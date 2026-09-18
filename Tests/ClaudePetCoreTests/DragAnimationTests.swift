import XCTest
@testable import ClaudePetCore

final class DragAnimationTests: XCTestCase {
    func row(_ dx: Double, _ dy: Double) -> SpriteRow? {
        DragAnimation.row(dx: dx, dy: dy)
    }

    func testHorizontalDragRuns() {
        XCTAssertEqual(row(8, 0), .runningRight)
        XCTAssertEqual(row(-8, 0), .runningLeft)
    }

    /// 세로로 더 움직이면 위든 아래든 점프. 시트에 떨어지는 행이 없어서 공중에 뜬 느낌으로 통일한다.
    func testVerticalDragJumps() {
        XCTAssertEqual(row(0, 8), .jumping)
        XCTAssertEqual(row(0, -8), .jumping)
        XCTAssertEqual(row(2, 9), .jumping)
    }

    /// 대각선은 더 많이 움직인 축을 따른다. 같으면 가로가 이긴다.
    func testDiagonalFollowsDominantAxis() {
        XCTAssertEqual(row(9, 2), .runningRight)
        XCTAssertEqual(row(-9, 2), .runningLeft)
        XCTAssertEqual(row(5, 5), .runningRight, "같으면 가로")
        XCTAssertEqual(row(-5, 5), .runningLeft)
    }

    /// 손이 멈춘 동안에는 달리게 두지 않는다. 평소 상태로 돌아가라는 뜻으로 nil.
    func testTinyMovementIsNotDragging() {
        XCTAssertNil(row(0, 0))
        XCTAssertNil(row(0.4, 0.4))
        XCTAssertNil(row(-0.9, 0.9))
    }

    func testThresholdIsTheBoundary() {
        XCTAssertNil(row(DragAnimation.threshold - 0.01, 0))
        XCTAssertEqual(row(DragAnimation.threshold, 0), .runningRight)
    }
}

// MARK: 드래그하는 동안 붙잡아 두는 행

final class AnimationDirectorHoldTests: XCTestCase {
    func director(_ state: PetState = .running) -> AnimationDirector {
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = row.nominalFrameCount }
        let d = AnimationDirector(frameCounts: counts, random: { 1 })
        d.setState(state)
        return d
    }

    /// 붙잡은 행은 상태 행과 일회성 연출을 모두 제친다. 드래그 중에는 그것만 보여야 한다.
    func testHeldRowWinsOverEverything() {
        let d = director()
        d.playOnce(.waving)
        d.hold(.runningRight)
        XCTAssertEqual(d.current.row, .runningRight)
        _ = d.advance()
        XCTAssertEqual(d.current.row, .runningRight)
    }

    /// 붙잡고 있는 동안에는 끝나지 않고 계속 돈다.
    func testHeldRowLoops() {
        let d = director()
        d.hold(.runningLeft)
        for _ in 0..<(SpriteRow.runningLeft.nominalFrameCount * 3) {
            XCTAssertEqual(d.advance().row, .runningLeft)
        }
    }

    /// 놓으면 원래 흐름으로 돌아간다.
    func testReleasingRestoresNormalFlow() {
        let d = director(.waiting)
        d.hold(.runningRight)
        XCTAssertEqual(d.current.row, .runningRight)
        d.hold(nil)
        XCTAssertEqual(d.current.row, .waiting)
    }

    /// 붙잡은 행이 바뀌면 처음 프레임부터 다시 간다. 방향이 바뀌었는데 중간부터 나오면 어색하다.
    func testChangingHeldRowRestartsFrames() {
        let d = director()
        d.hold(.runningRight)
        _ = d.advance(); _ = d.advance()
        XCTAssertNotEqual(d.current.index, 0)
        d.hold(.runningLeft)
        XCTAssertEqual(d.current.index, 0)
    }

    /// 같은 행을 다시 붙잡는 건 아무 일도 아니다. 드래그 이벤트마다 불려도 프레임이 멈추면 안 된다.
    func testHoldingSameRowDoesNotRestart() {
        let d = director()
        d.hold(.runningRight)
        _ = d.advance()
        let index = d.current.index
        d.hold(.runningRight)
        XCTAssertEqual(d.current.index, index)
    }

    /// 붙잡은 행은 가라앉은 idle 처럼 느려지면 안 된다. 손을 따라와야 한다.
    func testHeldRowRunsAtNormalSpeed() {
        let d = director(.idle)
        let slow = d.currentDurationMs
        d.hold(.runningRight)
        XCTAssertLessThan(d.currentDurationMs, slow)
    }

    /// 드래그 중 상태가 바뀌어도 화면은 붙잡은 행이 이긴다. 놓을 때 새 상태로 간다.
    func testStateChangeDuringDragIsDeferred() {
        let d = director(.running)
        d.hold(.runningRight)
        d.setState(.failed)
        XCTAssertEqual(d.current.row, .runningRight)
        d.hold(nil)
        XCTAssertEqual(d.current.row, .failed)
    }

    /// 동작 줄이기에서는 붙잡지 않는다.
    func testReducedMotionIgnoresHold() {
        let d = director(.waiting)
        d.reducedMotion = true
        d.hold(.runningRight)
        XCTAssertEqual(d.current.row, .waiting)
    }
}

// MARK: 바뀐 경우에만 알린다

