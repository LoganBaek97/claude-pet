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
