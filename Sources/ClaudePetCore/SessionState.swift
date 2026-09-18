import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public let sessionId: String
    public let state: PetState
    public let event: String
    public let tool: String
    public let cwd: String
    /// 세션 트랜스크립트(JSONL) 경로. 앱이 마지막 답변을 읽어 미리보기로 쓴다.
    /// 예전 버전 훅이 쓴 파일에는 없으므로 옵셔널이어야 한다.
    public let transcript: String?
    /// Claude Desktop 이 호스팅하는 세션의 앱 쪽 ID(`local_...`). 다른 호스트면 nil.
    /// 예전 버전 훅이 쓴 파일에는 없으므로 옵셔널이어야 한다.
    public let hostSessionId: String?
    /// 세션을 띄운 GUI 앱의 pid 와 번들 경로. 조상 프로세스에서 찾는다.
    /// Claude Desktop 세션이면 `hostSessionId` 로 충분해서 훅이 채우지 않는다.
    public let hostPid: Int32?
    public let hostApp: String?
    /// 상태를 보낸 에이전트의 id(`claude`, `codex`). 예전 훅이 쓴 파일에는 없고, 모르는 값이 와도
    /// 파일을 버리지 않기 위해 문자열로 받는다. 해석은 `agent` 가 한다.
    public let agentId: String?
    public let ts: TimeInterval

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", state, event, tool, cwd, transcript
        case hostSessionId = "host_session"
        case hostPid = "host_pid"
        case hostApp = "host_app"
        case agentId = "agent"
        case ts
    }

    public init(sessionId: String, state: PetState, event: String = "", tool: String = "", cwd: String = "",
                transcript: String? = nil, hostSessionId: String? = nil, hostPid: Int32? = nil, hostApp: String? = nil,
                agent: Agent = .claude, ts: TimeInterval) {
        self.sessionId = sessionId; self.state = state; self.event = event
        self.tool = tool; self.cwd = cwd; self.transcript = transcript; self.hostSessionId = hostSessionId
        self.hostPid = hostPid; self.hostApp = hostApp; self.agentId = agent.rawValue; self.ts = ts
    }

    /// agent 필드가 없거나 모르는 값이면 Claude 다.
    public var agent: Agent { agentId.flatMap(Agent.init(rawValue:)) ?? .claude }

    public var timestamp: Date { Date(timeIntervalSince1970: ts) }

    /// cwd 의 마지막 경로 요소. 비어 있으면 빈 문자열.
    public var projectName: String {
        cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent
    }
}
