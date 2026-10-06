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

// MARK: Codex 세션

extension BubbleTextTests {
    func codex(_ state: PetState, tool: String = "", waiting: Int = 0) -> Aggregate {
        let s = SessionState(sessionId: "c", state: state, tool: tool, cwd: "/Users/x/my-project", agent: .codex, ts: 1)
        return Aggregate(state: state, session: s, waitingCount: waiting, liveSessionCount: 1)
    }

    /// Codex 세션만 앞에 에이전트 이름을 붙인다. Claude 는 지금까지와 같다.
    func testCodexSessionIsPrefixed() {
        XCTAssertEqual(BubbleText.text(for: codex(.running, tool: "shell")), "Codex · shell · my-project")
        XCTAssertEqual(BubbleText.text(for: codex(.running)), "Codex · 작업 중 · my-project")
        XCTAssertEqual(BubbleText.text(for: codex(.waiting, waiting: 2)), "Codex · 입력 대기 · my-project +1")
        XCTAssertEqual(BubbleText.text(for: codex(.review)), "Codex · 끝남 · my-project")
    }

    func testCodexIdleStaysHidden() {
        XCTAssertNil(BubbleText.text(for: codex(.idle)))
    }
}

// MARK: 세션별 한 줄

final class SessionBubbleTextTests: XCTestCase {
    func summary(_ state: PetState, tool: String = "", cwd: String = "/Users/x/my-project",
                 agent: Agent = .claude, id: String = "abcdef0123", ts: TimeInterval = 100) -> SessionSummary {
        SessionSummary(session: SessionState(sessionId: id, state: state, tool: tool, cwd: cwd, agent: agent, ts: ts),
                       state: state)
    }

    func testTitleIsProjectName() {
        XCTAssertEqual(BubbleText.title(for: summary(.running)), "my-project")
    }

    /// cwd 가 없으면 빈 카드가 되지 않도록 세션 id 앞자리를 쓴다.
    func testTitleFallsBackToSessionIdPrefix() {
        XCTAssertEqual(BubbleText.title(for: summary(.running, cwd: "", id: "abcdef0123")), "abcdef")
    }

    /// 도구 이름은 부제에 넣지 않는다.
    func testDetailPerState() {
        XCTAssertEqual(BubbleText.detail(for: summary(.running, tool: "Bash")), "작업 중")
        XCTAssertEqual(BubbleText.detail(for: summary(.waiting)), "입력 대기")
        XCTAssertEqual(BubbleText.detail(for: summary(.failed, tool: "Bash")), "실패")
        XCTAssertEqual(BubbleText.detail(for: summary(.review)), "끝남")
        XCTAssertEqual(BubbleText.detail(for: summary(.idle)), "유휴")
    }

    /// 에이전트 배지는 카드가 따로 그린다. 본문 글자에는 섞지 않는다.
    func testDetailDoesNotEmbedAgentName() {
        XCTAssertEqual(BubbleText.detail(for: summary(.running, tool: "shell", agent: .codex)), "작업 중")
    }

    /// 진행 중인 턴은 프롬프트를 보낸 때부터 센다. 마지막 도구 시각(ts)이 아니다.
    func testSubtitleCountsFromPrompt() {
        let s = SessionSummary(session: SessionState(sessionId: "s", state: .running, tool: "Bash",
                                                     promptTs: 100, ts: 280), state: .running)
        XCTAssertEqual(BubbleText.subtitle(for: s, now: Date(timeIntervalSince1970: 400)), "작업 중 · 5분")
        let w = SessionSummary(session: SessionState(sessionId: "s", state: .waiting, promptTs: 100, ts: 390), state: .waiting)
        XCTAssertEqual(BubbleText.subtitle(for: w, now: Date(timeIntervalSince1970: 400)), "입력 대기 · 5분")
    }

    /// 프롬프트 시각을 모르는 예전 파일은 마지막 신호부터 센다.
    func testSubtitleFallsBackToLastSignal() {
        XCTAssertEqual(BubbleText.subtitle(for: summary(.running, ts: 100), now: Date(timeIntervalSince1970: 130)), "작업 중 · 30초")
    }

    /// 끝난 턴은 프롬프트부터 끝날 때까지 걸린 총 시간을 단다. 지금 시각과는 상관없다.
    func testSubtitleShowsTotalWhenFinished() {
        func finished(_ state: PetState, event: String = "Stop", start: TimeInterval?) -> SessionSummary {
            SessionSummary(session: SessionState(sessionId: "s", state: state, event: event,
                                                 promptTs: start, ts: 1000), state: state)
        }
        let later = Date(timeIntervalSince1970: 99_999)
        XCTAssertEqual(BubbleText.subtitle(for: finished(.review, start: 700), now: later), "끝남 · 총 5분")
        XCTAssertEqual(BubbleText.subtitle(for: finished(.failed, event: "StopFailure", start: 958), now: later), "실패 · 총 42초")
        // 시작을 모르면 시간을 뺀다.
        XCTAssertEqual(BubbleText.subtitle(for: finished(.review, start: nil), now: later), "끝남")
    }

    /// 도구 실패 뒤에는 턴이 이어지므로 흐르는 시간을 단다. 유휴에는 시간이 없다.
    func testSubtitleForMidTurnFailureAndIdle() {
        let failed = SessionSummary(session: SessionState(sessionId: "s", state: .failed, event: "PostToolUseFailure",
                                                          promptTs: 100, ts: 200), state: .failed)
        XCTAssertEqual(BubbleText.subtitle(for: failed, now: Date(timeIntervalSince1970: 400)), "실패 · 5분")
        XCTAssertEqual(BubbleText.subtitle(for: summary(.idle), now: Date(timeIntervalSince1970: 10_000)), "유휴")
    }

    func testDuration() {
        XCTAssertEqual(BubbleText.duration(0), "1초")
        XCTAssertEqual(BubbleText.duration(42), "42초")
        XCTAssertEqual(BubbleText.duration(300), "5분")
        XCTAssertEqual(BubbleText.duration(3600), "1시간")
        XCTAssertEqual(BubbleText.duration(3600 + 25 * 60), "1시간 25분")
    }

    func testElapsed() {
        XCTAssertEqual(BubbleText.elapsed(0), "방금")
        XCTAssertEqual(BubbleText.elapsed(4), "방금")
        XCTAssertEqual(BubbleText.elapsed(5), "5초")
        XCTAssertEqual(BubbleText.elapsed(59), "59초")
        XCTAssertEqual(BubbleText.elapsed(60), "1분")
        XCTAssertEqual(BubbleText.elapsed(59 * 60), "59분")
        XCTAssertEqual(BubbleText.elapsed(60 * 60), "1시간")
        XCTAssertEqual(BubbleText.elapsed(5 * 3600), "5시간")
    }

    /// 음수(시계가 어긋난 상태 파일)도 말이 되게 나와야 한다.
    func testElapsedClampsNegative() {
        XCTAssertEqual(BubbleText.elapsed(-30), "방금")
    }
}
