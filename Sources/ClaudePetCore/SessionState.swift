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
    /// 이 세션을 돌리는 claude/codex 프로세스의 pid. 앱이 생사를 확인해서, 오래 조용한 세션도
    /// 프로세스가 살아 있으면 계속 보여 준다. 예전 훅이 쓴 파일에는 없으므로 옵셔널이어야 한다.
    public let agentPid: Int32?
    /// 상태를 보낸 에이전트의 id(`claude`, `codex`). 예전 훅이 쓴 파일에는 없고, 모르는 값이 와도
    /// 파일을 버리지 않기 위해 문자열로 받는다. 해석은 `agent` 가 한다.
    public let agentId: String?
    /// 이번 턴을 연 프롬프트(UserPromptSubmit)의 시각. 훅이 매 이벤트마다 파일을 새로 쓰므로 직전 파일에서
    /// 이어 받는다. 말풍선의 경과 시간은 마지막 도구가 아니라 이 시각부터 센다. 예전 훅이 쓴 파일에는 없다.
    public let promptTs: TimeInterval?
    public let ts: TimeInterval

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", state, event, tool, cwd, transcript
        case hostSessionId = "host_session"
        case hostPid = "host_pid"
        case hostApp = "host_app"
        case agentPid = "agent_pid"
        case agentId = "agent"
        case promptTs = "prompt_ts"
        case ts
    }

    public init(sessionId: String, state: PetState, event: String = "", tool: String = "", cwd: String = "",
                transcript: String? = nil, hostSessionId: String? = nil, hostPid: Int32? = nil, hostApp: String? = nil,
                agentPid: Int32? = nil, agent: Agent = .claude, promptTs: TimeInterval? = nil, ts: TimeInterval) {
        self.sessionId = sessionId; self.state = state; self.event = event
        self.tool = tool; self.cwd = cwd; self.transcript = transcript; self.hostSessionId = hostSessionId
        self.hostPid = hostPid; self.hostApp = hostApp; self.agentPid = agentPid
        self.agentId = agent.rawValue; self.promptTs = promptTs; self.ts = ts
    }

    /// agent 필드가 없거나 모르는 값이면 Claude 다.
    public var agent: Agent { agentId.flatMap(Agent.init(rawValue:)) ?? .claude }

    public var timestamp: Date { Date(timeIntervalSince1970: ts) }

    /// 이번 턴을 연 프롬프트 시각. 예전 훅이 쓴 파일이거나 훅이 0(없음)을 쓰면 nil.
    public var promptDate: Date? {
        guard let promptTs, promptTs > 0 else { return nil }
        return Date(timeIntervalSince1970: promptTs)
    }

    /// 진행 중인 턴이 시작된 시각. 프롬프트 시각을 모르면 마지막 신호 시각으로 대신한다.
    public var turnStartedAt: Date { promptDate ?? timestamp }

    /// 끝난 턴이 걸린 시간(프롬프트부터 끝난 신호까지). 시작을 모르면 nil.
    public var turnDuration: TimeInterval? {
        promptDate.map { timestamp.timeIntervalSince($0) }
    }

    /// cwd 의 마지막 경로 요소. 비어 있으면 빈 문자열.
    /// `/` 와 `\` 를 모두 구분자로 보고, 끝에 구분자가 붙어 있어도 올바르게 처리한다(`C:\proj\` → `proj`).
    public var projectName: String {
        guard !cwd.isEmpty else { return "" }
        return cwd.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? ""
    }
}
