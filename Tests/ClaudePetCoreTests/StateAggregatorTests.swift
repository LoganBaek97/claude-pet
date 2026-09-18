import XCTest
@testable import ClaudePetCore

final class StateAggregatorTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)
    func s(_ id: String, _ state: PetState, ageSeconds: TimeInterval = 0, cwd: String = "/p/\(UUID().uuidString)") -> SessionState {
        SessionState(sessionId: id, state: state, event: "", tool: "", cwd: cwd, ts: now.timeIntervalSince1970 - ageSeconds)
    }

    func testEmptyIsIdleWithoutSession() {
        let a = StateAggregator.aggregate([], now: now)
        XCTAssertEqual(a.state, .idle)
        XCTAssertNil(a.session)
        XCTAssertEqual(a.waitingCount, 0)
        XCTAssertEqual(a.liveSessionCount, 0)
    }

    func testHighestPriorityWins() {
        let a = StateAggregator.aggregate([s("r", .running), s("w", .waiting), s("f", .failed)], now: now)
        XCTAssertEqual(a.state, .waiting)
        XCTAssertEqual(a.session?.sessionId, "w")
    }

    func testTieBreaksByNewest() {
        let a = StateAggregator.aggregate([s("old", .running, ageSeconds: 60), s("new", .running, ageSeconds: 5)], now: now)
        XCTAssertEqual(a.session?.sessionId, "new")
    }

    func testDeadSessionsIgnored() {
        let a = StateAggregator.aggregate([s("dead", .waiting, ageSeconds: 31 * 60), s("live", .running)], now: now)
        XCTAssertEqual(a.state, .running)
        XCTAssertEqual(a.liveSessionCount, 1)
    }

    func testFailedAndReviewSettleToIdleAfterTenMinutes() {
        let a = StateAggregator.aggregate([s("f", .failed, ageSeconds: 11 * 60), s("r", .review, ageSeconds: 11 * 60)], now: now)
        XCTAssertEqual(a.state, .idle)
        XCTAssertNotNil(a.session, "settled sessions are still live and clickable")
        let fresh = StateAggregator.aggregate([s("f", .failed, ageSeconds: 9 * 60)], now: now)
        XCTAssertEqual(fresh.state, .failed)
    }

    func testRunningSettlesToIdleAfterFiveMinutes() {
        let stale = StateAggregator.aggregate([s("r", .running, ageSeconds: 6 * 60)], now: now)
        XCTAssertEqual(stale.state, .idle)
        XCTAssertNotNil(stale.session, "settled session is still live and clickable")
        XCTAssertEqual(stale.liveSessionCount, 1)
        let fresh = StateAggregator.aggregate([s("r", .running, ageSeconds: 4 * 60)], now: now)
        XCTAssertEqual(fresh.state, .running)
    }

    func testWaitingCountCountsAllLiveWaiting() {
        let a = StateAggregator.aggregate([s("a", .waiting), s("b", .waiting, ageSeconds: 10), s("c", .waiting, ageSeconds: 40 * 60), s("d", .running)], now: now)
        XCTAssertEqual(a.waitingCount, 2)
        XCTAssertEqual(a.session?.sessionId, "a")
    }
}

// MARK: 세션 목록

extension StateAggregatorTests {
    /// 말풍선은 세션마다 하나씩 뜬다. 합성이 고른 대표 하나 말고 살아 있는 세션 전부가 필요하다.
    func testSessionsListsEveryLiveSession() {
        let a = StateAggregator.aggregate([s("r", .running), s("w", .waiting), s("i", .idle)], now: now)
        XCTAssertEqual(a.sessions.map(\.session.sessionId), ["w", "r", "i"], "우선순위 내림차순")
        XCTAssertEqual(a.sessions.map(\.state), [.waiting, .running, .idle])
    }

    func testSessionsExcludesDeadOnes() {
        let a = StateAggregator.aggregate([s("dead", .waiting, ageSeconds: 31 * 60), s("live", .running)], now: now)
        XCTAssertEqual(a.sessions.map(\.session.sessionId), ["live"])
    }

    /// 목록의 상태는 가라앉힌 뒤의 상태다. 대표 상태를 고를 때 쓰는 규칙과 같아야 한다.
    func testSessionsCarrySettledState() {
        let a = StateAggregator.aggregate([s("stale", .running, ageSeconds: 6 * 60), s("fresh", .running)], now: now)
        let byId = Dictionary(uniqueKeysWithValues: a.sessions.map { ($0.session.sessionId, $0.state) })
        XCTAssertEqual(byId["stale"], .idle)
        XCTAssertEqual(byId["fresh"], .running)
    }

