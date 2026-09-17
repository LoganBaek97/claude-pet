import Foundation

/// 펫을 눌렀을 때 무엇을 열지. AppKit 없이 정하고, 실행만 앱 레이어에서 한다.
public enum OpenPlan: Equatable {
    /// Claude Desktop 을 앞으로 가져오고 딥링크로 세션까지 이동한다.
    case deepLink(URL)
    /// 그 외 호스트(터미널, 에디터). 살아 있는 pid 면 그 인스턴스를, 아니면 번들을 연다.
    case activate(pid: Int32?, bundlePath: String)
    /// 단서가 없으면 예전처럼 Claude Desktop 을 연다.
    case claudeDesktop
}

public enum SessionOpenPlanner {
    public static func plan(for agg: Aggregate) -> OpenPlan {
        guard let session = agg.session else { return .claudeDesktop }

        // 호스트 세션 ID 는 Claude Desktop 만 환경에 내보낸다. 있으면 그게 곧 호스트다.
        if let url = DeepLink.url(for: agg), session.hostSessionId.map(DeepLink.isHostSessionId) == true {
            return .deepLink(url)
        }

        if let app = session.hostApp, !app.isEmpty {
            let pid = session.hostPid.flatMap { $0 > 0 ? $0 : nil }
            return .activate(pid: pid, bundlePath: app)
        }

        return .claudeDesktop
    }
}
