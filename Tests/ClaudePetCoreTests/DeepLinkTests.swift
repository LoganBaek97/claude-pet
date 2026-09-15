import XCTest
@testable import ClaudePetCore

final class DeepLinkTests: XCTestCase {
    func agg(_ state: PetState, id: String? = "abc-123") -> Aggregate {
        Aggregate(state: state, session: id.map { SessionState(sessionId: $0, state: state, ts: 1) }, waitingCount: 0, liveSessionCount: 1)
    }

    func testWaitingUsesNeedsInput() {
        XCTAssertEqual(DeepLink.url(for: agg(.waiting))?.absoluteString, "claude://code/needs-input?session=abc-123")
    }

    func testOtherStatesUseContinue() {
        for s in [PetState.running, .failed, .review, .idle] {
            XCTAssertEqual(DeepLink.url(for: agg(s))?.absoluteString, "claude://code/continue?session=abc-123", "\(s)")
        }
    }

    func testNoSessionNoURL() {
        XCTAssertNil(DeepLink.url(for: agg(.idle, id: nil)))
    }
}