    /// 같은 순위면 최신이 위로. 목록 순서가 곧 말풍선 순서다.
    func testSessionsTieBreakByNewest() {
        let a = StateAggregator.aggregate([s("old", .waiting, ageSeconds: 60), s("new", .waiting, ageSeconds: 5)], now: now)
        XCTAssertEqual(a.sessions.map(\.session.sessionId), ["new", "old"])
    }

    func testEmptyAggregateHasNoSessions() {
        XCTAssertEqual(Aggregate.empty.sessions.count, 0)
        XCTAssertEqual(StateAggregator.aggregate([], now: now).sessions.count, 0)
    }

    /// 대표 세션은 목록 맨 앞과 같은 것이어야 한다.
    func testTopSessionMatchesFirstOfList() {
        let a = StateAggregator.aggregate([s("r", .running), s("f", .failed), s("w", .waiting)], now: now)
        XCTAssertEqual(a.session?.sessionId, a.sessions.first?.session.sessionId)
        XCTAssertEqual(a.state, a.sessions.first?.state)
    }
}

// MARK: 프로세스 생사로 판단하기

final class SessionLivenessTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 2_000_000)

    func s(_ id: String, _ state: PetState, ageSeconds: TimeInterval = 0, pid: Int32? = nil) -> SessionState {
        SessionState(sessionId: id, state: state, cwd: "/p/\(id)", agentPid: pid,
                     ts: now.timeIntervalSince1970 - ageSeconds)
    }

    /// 이번 작업의 본론. 오래 조용해도 프로세스가 살아 있으면 계속 보여 준다.
    /// 예전에는 30분간 이벤트가 없으면 죽은 것으로 보고 말풍선에서 빼 버렸다.
    func testAliveProcessSurvivesLongSilence() {
        let quiet = s("quiet", .idle, ageSeconds: 5 * 3600, pid: 42)
        let a = StateAggregator.aggregate([quiet], now: now) { _ in .alive }
        XCTAssertEqual(a.sessions.map(\.session.sessionId), ["quiet"])
        XCTAssertEqual(a.liveSessionCount, 1)
    }

    /// 프로세스가 없으면 30분을 기다리지 않고 바로 뺀다. 지금까지는 유령이 남았다.
    func testGoneProcessDropsImmediately() {
        let fresh = s("dead", .running, ageSeconds: 5, pid: 42)
        let a = StateAggregator.aggregate([fresh], now: now) { _ in .gone }
        XCTAssertTrue(a.sessions.isEmpty)
        XCTAssertEqual(a.state, .idle)
    }

    /// 옛 훅이 쓴 파일에는 pid 가 없다. 그때는 지금까지 쓰던 30분 규칙 그대로.
    func testUnknownFallsBackToAgeRule() {
        let old = s("old", .running, ageSeconds: 31 * 60)
        let recent = s("recent", .running, ageSeconds: 29 * 60)
        let a = StateAggregator.aggregate([old, recent], now: now) { _ in .unknown }
        XCTAssertEqual(a.sessions.map(\.session.sessionId), ["recent"])
    }

    /// 살아 있어도 가라앉힘 규칙은 그대로다. 몇 시간 조용한 세션이 계속 "작업 중" 일 수는 없다.
    func testAliveSessionStillSettlesToIdle() {
        let a = StateAggregator.aggregate([s("q", .running, ageSeconds: 3 * 3600, pid: 42)], now: now) { _ in .alive }
        XCTAssertEqual(a.sessions.first?.state, .idle)
        XCTAssertEqual(a.state, .idle)
    }

    /// 판단은 세션마다 다르다. 살아 있는 것만 남는다.
    func testMixedLiveness() {
        let sessions = [s("alive", .idle, ageSeconds: 4 * 3600, pid: 1),
                        s("gone", .waiting, ageSeconds: 10, pid: 2),
                        s("nopid", .running, ageSeconds: 10)]
        let a = StateAggregator.aggregate(sessions, now: now) { session in
            switch session.sessionId {
            case "alive": return .alive
            case "gone": return .gone
            default: return .unknown
            }
        }
        XCTAssertEqual(Set(a.sessions.map(\.session.sessionId)), ["alive", "nopid"])
        XCTAssertEqual(a.state, .running, "살아 있지만 조용한 세션보다 방금 도는 세션이 앞선다")
    }

    /// 판단을 넘기지 않으면 지금까지와 똑같이 동작해야 한다.
    func testDefaultKeepsOldBehaviour() {
        let a = StateAggregator.aggregate([s("old", .running, ageSeconds: 31 * 60)], now: now)
        XCTAssertTrue(a.sessions.isEmpty)
    }
}
