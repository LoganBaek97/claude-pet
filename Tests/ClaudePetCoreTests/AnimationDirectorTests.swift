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

    /// 누적 재생 시간이 `ms` 를 넘기기 직전까지 진행한다. 반환값: 진행한 프레임 수.
    func advance(_ d: AnimationDirector, untilElapsed ms: Int) -> Int {
        var elapsed = 0, n = 0
        while elapsed + d.currentDurationMs < ms { elapsed += d.currentDurationMs; _ = d.advance(); n += 1 }
        return n
    }

    func testRunningWalksWhenRandomSaysSo() {
        var calls = 0
        let d = director(random: { calls += 1; return 0.1 }) // 0.1 < 0.3 → 산책, 0.1 < 0.5 → runningRight
        d.setState(.running)
        _ = advance(d, untilElapsed: AnimationDirector.walkEveryMs)
        XCTAssertEqual(d.current.row, .idle, "20초면 이미 가라앉아 있다")
        XCTAssertEqual(calls, 0)
        let f = d.advance()
        XCTAssertEqual(f.row, .runningRight)
        XCTAssertEqual(f.index, 0)
        XCTAssertEqual(calls, 2)
    }

    func testRunningDoesNotWalkWhenRandomSaysNo() {
        let d = director(random: { 0.9 })
        d.setState(.running)
        let frames = rows(d, 200)
        XCTAssertFalse(frames.contains { $0.row == .runningRight || $0.row == .runningLeft })
    }

    func testNoWalkOutsideRunning() {
        let d = director(random: { 0.0 })
        d.setState(.waiting)
        let frames = rows(d, 200)
        XCTAssertFalse(frames.contains { $0.row == .runningRight || $0.row == .runningLeft })
    }

    // MARK: 행별 프레임 길이 (Codex 표)

    func testFrameDurationsFollowCodexTable() {
        XCTAssertEqual((0..<6).map { SpriteRow.idle.frameDurationMs(index: $0, of: 6) }, [280, 110, 110, 140, 140, 320])
        XCTAssertEqual((0..<6).map { SpriteRow.running.frameDurationMs(index: $0, of: 6) }, [120, 120, 120, 120, 120, 220])
        XCTAssertEqual((0..<4).map { SpriteRow.waving.frameDurationMs(index: $0, of: 4) }, [140, 140, 140, 280])
        XCTAssertEqual((0..<8).map { SpriteRow.failed.frameDurationMs(index: $0, of: 8) }, Array(repeating: 140, count: 7) + [240])
        XCTAssertEqual((0..<6).map { SpriteRow.waiting.frameDurationMs(index: $0, of: 6) }, Array(repeating: 150, count: 5) + [260])
        XCTAssertEqual((0..<6).map { SpriteRow.review.frameDurationMs(index: $0, of: 6) }, Array(repeating: 150, count: 5) + [280])
        XCTAssertEqual(SpriteRow.runningLeft.frameDurationMs(index: 7, of: 8), 220)
        XCTAssertEqual(SpriteRow.jumping.frameDurationMs(index: 4, of: 5), 280)
    }

    func testShortRowKeepsLongLastFrame() {
        XCTAssertEqual((0..<3).map { SpriteRow.idle.frameDurationMs(index: $0, of: 3) }, [280, 110, 320])
        XCTAssertEqual(SpriteRow.running.frameDurationMs(index: 0, of: 1), 220)
    }

    func testIdleStateRunsSlowIdleFromTheStart() {
        let d = director()
        let durations = (0..<6).map { _ in let ms = d.currentDurationMs; _ = d.advance(); return ms }
        XCTAssertEqual(durations, [280, 110, 110, 140, 140, 320].map { $0 * 6 })
        XCTAssertEqual(durations.reduce(0, +), 6600)
    }

    func testOneShotPlaysAtFullSpeedEvenWhileIdle() {
        let d = director()
        d.playOnce(.waving)
        XCTAssertEqual(d.currentDurationMs, 140)
        _ = rows(d, 3)
        XCTAssertEqual(d.current, AnimationFrame(row: .waving, index: 3))
        XCTAssertEqual(d.currentDurationMs, 280)
        _ = d.advance()
        XCTAssertEqual(d.current.row, .idle)
        XCTAssertEqual(d.currentDurationMs, 280 * 6)
    }

    // MARK: 3회 재생 후 정착 (Codex `Ulo`)

    func testNonIdleStatePlaysThreeTimesThenSettlesIntoSlowIdle() {
        let d = director()
        d.setState(.running)
        let burst = rows(d, 17)
        XCTAssertTrue(burst.allSatisfy { $0.row == .running })
        XCTAssertEqual(burst.map(\.index), [1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5])
        XCTAssertEqual(d.currentDurationMs, 220)
        let settled = d.advance()
        XCTAssertEqual(settled, AnimationFrame(row: .idle, index: 0))
        XCTAssertEqual(d.currentDurationMs, 280 * 6)
        XCTAssertTrue(rows(d, 30).allSatisfy { $0.row == .idle })
    }

    func testBurstDurationsMatchCodex() {
        // running 은 120×5+220 = 820ms 를 3회, 2460ms 뒤에 가라앉는다.
        let d = director()
        d.setState(.running)
        var total = 0
        while d.current.row == .running { total += d.currentDurationMs; _ = d.advance() }
        XCTAssertEqual(total, 2460)
    }

    func testStateChangeRestartsBurst() {
        let d = director()
        d.setState(.running)
        _ = rows(d, 18)
        XCTAssertEqual(d.current.row, .idle)
        d.setState(.review)
        XCTAssertEqual(d.current, AnimationFrame(row: .review, index: 0))
        XCTAssertEqual(d.currentDurationMs, 150)
    }

    func testWaitingToRunningJumpsThenBurstsThenSettles() {
        let d = director()
        d.setState(.waiting)
        d.setState(.running)
        // jumping 5프레임(advance 4회 뒤 마지막 프레임) → running 6프레임×3회 → idle
        let frames = rows(d, 4 + 18 + 1)
        XCTAssertEqual(frames.prefix(4).map(\.row), [.jumping, .jumping, .jumping, .jumping])
        XCTAssertTrue(frames[4..<22].allSatisfy { $0.row == .running })
        XCTAssertEqual(frames.last, AnimationFrame(row: .idle, index: 0))
    }

    // MARK: 감속 모션

    func testReducedMotionShowsFirstFrameOnly() {
        let d = director()
        d.reducedMotion = true
        d.setState(.waiting)
        XCTAssertEqual(d.current, AnimationFrame(row: .waiting, index: 0))
        XCTAssertEqual(rows(d, 5), Array(repeating: AnimationFrame(row: .waiting, index: 0), count: 5))
        d.playOnce(.waving)
        XCTAssertEqual(d.current, AnimationFrame(row: .waiting, index: 0))
        d.reducedMotion = false
        XCTAssertEqual(d.advance(), AnimationFrame(row: .waiting, index: 1))
    }

    func testTurningReducedMotionOnDropsOneShots() {
        let d = director()
        d.playOnce(.waving)
        _ = rows(d, 2)
        d.reducedMotion = true
        XCTAssertEqual(d.current, AnimationFrame(row: .idle, index: 0))
    }

    func testMissingFrameCountFallsBackToOne() {
        let d = AnimationDirector(frameCounts: [:], random: { 1 })
        XCTAssertEqual(d.advance(), AnimationFrame(row: .idle, index: 0))
    }
}
