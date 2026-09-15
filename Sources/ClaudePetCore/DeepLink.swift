import Foundation

public enum DeepLink {
    public static let claudeBundleId = "com.anthropic.claudefordesktop"

    public static func url(for agg: Aggregate) -> URL? {
        guard let id = agg.session?.sessionId,
              let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        let path = agg.state == .waiting ? "needs-input" : "continue"
        return URL(string: "claude://code/\(path)?session=\(encoded)")
    }
}
