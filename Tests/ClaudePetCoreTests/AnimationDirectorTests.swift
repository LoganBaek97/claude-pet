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
        XCTAssertEqual(d.current.row, .running, "작업 중은 가라앉지 않고 계속 돈다")
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

    // MARK: 3회 재생 후 정착 (Codex `Ulo`) — 끝난 일에만

    /// 끝난 일은 세 번 알리고 느린 idle 로 가라앉는다.
    /// 작업 중·입력 대기는 이어지는 상태라 가라앉지 않는다(`testOngoingStatesNeverSettle`).
    func testFinishedStatePlaysThreeTimesThenSettlesIntoSlowIdle() {
        let d = director()
        d.setState(.review)
        let burst = rows(d, 17)
        XCTAssertTrue(burst.allSatisfy { $0.row == .review })
        XCTAssertEqual(burst.map(\.index), [1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5, 0, 1, 2, 3, 4, 5])
        XCTAssertEqual(d.currentDurationMs, 280)
        let settled = d.advance()
        XCTAssertEqual(settled, AnimationFrame(row: .idle, index: 0))
        XCTAssertEqual(d.currentDurationMs, 280 * 6)
        XCTAssertTrue(rows(d, 30).allSatisfy { $0.row == .idle })
    }

    /// 끝난 일은 정해진 횟수만 알리고 가라앉는다. review 는 150×5+280 = 1030ms 를 3회, 3090ms.
    /// (작업 중·입력 대기는 이어지는 상태라 가라앉지 않으므로 여기서 재지 않는다.)
    func testBurstDurationsMatchCodex() {
        let d = director()
        d.setState(.review)
        var total = 0
        var guardCount = 0
        while d.current.row == .review, guardCount < 500 {
            total += d.currentDurationMs; _ = d.advance(); guardCount += 1
        }
        XCTAssertEqual(total, 3090)
    }

    func testStateChangeRestartsBurst() {
        let d = director()
        d.setState(.failed)
        _ = rows(d, 30)
        XCTAssertEqual(d.current.row, .idle, "끝난 일은 가라앉는다")
        d.setState(.review)
        XCTAssertEqual(d.current, AnimationFrame(row: .review, index: 0))
        XCTAssertEqual(d.currentDurationMs, 150)
    }

    func testWaitingToRunningJumpsThenKeepsRunning() {
        let d = director()
        d.setState(.waiting)
        d.setState(.running)
        // jumping 5프레임(advance 4회 뒤 마지막 프레임) 뒤로는 계속 running 이다. 가라앉지 않는다.
        let frames = rows(d, 4 + 24)
        XCTAssertEqual(frames.prefix(4).map(\.row), [.jumping, .jumping, .jumping, .jumping])
        XCTAssertTrue(frames[4...].allSatisfy { $0.row == .running }, "작업 중은 계속 돈다")
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

// MARK: 이어지는 상태는 가라앉지 않는다

extension AnimationDirectorTests {
    func fullDirector(_ state: PetState) -> AnimationDirector {
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = row.nominalFrameCount }
        let d = AnimationDirector(frameCounts: counts, random: { 1 })
        d.setState(state)
        return d
    }

    /// 작업이 10분 걸려도 펫은 2.5초만 움직이고 나머지는 중립이었다.
    /// 지금 진행되는 상태는 그 상태인 동안 계속 돈다.
    func testOngoingStatesNeverSettle() {
        for state in [PetState.running, .waiting] {
            let d = fullDirector(state)
            let row = SpriteRow.base(for: state)
            for _ in 0..<(row.nominalFrameCount * 20) {
                XCTAssertEqual(d.advance().row, row, "\(state) 는 계속 돌아야 한다")
            }
        }
    }

    /// 끝난 일은 몇 번 알리고 조용해진다. 화면이 계속 움직이면 피곤하다.
    func testFinishedStatesStillSettle() {
        for state in [PetState.review, .failed] {
            let d = fullDirector(state)
            var frames = 0
            while d.current.row == SpriteRow.base(for: state), frames < 500 {
                _ = d.advance(); frames += 1
            }
            XCTAssertEqual(d.current.row, .idle, "\(state) 는 가라앉아야 한다")
        }
    }

    /// 이어지는 상태는 느려지지도 않는다. 가라앉은 idle 만 1/6 속도다.
    func testOngoingStatesKeepNormalSpeed() {
        let d = fullDirector(.running)
        let fast = d.currentDurationMs
        for _ in 0..<(SpriteRow.running.nominalFrameCount * 5) { _ = d.advance() }
        XCTAssertEqual(d.currentDurationMs, fast, "한참 돌아도 속도가 그대로여야 한다")
    }
}

// MARK: 합성과 애니메이션을 이은 사슬

/// "작업 중에는 계속 움직이고, 한동안 아무 일이 없으면 유휴로 가라앉아 느려진다" 를
/// 두 조각이 함께 만들어 낸다. 어느 한쪽만 보면 규칙이 반쪽이라 여기서 이어 본다.
///
/// - 합성(`StateAggregator`)이 시간을 본다. 마지막 이벤트로부터 `runningStaleAfter` 가 지나면 idle.
/// - 디렉터는 받은 상태를 그대로 보여 준다. 이어지는 상태면 계속, idle 이면 느린 idle.
final class SettleChainTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func director() -> AnimationDirector {
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = row.nominalFrameCount }
        return AnimationDirector(frameCounts: counts, random: { 1 })
    }

    func session(ageSeconds: TimeInterval) -> SessionState {
        SessionState(sessionId: "s", state: .running, cwd: "/p/x", agentPid: 1,
                     ts: now.timeIntervalSince1970 - ageSeconds)
    }

    /// 도구를 계속 부르는 세션. 몇 분이 지나도 펫은 작업 중 동작을 돌린다.
    func testBusySessionKeepsAnimating() {
        let agg = StateAggregator.aggregate([session(ageSeconds: 5)], now: now) { _ in .alive }
        XCTAssertEqual(agg.state, .running)

        let d = director()
        d.setState(agg.state)
        let fast = d.currentDurationMs
        for _ in 0..<60 { XCTAssertEqual(d.advance().row, .running) }
        XCTAssertEqual(d.currentDurationMs, fast, "속도도 그대로다")
    }

    /// 한동안 아무 일이 없으면 합성이 유휴로 내린다. 그때 비로소 느려진다.
    func testQuietSessionGoesIdleAndSlowsDown() {
        let quiet = session(ageSeconds: StateAggregator.runningStaleAfter + 60)
        let agg = StateAggregator.aggregate([quiet], now: now) { _ in .alive }
        XCTAssertEqual(agg.state, .idle, "\(Int(StateAggregator.runningStaleAfter / 60))분 조용하면 유휴")

        let d = director()
        d.setState(.running)
        let busy = d.currentDurationMs
        d.setState(agg.state)
        XCTAssertEqual(d.current.row, .idle)
        XCTAssertGreaterThan(d.currentDurationMs, busy, "유휴는 느리게 돈다")
        XCTAssertEqual(d.currentDurationMs, 280 * AnimationDirector.settledIdleSlowdown)
    }
}
