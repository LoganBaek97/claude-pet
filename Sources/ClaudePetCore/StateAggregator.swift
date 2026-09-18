import Foundation

/// 말풍선 한 장이 나르는 세션 하나. `state` 는 가라앉힘 규칙을 적용한 뒤의 상태다(`SessionState.state` 원본이 아니다).
public struct SessionSummary: Equatable, Sendable {
    public let session: SessionState
    public let state: PetState

    public init(session: SessionState, state: PetState) {
        self.session = session
        self.state = state
    }
}

public struct Aggregate: Equatable, Sendable {
    public let state: PetState
    public let session: SessionState?
    public let waitingCount: Int
    public let liveSessionCount: Int
    /// 살아 있는 세션 전부. 급한 순서, 같으면 최신순. 맨 앞이 `state`/`session` 이 가리키는 그 세션이다.
    public let sessions: [SessionSummary]

    public init(state: PetState, session: SessionState?, waitingCount: Int, liveSessionCount: Int,
                sessions: [SessionSummary] = []) {
        self.state = state; self.session = session
        self.waitingCount = waitingCount; self.liveSessionCount = liveSessionCount
        self.sessions = sessions
    }

    public static let empty = Aggregate(state: .idle, session: nil, waitingCount: 0, liveSessionCount: 0)
}

/// 세션 프로세스가 아직 있는지. `unknown` 은 옛 훅이 쓴 파일이라 pid 를 모르는 경우다.
public enum SessionLiveness: Equatable, Sendable {
    case alive, gone, unknown
}

public enum StateAggregator {
    public static let deadAfter: TimeInterval = 30 * 60
    public static let settleAfter: TimeInterval = 10 * 60
    public static let deleteAfter: TimeInterval = 24 * 3600
    /// SubagentStop 이후 후속 이벤트 없이 눌러앉은 running 을 죽은 세션 시효(30분)까지 기다리지 않고 가라앉힌다.
    public static let runningStaleAfter: TimeInterval = 5 * 60

    /// 죽은 세션을 거르고, failed/review/running 을 가라앉힌 뒤, 우선순위와 최신순으로 줄 세운다.
    /// 맨 앞이 펫이 따르는 상태이고, 줄 전체가 말풍선 순서다.
    ///
    /// `liveness` 는 세션 프로세스가 아직 있는지 알려 준다. 살아 있으면 아무리 조용해도 남기고,
    /// 없으면 바로 뺀다. 모르면(옛 훅이 쓴 파일) `deadAfter` 시효로 판단한다.
    /// 훅 이벤트만 보면 몇 시간 조용한 세션이 사라져 버린다. 프로세스를 보는 쪽이 사실에 가깝다.
    public static func aggregate(_ sessions: [SessionState], now: Date,
                                 liveness: (SessionState) -> SessionLiveness = { _ in .unknown }) -> Aggregate {
        let live = sessions.filter { session in
            switch liveness(session) {
            case .alive: return true
            case .gone: return false
            case .unknown: return now.timeIntervalSince(session.timestamp) <= deadAfter
            }
        }
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

        let ranked = live.map { SessionSummary(session: $0, state: effective($0)) }
            .sorted { a, b in
                if a.state.priority != b.state.priority { return a.state.priority > b.state.priority }
                return a.session.ts > b.session.ts
            }
        let top = ranked[0]
        let waiting = ranked.filter { $0.state == .waiting }.count
        return Aggregate(state: top.state, session: top.session, waitingCount: waiting,
                         liveSessionCount: live.count, sessions: ranked)
    }
}
