import Foundation

public struct SessionState: Codable, Equatable, Sendable {
    public let sessionId: String
    public let state: PetState
    public let event: String
    public let tool: String
    public let cwd: String
    public let ts: TimeInterval

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id", state, event, tool, cwd, ts
    }

    public init(sessionId: String, state: PetState, event: String = "", tool: String = "", cwd: String = "", ts: TimeInterval) {
        self.sessionId = sessionId; self.state = state; self.event = event
        self.tool = tool; self.cwd = cwd; self.ts = ts
    }

    public var timestamp: Date { Date(timeIntervalSince1970: ts) }

    /// cwd 의 마지막 경로 요소. 비어 있으면 빈 문자열.
    public var projectName: String {
        cwd.isEmpty ? "" : (cwd as NSString).lastPathComponent
    }
}
