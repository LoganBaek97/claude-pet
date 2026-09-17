import XCTest
@testable import ClaudePetCore

final class SessionOpenPlanTests: XCTestCase {
    let host = "local_f1d6cbbb-68f8-4543-ae2f-d99f0f2c198e"

    func agg(_ state: PetState = .running, hostSession: String? = nil,
             pid: Int32? = nil, app: String? = nil, hasSession: Bool = true) -> Aggregate {
        let s = hasSession ? SessionState(sessionId: "s", state: state, hostSessionId: hostSession,
                                          hostPid: pid, hostApp: app, ts: 1) : nil
        return Aggregate(state: state, session: s, waitingCount: 0, liveSessionCount: 1)
    }

    func testClaudeDesktopSessionGetsDeepLink() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(hostSession: host)),
                       .deepLink(URL(string: "claude://code/continue?session=\(host)&source=desktop_action")!))
    }

    /// 데스크톱이 아닌 호스트는 딥링크가 아니라 그 앱을 띄운다. 이게 이번 작업의 본론.
    func testTerminalSessionActivatesItsApp() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(pid: 4242, app: "/Applications/Ghostty.app")),
                       .activate(pid: 4242, bundlePath: "/Applications/Ghostty.app"))
    }

    /// 훅은 pid 를 모를 때 0 을 쓴다. 번들만 있으면 그걸로 연다.
    func testZeroPidIsTreatedAsUnknown() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(pid: 0, app: "/Applications/iTerm.app")),
                       .activate(pid: nil, bundlePath: "/Applications/iTerm.app"))
    }

    func testDesktopSessionWinsOverHostApp() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(hostSession: host, pid: 7, app: "/Applications/Claude.app")),
                       .deepLink(URL(string: "claude://code/continue?session=\(host)&source=desktop_action")!))
    }

    func testNoHostInfoFallsBackToClaudeDesktop() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg()), .claudeDesktop)
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(app: "")), .claudeDesktop)
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(hasSession: false)), .claudeDesktop)
    }

    /// 형식이 깨진 호스트 세션 ID 로 딥링크를 쏘면 앱이 거절한다. 호스트 앱 경로가 있으면 그쪽으로.
    func testMalformedHostSessionPrefersHostApp() {
        XCTAssertEqual(SessionOpenPlanner.plan(for: agg(hostSession: "garbage", pid: 9, app: "/Applications/Antigravity.app")),
                       .activate(pid: 9, bundlePath: "/Applications/Antigravity.app"))
    }
}
