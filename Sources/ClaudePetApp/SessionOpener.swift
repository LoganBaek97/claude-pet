#if os(macOS)
import AppKit
import ClaudePetCore

enum SessionOpener {
    /// 세션이 돌고 있는 앱을 앞으로 가져온다. Claude Desktop 이면 세션까지 이동한다.
    /// 아무것도 열지 못하면 false.
    @discardableResult
    static func open(_ agg: Aggregate) -> Bool {
        switch SessionOpenPlanner.plan(for: agg) {
        case .deepLink(let url):
            return openClaudeDesktop(then: url)
        case .activate(let pid, let bundlePath):
            if activate(pid: pid, bundlePath: bundlePath) { return true }
            // 호스트 앱이 사라졌을 때의 폴백. Claude 세션만 Claude Desktop 으로 보낸다.
            return agg.session?.agent == .claude && openClaudeDesktop(then: nil)
        case .claudeDesktop:
            return openClaudeDesktop(then: nil)
        case .stay:
            return false
        }
    }

    /// pid 가 아직 그 번들의 프로세스면 그 인스턴스를 띄운다. pid 는 재사용되므로
    /// 번들 경로까지 맞는지 확인한다. 이미 끝난 세션이면 번들을 새로 연다.
    private static func activate(pid: Int32?, bundlePath: String) -> Bool {
        if let pid,
           let running = NSRunningApplication(processIdentifier: pid),
           running.bundleURL?.standardizedFileURL.path == URL(fileURLWithPath: bundlePath).standardizedFileURL.path,
           running.activate(options: [.activateAllWindows]) {
            return true
        }
        let url = URL(fileURLWithPath: bundlePath)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return true
    }

    private static func openClaudeDesktop(then url: URL?) -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: DeepLink.claudeBundleId) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, _ in
            guard let url else { return }
            DispatchQueue.main.async { NSWorkspace.shared.open(url) }
        }
        return true
    }
}
#endif
