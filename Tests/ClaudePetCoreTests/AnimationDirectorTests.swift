import XCTest
@testable import ClaudePetCore

final class AnimationDirectorTests: XCTestCase {
    let counts: [SpriteRow: Int] = [.idle: 6, .runningRight: 8, .runningLeft: 8, .waving: 4, .jumping: 5,
                                    .failed: 8, .waiting: 6, .running: 6, .review: 6]

    func director(random: @escaping () -> Double = { 1.0 }) -> AnimationDirector {
        AnimationDirector(frameCounts: counts, random: random)
    }

    func rows(_ d: AnimationDirector, _ n: Int) -> [AnimationFrame] { (0..<n).map { _ in d.advance() } }

    func testStartsIdleAndLoops() {
        let d = director()
        XCTAssertEqual(d.current, AnimationFrame(row: .idle, index: 0))
        let frames = rows(d, 7)
        XCTAssertEqual(frames.map(\.index), [1, 2, 3, 4, 5, 0, 1])
        XCTAssertTrue(frames.allSatisfy { $0.row == .idle })
    }

    func testSetStateSwitchesBaseRow() {
        let d = director()
        d.setState(.waiting)
        XCTAssertEqual(d.current, AnimationFrame(row: .waiting, index: 0))
        XCTAssertEqual(d.advance().row, .waiting)
    }

    func testWaitingToRunningPlaysJumpOnce() {
        let d = director()
        d.setState(.waiting)
        d.setState(.running)
        XCTAssertEqual(d.current.row, .jumping)
        let frames = rows(d, 6)
        XCTAssertEqual(frames.map(\.row), [.jumping, .jumping, .jumping, .jumping, .running, .running])
        XCTAssertEqual(frames[4].index, 0)
    }

    func testIdleToRunningDoesNotJump() {
        let d = director()
        d.setState(.running)
        XCTAssertEqual(d.current.row, .running)
    }

    func testPlayOnceQueuesAfterCurrentOneShot() {
        let d = director()
        d.playOnce(.waving)
        XCTAssertEqual(d.current, AnimationFrame(row: .waving, index: 0))
        d.playOnce(.jumping)
        let frames = rows(d, 9)
        XCTAssertEqual(frames.map(\.row), [.waving, .waving, .waving, .jumping, .jumping, .jumping, .jumping, .jumping, .idle])
    }

    func testRunningWalksWhenRandomSaysSo() {
        var calls = 0
        let d = director(random: { calls += 1; return 0.1 }) // 0.1 < 0.3 → 산책, 0.1 < 0.5 → runningRight
        d.setState(.running)
        _ = rows(d, AnimationDirector.walkEveryTicks - 1)
        XCTAssertEqual(d.current.row, .running)
        let f = d.advance()
        XCTAssertEqual(f.row, .runningRight)
        XCTAssertEqual(f.index, 0)
        XCTAssertEqual(calls, 2)
    }

    func testRunningDoesNotWalkWhenRandomSaysNo() {
        let d = director(random: { 0.9 })
        d.setState(.running)
        let frames = rows(d, AnimationDirector.walkEveryTicks + 5)
        XCTAssertTrue(frames.allSatisfy { $0.row == .running })
    }

    func testNoWalkOutsideRunning() {
        let d = director(random: { 0.0 })
        d.setState(.waiting)
        let frames = rows(d, AnimationDirector.walkEveryTicks + 5)
        XCTAssertTrue(frames.allSatisfy { $0.row == .waiting })
    }

    func testMissingFrameCountFallsBackToOne() {
        let d = AnimationDirector(frameCounts: [:], random: { 1 })
        XCTAssertEqual(d.advance(), AnimationFrame(row: .idle, index: 0))
    }
}
