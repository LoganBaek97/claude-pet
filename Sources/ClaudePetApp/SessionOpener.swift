import AppKit
import ClaudePetCore

enum SessionOpener {
    /// Claude Desktop 을 앞으로 가져온 뒤 딥링크를 연다. 앱이 없으면 false.
    @discardableResult
    static func open(_ agg: Aggregate) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: DeepLink.claudeBundleId) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            if let url = DeepLink.url(for: agg) {
                DispatchQueue.main.async { NSWorkspace.shared.open(url) }
            }
        }
        return true
    }
}
