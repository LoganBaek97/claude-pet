import Foundation

/// 말풍선이 얼마나, 어떤 성격으로 눈에 띄어야 하는지.
/// question 은 답을 기다리는 상태, failure 는 무언가 잘못된 상태다.
public enum BubbleEmphasis: Equatable, Sendable {
    case none, question, failure

    /// none 이 아니면 흐려지지 않고 색 테두리를 갖는다.
    public var isEmphasized: Bool { self != .none }
}

public enum BubbleText {
    public static func text(for agg: Aggregate) -> String? {
        guard let s = agg.session else { return nil }
        let project = s.projectName
        func join(_ a: String, _ b: String) -> String {
            [a, b].filter { !$0.isEmpty }.joined(separator: " · ")
        }
        let body: String
        switch agg.state {
        case .idle:
            return nil
        case .running:
            body = s.tool.isEmpty ? join("작업 중", project) : join(s.tool, project)
        case .waiting:
            let base = join("입력 대기", project)
            body = agg.waitingCount > 1 ? "\(base) +\(agg.waitingCount - 1)" : base
        case .failed:
            body = join("실패", s.tool.isEmpty ? project : s.tool)
        case .review:
            body = join("끝남", project)
        }
        // Claude 가 기본이라 표식이 없고, 다른 에이전트만 이름을 앞에 단다.
        return s.agent == .claude ? body : join(s.agent.displayName, body)
    }

    /// 말풍선 강조 단계. 사용자가 개입해야 하는 두 상태를 서로 다른 색으로 구분한다.
    public static func emphasis(for state: PetState) -> BubbleEmphasis {
        switch state {
        case .waiting: return .question
        case .failed: return .failure
        default: return .none
        }
    }
}
