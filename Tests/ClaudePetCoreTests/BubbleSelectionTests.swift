import Foundation
import Testing
@testable import ClaudePetCore

struct BubbleSelectionTests {
    private func session(_ id: String, state: PetState, ts: TimeInterval = 1000) -> SessionSummary {
        SessionSummary(
            session: SessionState(sessionId: id, state: state, cwd: "/tmp/\(id)", ts: ts),
            state: state
        )
    }

    @Test func bubbleHiddenReturnsEmpty() {
        let result = BubbleSelection.choose(
            sessions: [session("a", state: .running)],
            isExpanded: false,
            isBubbleHidden: true,
            maxCards: 8,
            closed: [:]
        )
        #expect(result.shown.isEmpty)
        #expect(result.hiddenCount == 0)
    }

    @Test func collapsedHidesIdle() {
        let sessions = [
            session("a", state: .running, ts: 3),
            session("b", state: .idle, ts: 2),
            session("c", state: .idle, ts: 1),
        ]
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: false, isBubbleHidden: false, maxCards: 8, closed: [:]
        )
        #expect(result.shown.count == 1)
        #expect(result.shown[0].session.sessionId == "a")
        #expect(result.hiddenCount == 2)
    }

    @Test func expandedShowsIdle() {
        let sessions = [
            session("a", state: .running, ts: 3),
            session("b", state: .idle, ts: 2),
        ]
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: true, isBubbleHidden: false, maxCards: 8, closed: [:]
        )
        #expect(result.shown.count == 2)
        #expect(result.hiddenCount == 0)
    }

    @Test func collapsedLimitIsThree() {
        let sessions = (0..<5).map { session("s\($0)", state: .running, ts: Double(5 - $0)) }
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: false, isBubbleHidden: false, maxCards: 8, closed: [:]
        )
        #expect(result.shown.count == BubbleSelection.collapsedLimit)
        #expect(result.hiddenCount == 2)
    }

    @Test func expandedLimitIsEight() {
        let sessions = (0..<12).map { session("s\($0)", state: .running, ts: Double(12 - $0)) }
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: true, isBubbleHidden: false, maxCards: 12, closed: [:]
        )
        #expect(result.shown.count == BubbleSelection.expandedLimit)
        #expect(result.hiddenCount == 4)
    }

    @Test func maxCardsCapsFurther() {
        let sessions = (0..<5).map { session("s\($0)", state: .running, ts: Double(5 - $0)) }
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: true, isBubbleHidden: false, maxCards: 2, closed: [:]
        )
        #expect(result.shown.count == 2)
        #expect(result.hiddenCount == 3)
    }

    @Test func closedSessionIsHiddenWhileSameState() {
        let sessions = [
            session("a", state: .waiting, ts: 2),
            session("b", state: .running, ts: 1),
        ]
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: false, isBubbleHidden: false, maxCards: 8,
            closed: ["a": .waiting]
        )
        #expect(result.shown.count == 1)
        #expect(result.shown[0].session.sessionId == "b")
    }

    @Test func closedSessionReappearsOnStateChange() {
        let sessions = [
            session("a", state: .running, ts: 2),
        ]
        // 닫았을 때의 상태는 waiting 이었지만 지금은 running 이므로 다시 보인다.
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: false, isBubbleHidden: false, maxCards: 8,
            closed: ["a": .waiting]
        )
        #expect(result.shown.count == 1)
    }

    @Test func maxCardsAtLeastOne() {
        let sessions = [session("a", state: .running)]
        let result = BubbleSelection.choose(
            sessions: sessions, isExpanded: false, isBubbleHidden: false, maxCards: 0, closed: [:]
        )
        #expect(result.shown.count == 1)
    }
}
