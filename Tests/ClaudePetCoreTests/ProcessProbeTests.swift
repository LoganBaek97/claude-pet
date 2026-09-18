import XCTest
@testable import ClaudePetCore

final class ProcessProbeTests: XCTestCase {
    let probe = ProcessProbe()

    func session(pid: Int32?) -> SessionState {
        SessionState(sessionId: "s", state: .idle, cwd: "/p/x", agentPid: pid, ts: 1)
    }

    /// pid 가 없는 옛 파일은 판단하지 않는다. 합성이 시효 규칙으로 넘어간다.
    func testMissingPidIsUnknown() {
        XCTAssertEqual(probe.liveness(of: session(pid: nil)), .unknown)
        XCTAssertEqual(probe.liveness(of: session(pid: 0)), .unknown, "훅은 못 찾았을 때 0 을 쓴다")
    }

    /// 지금 도는 테스트 프로세스는 분명히 살아 있지만 claude/codex 가 아니다.
    /// pid 를 돌려 쓴 엉뚱한 프로그램을 세션으로 착각하면 안 된다.
    func testLivePidThatIsNotAnAgentIsGone() {
        XCTAssertEqual(probe.liveness(of: session(pid: getpid())), .gone)
    }

    /// 쓰이지 않는 아주 큰 pid. 있을 리 없다.
    func testUnusedPidIsGone() {
        XCTAssertEqual(probe.liveness(of: session(pid: 99_998)), .gone)
    }

    func testExistsAgreesWithReality() {
        XCTAssertTrue(ProcessProbe.exists(getpid()))
        XCTAssertTrue(ProcessProbe.exists(1), "launchd 는 남의 것이라 EPERM 이지만 살아 있다")
        XCTAssertFalse(ProcessProbe.exists(99_998))
    }

    /// CLI 로 깐 Claude Code 는 심볼릭 링크를 따라가면 파일 이름이 버전 번호다.
    /// 마지막 조각만 보면 그 세션을 통째로 놓친다. 실제로 겪은 결함이라 표로 굳혀 둔다.
    func testPathShapesThatMustCountAsAgent() {
        let yes = [
            "/Users/x/.local/share/claude/versions/2.1.274",
            "/Users/x/Library/Application Support/Claude/claude-code/2.1.271/claude.app/Contents/MacOS/claude",
            "/opt/homebrew/bin/codex",
            "/Users/x/.devin/extensions/openai.chatgpt-26/bin/macos-aarch64/codex",
        ]
        for path in yes {
            XCTAssertTrue(ProcessProbe.pathLooksLikeAgent(path), "에이전트로 봐야 한다: \(path)")
        }
    }

    /// 이름이 비슷한 남의 프로그램까지 세션으로 보면 안 된다.
    func testPathShapesThatMustNotCountAsAgent() {
        let no = [
            "/opt/homebrew/Cellar/claude-pet/0.2.0/ClaudePet.app/Contents/MacOS/ClaudePetApp",
            "/usr/bin/ssh",
            "/Users/x/Documents/workspace/claude-pet/.build/debug/ClaudePetApp",
        ]
        for path in no {
            XCTAssertFalse(ProcessProbe.pathLooksLikeAgent(path), "에이전트가 아니어야 한다: \(path)")
        }
    }

    func testProcessNameOfSelf() {
        XCTAssertNotNil(ProcessProbe.processName(getpid()))
        XCTAssertNil(ProcessProbe.processName(99_998))
    }

    func testExecutablePathOfSelf() {
        let path = ProcessProbe.executablePath(getpid())
        XCTAssertNotNil(path)
        XCTAssertTrue(path?.hasPrefix("/") == true, "절대 경로여야 한다: \(path ?? "nil")")
    }

    /// 진짜 claude 프로세스가 돌고 있으면 살아 있다고 답해야 한다.
    /// 이 기계에 세션이 없으면 확인할 게 없으므로 건너뛴다.
    func testRealAgentProcessIsAlive() throws {
        let registry = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: registry.path)) ?? []
        let pids: [Int32] = names.compactMap { name in
            guard name.hasSuffix(".json"), let pid = Int32(name.dropLast(5)) else { return nil }
            return ProcessProbe.exists(pid) ? pid : nil
        }
        try XCTSkipIf(pids.isEmpty, "돌고 있는 Claude Code 세션이 없다")
        let alive = pids.filter { probe.liveness(of: session(pid: $0)) == .alive }
        XCTAssertFalse(alive.isEmpty, "살아 있는 세션 프로세스를 하나도 알아보지 못했다: \(pids)")
    }
}
