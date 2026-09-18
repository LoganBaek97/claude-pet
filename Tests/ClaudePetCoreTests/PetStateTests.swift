import XCTest
@testable import ClaudePetCore

final class PetStateTests: XCTestCase {
    func testPriorityOrder() {
        XCTAssertLessThan(PetState.idle.priority, PetState.review.priority)
        XCTAssertLessThan(PetState.review.priority, PetState.running.priority)
        XCTAssertLessThan(PetState.running.priority, PetState.failed.priority)
        XCTAssertLessThan(PetState.failed.priority, PetState.waiting.priority)
    }

    func testEventMapping() {
        XCTAssertEqual(EventMapper.outcome(for: "SessionStart"), .set(.idle))
        XCTAssertEqual(EventMapper.outcome(for: "SessionEnd"), .remove)
        for e in ["UserPromptSubmit", "PreToolUse", "PostToolUse"] {
            XCTAssertEqual(EventMapper.outcome(for: e), .set(.running), e)
        }
        XCTAssertEqual(EventMapper.outcome(for: "PermissionRequest"), .set(.waiting))
        XCTAssertEqual(EventMapper.outcome(for: "Notification"), .set(.waiting))
        XCTAssertEqual(EventMapper.outcome(for: "PostToolUseFailure"), .set(.failed))
        XCTAssertEqual(EventMapper.outcome(for: "StopFailure"), .set(.failed))
        XCTAssertEqual(EventMapper.outcome(for: "Stop"), .set(.review))
        XCTAssertEqual(EventMapper.outcome(for: "PreCompact"), .ignore)
        XCTAssertEqual(EventMapper.outcome(for: "SubagentStart"), .ignore)
        XCTAssertEqual(EventMapper.outcome(for: "SubagentStop"), .ignore)
    }

    func testHookedEventsMatchSpec() {
        XCTAssertEqual(Set(EventMapper.hookedEvents), Set([
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
        ]))
        XCTAssertEqual(EventMapper.hookedEvents.count, 10)
    }

    func testSessionStateDecodesHookOutput() throws {
        let json = #"{"session_id":"s1","state":"running","event":"PreToolUse","tool":"Bash","cwd":"/Users/x/proj","ts":1789000000}"#
        let s = try JSONDecoder().decode(SessionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.sessionId, "s1")
        XCTAssertEqual(s.state, .running)
        XCTAssertEqual(s.projectName, "proj")
        XCTAssertEqual(s.timestamp, Date(timeIntervalSince1970: 1789000000))
    }

    func testProjectNameFallsBackToCwdWhenEmpty() throws {
        let json = #"{"session_id":"s1","state":"idle","event":"SessionStart","tool":"","cwd":"","ts":1}"#
        let s = try JSONDecoder().decode(SessionState.self, from: Data(json.utf8))
        XCTAssertEqual(s.projectName, "")
    }
}

// MARK: 이어지는 상태와 끝난 상태

extension PetStateTests {
    /// 지금 벌어지는 일은 계속 보여야 하고, 끝난 일은 몇 번 알리고 조용해지면 된다.
    func testOngoingStates() {
        XCTAssertTrue(PetState.running.isOngoing)
        XCTAssertTrue(PetState.waiting.isOngoing)
        XCTAssertFalse(PetState.review.isOngoing, "끝난 일")
        XCTAssertFalse(PetState.failed.isOngoing, "끝난 일")
        XCTAssertFalse(PetState.idle.isOngoing)
    }
}
