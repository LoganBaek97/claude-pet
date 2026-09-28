import Foundation

// MARK: - Input

public struct HookInput: Decodable {
    public let sessionId: String?
    public let hookEventName: String?
    public let toolName: String?
    public let cwd: String?
    public let transcriptPath: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case toolName = "tool_name"
        case cwd
        case transcriptPath = "transcript_path"
    }
}

// MARK: - Action

public enum HookAction: Equatable {
    case write(SessionState)
    case remove(sessionId: String)
    case ignore
}

// MARK: - HostAppRule

public struct HostAppRule: @unchecked Sendable {
    /// 실행 파일 경로가 GUI 호스트 앱인지 판단한다.
    public let matches: (String) -> Bool
    /// 실행 파일 경로에서 앱 표시 경로(번들 경로 또는 exe 전체 경로)를 추출한다.
    public let extractApp: (String) -> String?

    public init(matches: @escaping (String) -> Bool, extractApp: @escaping (String) -> String?) {
        self.matches = matches
        self.extractApp = extractApp
    }

    /// macOS: .app/Contents/MacOS/ 를 포함한 경로 → 번들 경로(".app" 까지).
    public static let macOS = HostAppRule(
        matches: { $0.contains(".app/Contents/MacOS/") },
        extractApp: { path in
            guard let range = path.range(of: ".app/Contents/MacOS/") else { return nil }
            return String(path[..<range.lowerBound]) + ".app"
        }
    )

    /// Windows: 거부 목록에 없는 가장 바깥 조상 → exe 전체 경로.
    public static let windows: HostAppRule = {
        // 셸·콘솔 호스트·에이전트 자신·시스템 프로세스는 호스트 앱이 아니다. 소문자로 비교한다.
        let deny: Set<String> = [
            "bash", "sh", "cmd", "powershell", "pwsh", "conhost", "openconsole",
            "claude", "codex", "node", "explorer", "svchost", "services", "wininit", "system",
        ]
        return HostAppRule(
            matches: { path in !deny.contains(ProcessProbe.baseName(path)) },
            extractApp: { $0 }
        )
    }()
}

// MARK: - HookRunner

public enum HookRunner {

    // MARK: Decision (pure)

    /// hook.sh 와 같은 규칙으로 입력을 해석해 취할 행동을 반환한다. 부수 효과 없음.
    public static func decide(
        input: Data,
        agent: Agent,
        environment: [String: String],
        ancestry: ProcessAncestry,
        selfPid: Int32,
        hostRule: HostAppRule,
        now: Date
    ) -> HookAction {
        // 1. stdin이 비었거나 JSON 파싱 실패 → ignore
        guard !input.isEmpty,
              let parsed = try? JSONDecoder().decode(HookInput.self, from: input) else {
            return .ignore
        }

        // 2. session_id 검증: [A-Za-z0-9._-]+ 이어야 한다
        guard let sessionId = parsed.sessionId, !sessionId.isEmpty,
              sessionId.unicodeScalars.allSatisfy({ isValidSessionChar($0) }) else {
            return .ignore
        }

        let event = parsed.hookEventName ?? ""

        // 3. 이벤트 매핑
        switch EventMapper.outcome(for: event) {
        case .ignore:
            return .ignore
        case .remove:
            return .remove(sessionId: sessionId)
        case .set(let state):
            // 4. host_session: claude 에이전트이고 환경 변수가 유효할 때만
            let hostSessionId: String? = resolveHostSession(agent: agent, environment: environment)

            // 5. 조상 체인 탐색 (selfPid 자신은 제외)
            let chain = ancestry.chain(from: selfPid, limit: 20)
            let ancestors = chain.dropFirst()

            // 6. agent_pid: 가장 가까운 에이전트 조상 (Windows .exe 도 처리하는 확장 판정 사용)
            let agentPid: Int32? = ancestors
                .first { pathLooksLikeAgent($0.executablePath) }
                .map { $0.pid }

            // 7. host_pid / host_app: host_session 이 없을 때만 탐색
            var hostPid: Int32? = nil
            var hostApp: String? = nil
            if hostSessionId == nil {
                if let hostNode = ancestors.last(where: { hostRule.matches($0.executablePath) }),
                   let extracted = hostRule.extractApp(hostNode.executablePath) {
                    hostPid = hostNode.pid
                    hostApp = extracted
                }
            }

            let ss = SessionState(
                sessionId: sessionId,
                state: state,
                event: event,
                tool: parsed.toolName ?? "",
                cwd: parsed.cwd ?? "",
                transcript: parsed.transcriptPath ?? "",
                hostSessionId: hostSessionId,
                hostPid: hostPid ?? 0,
                hostApp: hostApp ?? "",
                agentPid: agentPid ?? 0,
                agent: agent,
                ts: now.timeIntervalSince1970
            )
            return .write(ss)
        }
    }

    // MARK: Execution (side effects)

    /// 행동을 실행한다. 디렉터리가 없으면 생성한다. 실패는 조용히 무시한다. 항상 반환.
    public static func perform(_ action: HookAction, stateDirectory: URL) {
        let fm = FileManager.default
        switch action {
        case .ignore:
            return

        case .remove(let sessionId):
            let file = stateDirectory.appendingPathComponent("\(sessionId).json")
            try? fm.removeItem(at: file)

        case .write(let state):
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            guard let data = try? encoder.encode(state) else { return }
            try? fm.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            let destination = stateDirectory.appendingPathComponent("\(state.sessionId).json")
            let selfPid = ProcessInfo.processInfo.processIdentifier
            atomicWrite(data, to: destination, pid: selfPid)
        }
    }

    // MARK: - Helpers

    private static func isValidSessionChar(_ scalar: Unicode.Scalar) -> Bool {
        let v = scalar.value
        return (v >= 65 && v <= 90)   // A-Z
            || (v >= 97 && v <= 122)  // a-z
            || (v >= 48 && v <= 57)   // 0-9
            || v == 46  // .
            || v == 95  // _
            || v == 45  // -
    }

    /// ProcessProbe 와 같은 판정(`/`·`\` 구분자, `.exe` 제거). 앱이 생사를 볼 때와 훅이 pid 를 고를 때 기준이 같아야 한다.
    private static func pathLooksLikeAgent(_ path: String) -> Bool {
        ProcessProbe.pathLooksLikeAgent(path)
    }

    private static func resolveHostSession(agent: Agent, environment: [String: String]) -> String? {
        guard agent == .claude,
              let raw = environment["CLAUDE_CODE_HOST_SESSION_ID"],
              DeepLink.isHostSessionId(raw) else { return nil }
        return raw
    }

    private static func atomicWrite(_ data: Data, to destination: URL, pid: Int32) {
        let tmp = destination.deletingLastPathComponent()
            .appendingPathComponent(destination.lastPathComponent + ".tmp.\(pid)")

        for attempt in 0..<2 {
            if attempt > 0 {
                // Windows Defender 가 짧게 잡을 수 있다. 한 번 기다린 뒤 재시도.
                Thread.sleep(forTimeInterval: 0.15)
            }
            do {
                try data.write(to: tmp)
                try FileManager.default.replaceItemAtomically(destination, with: tmp)
                return
            } catch {
                try? FileManager.default.removeItem(at: tmp)
            }
        }
    }
}
