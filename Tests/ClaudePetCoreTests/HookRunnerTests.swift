import Foundation
import Testing
@testable import ClaudePetCore

// MARK: - FakeAncestry

struct FakeAncestry: ProcessAncestry {
    let nodes: [ProcessNode]

    func chain(from startPid: Int32, limit: Int) -> [ProcessNode] {
        guard let startIdx = nodes.firstIndex(where: { $0.pid == startPid }) else { return [] }
        return Array(nodes[startIdx...].prefix(limit))
    }
}

// MARK: - Helpers

private let selfPid: Int32 = 9999
private let emptyAncestry = FakeAncestry(nodes: [ProcessNode(pid: selfPid, parentPid: 0, executablePath: "/usr/bin/test")])

private func fixture(_ name: String) -> Data {
    let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("hook/fixtures")
    return (try? Data(contentsOf: fixturesDir.appendingPathComponent(name))) ?? Data()
}

private func decide(_ data: Data, agent: Agent = .claude, env: [String: String] = [:],
                    ancestry: ProcessAncestry = emptyAncestry, rule: HostAppRule = .macOS) -> HookAction {
    HookRunner.decide(input: data, agent: agent, environment: env,
                      ancestry: ancestry, selfPid: selfPid, hostRule: rule, now: Date())
}

private func decideFixture(_ name: String, agent: Agent = .claude,
                            env: [String: String] = [:],
                            ancestry: ProcessAncestry = emptyAncestry,
                            rule: HostAppRule = .macOS) -> HookAction {
    decide(fixture(name), agent: agent, env: env, ancestry: ancestry, rule: rule)
}

// MARK: - Basic event mapping

@Test func preToolUseWritesRunning() throws {
    let action = decideFixture("pre-tool-use.json")
    guard case .write(let s) = action else { throw TestError("expected .write, got \(action)") }
    #expect(s.state == .running)
    #expect(s.event == "PreToolUse")
    #expect(s.tool == "Bash")
    #expect(s.cwd == "/Users/x/proj")
    #expect(s.transcript == "/Users/x/.claude/projects/p/sess-1.jsonl")
    #expect(s.agent == .claude)
    #expect(s.sessionId == "sess-1")
}

@Test func sessionEndReturnsRemove() {
    let action = decideFixture("session-end.json")
    #expect(action == .remove(sessionId: "sess-1"))
}

@Test func stopWritesReview() throws {
    let action = decideFixture("stop.json")
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.state == .review)
    #expect(s.event == "Stop")
}

@Test func permissionRequestWritesWaiting() throws {
    let action = decideFixture("permission-request.json")
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.state == .waiting)
    #expect(s.tool == "Edit")
    #expect(s.transcript == "")  // absent in fixture
}

@Test func postToolUseFailureWritesFailed() throws {
    let action = decideFixture("post-tool-use-failure.json")
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.state == .failed)
}

// MARK: - Ignored inputs

@Test func noSessionIdIgnored() {
    #expect(decideFixture("no-session.json") == .ignore)
}

@Test func emptyDataIgnored() {
    #expect(decide(Data()) == .ignore)
}

@Test func brokenJsonIgnored() {
    #expect(decide(Data("{not json".utf8)) == .ignore)
}

@Test func unknownEventIgnored() {
    #expect(decideFixture("unknown-event.json") == .ignore)
}

@Test func subagentStopIgnored() {
    #expect(decideFixture("subagent-stop.json") == .ignore)
}

// MARK: - Codex interrupt

@Test func codexInterruptWritesIdle() throws {
    let action = decideFixture("codex-interrupt.json", agent: .codex)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.state == .idle)
    #expect(s.event == "Interrupt")
    #expect(s.agent == .codex)
    #expect(s.agentId == "codex")
}

// MARK: - host_session

@Test func hostSessionAcceptedForClaude() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "local_abc-123"]
    let action = decideFixture("pre-tool-use.json", env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == "local_abc-123")
}

@Test func hostSessionRejectedMissingLocalPrefix() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "session_abc"]
    let action = decideFixture("pre-tool-use.json", env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == nil || s.hostSessionId == "")
}

@Test func hostSessionRejectedEmptyRest() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "local_"]
    let action = decideFixture("pre-tool-use.json", env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == nil || s.hostSessionId == "")
}

@Test func hostSessionRejectedTooLong() throws {
    let longId = "local_" + String(repeating: "a", count: 65)
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": longId]
    let action = decideFixture("pre-tool-use.json", env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == nil || s.hostSessionId == "")
}

@Test func hostSessionRejectedBadChars() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "local_has_underscore"]
    let action = decideFixture("pre-tool-use.json", env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == nil || s.hostSessionId == "")
}

@Test func hostSessionIgnoredForCodex() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e"]
    let action = decideFixture("pre-tool-use.json", agent: .codex, env: env)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostSessionId == nil || s.hostSessionId == "")
}

// MARK: - agent_pid

