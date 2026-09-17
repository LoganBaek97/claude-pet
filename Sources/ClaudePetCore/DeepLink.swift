import Foundation

public enum DeepLink {
    public static let claudeBundleId = "com.anthropic.claudefordesktop"

    /// Claude Desktop 의 URL 핸들러가 받는 세션 ID 형식. 앱 쪽 정규식
    /// `^local_[A-Za-z0-9-]{1,64}$` 와 같다. 어긋나면 앱은 링크를 버리고
    /// (로그: `claudeURLHandler: code entry link invalid ?session`) 창만 앞으로 나온다.
    public static func isHostSessionId(_ id: String) -> Bool {
        guard id.hasPrefix("local_") else { return false }
        let rest = id.dropFirst("local_".count)
        guard (1...64).contains(rest.count) else { return false }
        return rest.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    /// 앱이 스스로 만드는 링크와 같은 모양으로 맞춘다.
    /// 호스트 세션 ID 를 모르면(터미널 CLI 등) `continue` 는 마지막 세션으로,
    /// `needs-input` 은 세션 없이 — 핸들러가 가장 오래 기다린 세션을 고른다.
    public static func url(for agg: Aggregate) -> URL? {
        guard let session = agg.session else { return nil }
        let path = agg.state == .waiting ? "needs-input" : "continue"

        var items = [URLQueryItem]()
        if let host = session.hostSessionId, isHostSessionId(host) {
            items.append(URLQueryItem(name: "session", value: host))
        } else if path == "continue" {
            items.append(URLQueryItem(name: "session", value: "last"))
        }
        items.append(URLQueryItem(name: "source", value: "desktop_action"))

        var comps = URLComponents()
        comps.scheme = "claude"
        comps.host = "code"
        comps.path = "/\(path)"
        comps.queryItems = items
        return comps.url
    }
}
