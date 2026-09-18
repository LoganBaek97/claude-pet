import AppKit

/// 50ms 마다 마우스가 펫이나 말풍선 위에 있는지 보고 `ignoresMouseEvents` 를 토글한다.
/// 접근성 권한이 필요 없다. 패널은 넉넉한 고정 크기라 이 사각형들 바깥은 클릭이 밑으로 통과해야 한다.
final class HoverTracker {
    private weak var panel: NSPanel?
    private let hitRects: () -> [NSRect]
    private let onChange: (Bool) -> Void
    private var timer: Timer?
    private var wasInside = false

    /// `hitRects` 는 화면 좌표. `onChange` 는 들어가고 나갈 때만 불린다.
    init(panel: NSPanel, hitRects: @escaping () -> [NSRect], onChange: @escaping (Bool) -> Void = { _ in }) {
        self.panel = panel
        self.hitRects = hitRects
        self.onChange = onChange
    }

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if wasInside {
            wasInside = false
            onChange(false)
        }
    }

    private func tick() {
        guard let panel, panel.isVisible else { return }
        let mouse = NSEvent.mouseLocation
        let inside = hitRects().contains { $0.contains(mouse) }
        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }
        if inside != wasInside {
            wasInside = inside
            onChange(inside)
        }
    }
}
