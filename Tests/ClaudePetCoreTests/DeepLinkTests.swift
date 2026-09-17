import XCTest
@testable import ClaudePetCore

final class DeepLinkTests: XCTestCase {
    func agg(_ state: PetState, id: String? = "abc-123", host: String? = nil) -> Aggregate {
        Aggregate(state: state,
                  session: id.map { SessionState(sessionId: $0, state: state, hostSessionId: host, ts: 1) },
                  waitingCount: 0, liveSessionCount: 1)
    }

    let host = "local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e"

    func testWaitingUsesNeedsInputWithHostSession() {
        XCTAssertEqual(DeepLink.url(for: agg(.waiting, host: host))?.absoluteString,
                       "claude://code/needs-input?session=\(host)&source=desktop_action")
    }

    func testOtherStatesUseContinueWithHostSession() {
        for s in [PetState.running, .failed, .review, .idle] {
            XCTAssertEqual(DeepLink.url(for: agg(s, host: host))?.absoluteString,
                           "claude://code/continue?session=\(host)&source=desktop_action", "\(s)")
        }
    }

    /// 훅 페이로드의 세션 ID(UUID)는 앱이 거절한다. 링크에 넣지 않는다.
    func testCodeSessionIdNeverBecomesSessionParam() {
        let url = DeepLink.url(for: agg(.running, id: "3ae0102f-1afd-414c-8941-76c6c184f9f6"))
        XCTAssertEqual(url?.absoluteString, "claude://code/continue?session=last&source=desktop_action")
    }

    func testWaitingWithoutHostSessionOmitsSession() {
        XCTAssertEqual(DeepLink.url(for: agg(.waiting))?.absoluteString,
                       "claude://code/needs-input?source=desktop_action")
    }

    func testMalformedHostSessionFallsBack() {
        for bad in ["", "local_", "session_abc", "local_no_underscores_allowed",
                    "local_" + String(repeating: "a", count: 65)] {
            XCTAssertFalse(DeepLink.isHostSessionId(bad), bad)
            XCTAssertEqual(DeepLink.url(for: agg(.running, host: bad))?.absoluteString,
                           "claude://code/continue?session=last&source=desktop_action", bad)
        }
    }

    func testAcceptsHostSessionIdAtBounds() {
        XCTAssertTrue(DeepLink.isHostSessionId("local_a"))
        XCTAssertTrue(DeepLink.isHostSessionId("local_" + String(repeating: "a", count: 64)))
    }

    func testNoSessionNoURL() {
        XCTAssertNil(DeepLink.url(for: agg(.idle, id: nil)))
    }
}
