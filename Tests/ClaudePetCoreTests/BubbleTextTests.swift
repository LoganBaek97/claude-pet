import XCTest
@testable import ClaudePetCore

final class BubbleTextTests: XCTestCase {
    func agg(_ state: PetState, tool: String = "", cwd: String = "/Users/x/gguge-frontend", waiting: Int = 0) -> Aggregate {
        Aggregate(state: state, session: SessionState(sessionId: "s", state: state, tool: tool, cwd: cwd, ts: 1), waitingCount: waiting, liveSessionCount: 1)
    }

    func testRunningShowsToolAndProject() {
        XCTAssertEqual(BubbleText.text(for: agg(.running, tool: "Bash")), "Bash · gguge-frontend")
        XCTAssertEqual(BubbleText.text(for: agg(.running)), "작업 중 · gguge-frontend")
    }

    func testWaitingShowsCountWhenMoreThanOne() {
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, waiting: 1)), "입력 대기 · gguge-frontend")
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, waiting: 3)), "입력 대기 · gguge-frontend +2")
    }

    func testFailedPrefersTool() {
        XCTAssertEqual(BubbleText.text(for: agg(.failed, tool: "Bash")), "실패 · Bash")
        XCTAssertEqual(BubbleText.text(for: agg(.failed)), "실패 · gguge-frontend")
    }

    func testReviewAndIdle() {
        XCTAssertEqual(BubbleText.text(for: agg(.review)), "끝남 · gguge-frontend")
        XCTAssertNil(BubbleText.text(for: agg(.idle)))
        XCTAssertNil(BubbleText.text(for: .empty))
    }

    func testEmptyProjectNameOmitsSeparator() {
        XCTAssertEqual(BubbleText.text(for: agg(.running, tool: "Read", cwd: "")), "Read")
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, cwd: "")), "입력 대기")
    }

    func testEmphasis() {
        XCTAssertTrue(BubbleText.isEmphasized(.waiting))
        XCTAssertTrue(BubbleText.isEmphasized(.failed))
        XCTAssertFalse(BubbleText.isEmphasized(.running))
    }
}