// 체인: hook(9999) → sh(100) → claude(200) → Ghostty(300)
private let macChain = FakeAncestry(nodes: [
    ProcessNode(pid: 9999, parentPid: 100, executablePath: "/usr/bin/test"),
    ProcessNode(pid: 100,  parentPid: 200, executablePath: "/bin/sh"),
    ProcessNode(pid: 200,  parentPid: 300, executablePath: "/Users/x/.local/share/claude/versions/2.1.274"),
    ProcessNode(pid: 300,  parentPid: 1,   executablePath: "/Applications/Ghostty.app/Contents/MacOS/ghostty"),
])

@Test func agentPidFindsNearestAgent() throws {
    let action = decideFixture("pre-tool-use.json", ancestry: macChain, rule: .macOS)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.agentPid == 200)
}

@Test func hostAppMacRuleFindsGhostty() throws {
    let action = decideFixture("pre-tool-use.json", ancestry: macChain, rule: .macOS)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostApp == "/Applications/Ghostty.app")
    #expect(s.hostPid == 300)
}

@Test func hostAppSkippedWhenHostSession() throws {
    let env = ["CLAUDE_CODE_HOST_SESSION_ID": "local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e"]
    let action = decideFixture("pre-tool-use.json", env: env, ancestry: macChain, rule: .macOS)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostPid == 0 || s.hostPid == nil)
    #expect(s.hostApp == "" || s.hostApp == nil)
}

// Windows 체인: hook → bash → claude.exe → VSCode
private let windowsChain = FakeAncestry(nodes: [
    ProcessNode(pid: 9999, parentPid: 500, executablePath: "C:\\claude-pet\\claude-pet.exe"),
    ProcessNode(pid: 500,  parentPid: 600, executablePath: "C:\\Program Files\\Git\\usr\\bin\\bash.exe"),
    ProcessNode(pid: 600,  parentPid: 700, executablePath: "C:\\Users\\x\\.local\\bin\\claude.exe"),
    ProcessNode(pid: 700,  parentPid: 1,   executablePath: "C:\\Users\\x\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe"),
])

@Test func windowsChainAgentPidIsClaudeExe() throws {
    let action = decideFixture("pre-tool-use.json", ancestry: windowsChain, rule: .windows)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.agentPid == 600)
}

@Test func windowsChainHostAppIsVSCode() throws {
    let action = decideFixture("pre-tool-use.json", ancestry: windowsChain, rule: .windows)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.hostApp == "C:\\Users\\x\\AppData\\Local\\Programs\\Microsoft VS Code\\Code.exe")
    #expect(s.hostPid == 700)
}

// node.exe 체인: agent pid 는 없다(0)
private let nodeChain = FakeAncestry(nodes: [
    ProcessNode(pid: 9999, parentPid: 800, executablePath: "/usr/bin/test"),
    ProcessNode(pid: 800,  parentPid: 1,   executablePath: "/usr/local/bin/node"),
])

@Test func nodeChainAgentPidIsZero() throws {
    let action = decideFixture("pre-tool-use.json", ancestry: nodeChain, rule: .macOS)
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.agentPid == 0 || s.agentPid == nil)
}

// MARK: - Hangul round-trip

@Test func hangulCwdAndToolRoundTrip() throws {
    let action = decideFixture("pre-tool-use-hangul.json")
    guard case .write(let s) = action else { throw TestError("expected .write") }
    #expect(s.cwd == "/Users/x/프로젝트 폴더")
    #expect(s.tool == "도구")
    #expect(s.state == .running)
    #expect(s.sessionId == "sess-hangul")
}

// MARK: - perform: write and remove

@Test func performWritesValidJson() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HookRunnerTests-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let action = decideFixture("pre-tool-use.json")
    HookRunner.perform(action, stateDirectory: dir)

    let file = dir.appendingPathComponent("sess-1.json")
    #expect(FileManager.default.fileExists(atPath: file.path))
    let data = try Data(contentsOf: file)
    let decoded = try JSONDecoder().decode(SessionState.self, from: data)
    #expect(decoded.sessionId == "sess-1")
    #expect(decoded.state == .running)
}

@Test func performRemoveDeletesFile() throws {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HookRunnerTests-rm-\(ProcessInfo.processInfo.processIdentifier)")
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Pre-create the file
    let file = dir.appendingPathComponent("sess-1.json")
    try Data("{}".utf8).write(to: file)
    #expect(FileManager.default.fileExists(atPath: file.path))

    HookRunner.perform(.remove(sessionId: "sess-1"), stateDirectory: dir)
    #expect(!FileManager.default.fileExists(atPath: file.path))

    // Tmp files cleaned
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
    let tmps = contents.filter { $0.contains(".tmp.") }
    #expect(tmps.isEmpty)
}

@Test func performIgnoreIsNoop() {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("HookRunnerTests-ignore-\(ProcessInfo.processInfo.processIdentifier)")
    HookRunner.perform(.ignore, stateDirectory: dir)
    // No directory created, no crash
    #expect(!FileManager.default.fileExists(atPath: dir.path))
}

// MARK: - Helpers

private struct TestError: Error, CustomStringConvertible {
    let description: String
    init(_ msg: String) { self.description = msg }
}
