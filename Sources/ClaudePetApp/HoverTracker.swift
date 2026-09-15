import AppKit

/// 50ms 마다 마우스가 패널 위에 있는지 보고 ignoresMouseEvents 를 토글한다. 접근성 권한이 필요 없다.
final class HoverTracker {
    private weak var panel: NSPanel?
    private let hitRect: () -> NSRect
    private var timer: Timer?

    init(panel: NSPanel, hitRect: @escaping () -> NSRect) {
        self.panel = panel
        self.hitRect = hitRect
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() { timer?.invalidate(); timer = nil }

    private func tick() {
        guard let panel, panel.isVisible else { return }
        let inside = hitRect().contains(NSEvent.mouseLocation)
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
    }
}
