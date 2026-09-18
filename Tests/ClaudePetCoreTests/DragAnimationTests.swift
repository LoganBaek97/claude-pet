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
