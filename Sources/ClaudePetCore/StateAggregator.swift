import Foundation

public struct Aggregate: Equatable, Sendable {
    public let state: PetState
    public let session: SessionState?
    public let waitingCount: Int
    public let liveSessionCount: Int

    public init(state: PetState, session: SessionState?, waitingCount: Int, liveSessionCount: Int) {
        self.state = state; self.session = session
        self.waitingCount = waitingCount; self.liveSessionCount = liveSessionCount
    }

    public static let empty = Aggregate(state: .idle, session: nil, waitingCount: 0, liveSessionCount: 0)
}

public enum StateAggregator {
    public static let deadAfter: TimeInterval = 30 * 60
    public static let settleAfter: TimeInterval = 10 * 60
    public static let deleteAfter: TimeInterval = 24 * 3600
    /// SubagentStop 이후 후속 이벤트 없이 눌러앉은 running 을 죽은 세션 시효(30분)까지 기다리지 않고 가라앉힌다.
    public static let runningStaleAfter: TimeInterval = 5 * 60

    /// 죽은 세션을 거르고, failed/review/running 을 가라앉힌 뒤, 우선순위와 최신순으로 하나를 고른다.
    public static func aggregate(_ sessions: [SessionState], now: Date) -> Aggregate {
        let live = sessions.filter { now.timeIntervalSince($0.timestamp) <= deadAfter }
        guard !live.isEmpty else { return .empty }

        func effective(_ s: SessionState) -> PetState {
            switch s.state {
            case .failed, .review:
                return now.timeIntervalSince(s.timestamp) > settleAfter ? .idle : s.state
            case .running:
                return now.timeIntervalSince(s.timestamp) > runningStaleAfter ? .idle : s.state
            default:
                return s.state
            }
        }

        let ranked = live.map { (session: $0, state: effective($0)) }
            .sorted { a, b in
                if a.state.priority != b.state.priority { return a.state.priority > b.state.priority }
                return a.session.ts > b.session.ts
            }
        let top = ranked[0]
        let waiting = ranked.filter { $0.state == .waiting }.count
        return Aggregate(state: top.state, session: top.session, waitingCount: waiting, liveSessionCount: live.count)
    }
}
