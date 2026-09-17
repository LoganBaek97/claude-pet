import Foundation

/// 선언 순서가 우선순위 오름차순이다. 뒤로 갈수록 급하다.
public enum PetState: String, Codable, CaseIterable, Sendable {
    case idle, review, running, failed, waiting

    public var priority: Int { PetState.allCases.firstIndex(of: self)! }
}

public enum EventOutcome: Equatable, Sendable {
    case set(PetState)
    case remove
    case ignore
}

public enum EventMapper {
    public static func outcome(for event: String) -> EventOutcome {
        switch event {
        case "SessionStart": return .set(.idle)
        case "SessionEnd": return .remove
        case "UserPromptSubmit", "PreToolUse", "PostToolUse": return .set(.running)
        case "PermissionRequest", "Notification": return .set(.waiting)
        case "PostToolUseFailure", "StopFailure": return .set(.failed)
        case "Stop": return .set(.review)
        // Codex 전용. 사용자가 직접 끊은 것이라 알릴 게 없다.
        case "Interrupt": return .set(.idle)
        default: return .ignore
        }
    }

    /// settings.json 에 훅을 거는 이벤트 목록. 순서는 설치 결과의 가독성용.
    /// SubagentStart/SubagentStop 은 여기 없다: 부모 세션의 PreToolUse/PostToolUse/Stop 이 이미 상태를 반영하므로
    /// 걸지 않는다(걸면 서브에이전트 종료가 running 을 다시 만들어 review 뒤에도 눌러앉는다).
    public static let hookedEvents: [String] = [
        "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
        "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
    ]
}
