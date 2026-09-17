import XCTest
@testable import ClaudePetCore

final class AgentTests: XCTestCase {
    let home = URL(fileURLWithPath: "/Users/x", isDirectory: true)

    func testInterruptSettlesToIdle() {
        XCTAssertEqual(EventMapper.outcome(for: "Interrupt"), .set(.idle))
    }

    func testClaudeHooksEveryEventTheMapperKnows() {
        XCTAssertEqual(Agent.claude.hookedEvents, EventMapper.hookedEvents)
    }

    func testCodexHooksOnlyEventsCodexEmits() {
        XCTAssertEqual(Agent.codex.hookedEvents, [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "Stop", "Interrupt",
        ])
    }

    /// Codex 는 SessionEnd 와 Interrupt 훅을 최대 3초까지만 기다린다.
    func testCodexShortensTimeoutForSessionEndAndInterrupt() {
        XCTAssertEqual(Agent.codex.timeout(for: "SessionEnd"), 3)
        XCTAssertEqual(Agent.codex.timeout(for: "Interrupt"), 3)
        XCTAssertEqual(Agent.codex.timeout(for: "PreToolUse"), 5)
        XCTAssertEqual(Agent.claude.timeout(for: "SessionEnd"), 5)
    }

    func testSettingsFilePerAgent() {
        XCTAssertEqual(Agent.claude.settingsFile(home: home).path, "/Users/x/.claude/settings.json")
        XCTAssertEqual(Agent.codex.settingsFile(home: home).path, "/Users/x/.codex/hooks.json")
    }

    func testDisplayName() {
        XCTAssertEqual(Agent.claude.displayName, "Claude Code")
        XCTAssertEqual(Agent.codex.displayName, "Codex")
    }

    /// Claude 는 항상 대상이고, Codex 는 ~/.codex 디렉터리가 있을 때만 대상이다.
    func testInstallTargetsFollowCodexDirectory() throws {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tmp) }

        XCTAssertEqual(Agent.installTargets(home: tmp), [.claude])
        try FileManager.default.createDirectory(at: tmp.appendingPathComponent(".codex"), withIntermediateDirectories: true)
        XCTAssertEqual(Agent.installTargets(home: tmp), [.claude, .codex])
    }

    func testAgentParsesFromCommandArgument() {
        XCTAssertEqual(Agent(rawValue: "codex"), .codex)
        XCTAssertEqual(Agent(rawValue: "claude"), .claude)
        XCTAssertNil(Agent(rawValue: "gemini"))
    }
}

// MARK: 설치 뒤 안내

extension AgentTests {
    /// Codex 는 등록만으로는 훅이 돌지 않고 사용자가 /hooks 에서 신뢰해야 한다. 그 안내가 있어야 한다.
    func testCodexNeedsTrustNoteAfterInstall() {
        XCTAssertNil(Agent.claude.postInstallNote)
        let note = Agent.codex.postInstallNote
        XCTAssertNotNil(note)
        XCTAssertTrue(note?.contains("/hooks") == true, "\(note ?? "")")
    }
}
