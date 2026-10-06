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

    // MARK: 세션 카드 한 장

    /// 카드 제목. 어느 프로젝트인지가 세션을 가르는 가장 빠른 단서다.
    /// cwd 를 못 받은 세션은 빈 제목이 되지 않게 세션 id 앞자리를 쓴다.
    public static func title(for summary: SessionSummary) -> String {
        let project = summary.session.projectName
        if !project.isEmpty { return project }
        return String(summary.session.sessionId.prefix(6))
    }

    /// 카드 부제의 상태 글자. 도구 이름은 넣지 않는다(초마다 바뀌어 눈만 어지럽다).
    /// 에이전트 이름은 카드가 배지로 따로 그린다.
    public static func detail(for summary: SessionSummary) -> String {
        switch summary.state {
        case .idle: return "유휴"
        case .running: return "작업 중"
        case .waiting: return "입력 대기"
        case .failed: return "실패"
        case .review: return "끝남"
        }
    }

    /// 카드 부제 한 줄.
    /// 진행 중인 턴(작업 중·입력 대기, 도구 실패 뒤 이어지는 중)은 프롬프트를 보낸 때부터 흐르는 시간을,
    /// 끝난 턴(끝남, 턴 자체가 실패로 끝남)은 프롬프트부터 끝날 때까지 걸린 총 시간을 붙인다.
    /// 끝난 턴의 시작을 모르면 시간을 빼고, 유휴에는 붙이지 않는다.
    public static func subtitle(for summary: SessionSummary, now: Date) -> String {
        let detail = detail(for: summary)
        let session = summary.session
        let finished = summary.state == .review || (summary.state == .failed && session.event == "StopFailure")
        if finished {
            guard let total = session.turnDuration else { return detail }
            return "\(detail) · 총 \(duration(total))"
        }
        guard summary.state.isOngoing || summary.state == .failed else { return detail }
        return "\(detail) · \(elapsed(now.timeIntervalSince(session.turnStartedAt)))"
    }

    /// 끝난 턴의 총 시간. 흐르는 시간과 달리 "방금" 으로 뭉개지 않고, 한 시간이 넘으면 분까지 적는다.
    public static func duration(_ seconds: TimeInterval) -> String {
        let s = max(Int(seconds.rounded()), 1)
        if s < 60 { return "\(s)초" }
        if s < 3600 { return "\(s / 60)분" }
        let m = (s % 3600) / 60
        return m == 0 ? "\(s / 3600)시간" : "\(s / 3600)시간 \(m)분"
    }

    /// 지난 시간. 한 칸만 보여 준다(`3분` 이지 `3분 20초` 가 아니다).
    public static func elapsed(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded())
        if s < 5 { return "방금" }           // 음수(시계 어긋남)도 여기로 들어온다
        if s < 60 { return "\(s)초" }
        if s < 3600 { return "\(s / 60)분" }
        return "\(s / 3600)시간"
    }
}
