import XCTest
@testable import ClaudePetCore

final class BubbleTextTests: XCTestCase {
    func agg(_ state: PetState, tool: String = "", cwd: String = "/Users/x/my-project", waiting: Int = 0) -> Aggregate {
        Aggregate(state: state, session: SessionState(sessionId: "s", state: state, tool: tool, cwd: cwd, ts: 1), waitingCount: waiting, liveSessionCount: 1)
    }

    func testRunningShowsToolAndProject() {
        XCTAssertEqual(BubbleText.text(for: agg(.running, tool: "Bash")), "Bash · my-project")
        XCTAssertEqual(BubbleText.text(for: agg(.running)), "작업 중 · my-project")
    }

    func testWaitingShowsCountWhenMoreThanOne() {
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, waiting: 1)), "입력 대기 · my-project")
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, waiting: 3)), "입력 대기 · my-project +2")
    }

    func testFailedPrefersTool() {
        XCTAssertEqual(BubbleText.text(for: agg(.failed, tool: "Bash")), "실패 · Bash")
        XCTAssertEqual(BubbleText.text(for: agg(.failed)), "실패 · my-project")
    }

    func testReviewAndIdle() {
        XCTAssertEqual(BubbleText.text(for: agg(.review)), "끝남 · my-project")
        XCTAssertNil(BubbleText.text(for: agg(.idle)))
        XCTAssertNil(BubbleText.text(for: .empty))
    }

    func testEmptyProjectNameOmitsSeparator() {
        XCTAssertEqual(BubbleText.text(for: agg(.running, tool: "Read", cwd: "")), "Read")
        XCTAssertEqual(BubbleText.text(for: agg(.waiting, cwd: "")), "입력 대기")
    }

    func testEmphasisSeparatesQuestionFromFailure() {
        XCTAssertEqual(BubbleText.emphasis(for: .waiting), .question)
        XCTAssertEqual(BubbleText.emphasis(for: .failed), .failure)
        for state in [PetState.running, .review, .idle] {
            XCTAssertEqual(BubbleText.emphasis(for: state), BubbleEmphasis.none, "\(state) 는 강조하지 않는다")
        }
    }

    func testOnlyEmphasizedLevelsAreEmphasized() {
        XCTAssertTrue(BubbleEmphasis.question.isEmphasized)
        XCTAssertTrue(BubbleEmphasis.failure.isEmphasized)
        XCTAssertFalse(BubbleEmphasis.none.isEmphasized)
    }
}
