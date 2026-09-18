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