extension AnimationDirectorHoldTests {
    /// 드래그 이벤트는 초당 수십 번 온다. 그때마다 호출자가 프레임 타이머를 다시 걸면
    /// 프레임 길이가 지나기 전에 초기화되어 펫이 첫 장에 멈춘다. 바뀐 경우에만 참을 돌려준다.
    func testHoldReportsWhetherItChanged() {
        let d = director()
        XCTAssertTrue(d.hold(.runningRight), "처음 붙잡을 때")
        XCTAssertFalse(d.hold(.runningRight), "같은 방향이 이어질 때")
        XCTAssertTrue(d.hold(.runningLeft), "방향이 바뀔 때")
        XCTAssertTrue(d.hold(nil), "놓을 때")
        XCTAssertFalse(d.hold(nil), "이미 놓여 있을 때")
    }

    func testHoldReportsNothingUnderReducedMotion() {
        let d = director()
        d.reducedMotion = true
        XCTAssertFalse(d.hold(.runningRight))
    }
}

// MARK: 느린 드래그에서도 끊기지 않게 모아서 판단

final class DragTrackerTests: XCTestCase {
    /// 이벤트 하나가 문턱값보다 작아도 멈춘 것이 아니다. 계속 모아서 넘으면 그때 방향을 정한다.
    /// 예전에는 작은 이벤트마다 "멈춤" 으로 보고 애니메이션을 내렸다 올려서 끊겨 보였다.
    func testSlowDragAccumulatesUntilItDecides() {
        var t = DragTracker()
        XCTAssertNil(t.accumulate(dx: 0.4, dy: 0), "아직 모자라다")
        XCTAssertNil(t.accumulate(dx: 0.4, dy: 0))
        XCTAssertNil(t.accumulate(dx: 0.4, dy: 0))
        XCTAssertNil(t.accumulate(dx: 0.4, dy: 0))
        XCTAssertEqual(t.accumulate(dx: 0.4, dy: 0), .runningRight, "모인 값이 문턱을 넘었다")
    }

    /// 방향을 정하고 나면 다시 모으기 시작한다. 직전 것이 남아 판단을 흐리면 안 된다.
    func testDecidingResetsTheAccumulator() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        XCTAssertNil(t.accumulate(dx: 0.5, dy: 0), "방금 컸다고 해서 다음이 공짜는 아니다")
    }

    /// 앞뒤로 흔들면 서로 지워진다. 제자리 떨림에 펫이 방향을 바꾸지 않는다.
    func testJitterCancelsOut() {
        var t = DragTracker()
        XCTAssertNil(t.accumulate(dx: 1.4, dy: 0))
        XCTAssertNil(t.accumulate(dx: -1.4, dy: 0))
        XCTAssertNil(t.accumulate(dx: 1.0, dy: 0))
    }

    /// 방향이 진짜로 바뀌면 따라 돈다.
    func testRealDirectionChangeIsFollowed() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        XCTAssertEqual(t.accumulate(dx: -10, dy: 0), .runningLeft)
    }

    func testVerticalAccumulationJumps() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 0, dy: 10), .jumping)
    }

    /// 손을 멈추면 호출자가 초기화한다. 그 뒤로는 처음부터 다시 모은다.
    func testResetClearsWhatWasGathered() {
        var t = DragTracker()
        XCTAssertNil(t.accumulate(dx: 1.5, dy: 0))
        t.reset()
        XCTAssertNil(t.accumulate(dx: 1.5, dy: 0), "초기화했으니 다시 모자라다")
    }
}

// MARK: 축을 갈아탈 때만 여유를 둔다

extension DragTrackerTests {
    /// 45도 근처에서 달리기와 점프가 번갈아 뜨면 프레임이 계속 처음으로 돌아가 끊겨 보인다.
    /// 이미 달리고 있으면 세로가 어지간히 커야 점프로 넘어간다.
    func testNearDiagonalKeepsTheCurrentAxis() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        XCTAssertEqual(t.accumulate(dx: 5, dy: 6), .runningRight, "조금 더 세로라고 바로 점프하지 않는다")
        XCTAssertEqual(t.accumulate(dx: 5, dy: 6), .runningRight)
    }

    /// 확실히 세로로 가면 넘어간다.
    func testClearAxisChangeStillSwitches() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        XCTAssertEqual(t.accumulate(dx: 2, dy: 10), .jumping)
    }

    /// 점프 중이면 반대로 가로가 어지간히 커야 달리기로 넘어간다.
    func testJumpingIsAlsoSticky() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 0, dy: 10), .jumping)
        XCTAssertEqual(t.accumulate(dx: 6, dy: 5), .jumping)
        XCTAssertEqual(t.accumulate(dx: 10, dy: 2), .runningRight)
    }

    /// 좌우를 뒤집는 데는 여유를 두지 않는다. 돌아서는 건 바로 따라가야 한다.
    func testTurningAroundIsImmediate() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        XCTAssertEqual(t.accumulate(dx: -3, dy: 0), .runningLeft)
        XCTAssertEqual(t.accumulate(dx: 3, dy: 0), .runningRight)
    }

    /// 초기화하면 여유도 사라진다. 다음 드래그는 처음부터 판단한다.
    func testResetForgetsTheStickyAxis() {
        var t = DragTracker()
        XCTAssertEqual(t.accumulate(dx: 10, dy: 0), .runningRight)
        t.reset()
        XCTAssertEqual(t.accumulate(dx: 3, dy: 4), .jumping, "여유가 없으면 더 큰 축을 따른다")
    }
}
