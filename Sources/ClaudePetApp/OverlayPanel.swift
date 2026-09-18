import AppKit
import ClaudePetCore

final class OverlayPanel: NSPanel {
    static let margin: CGFloat = 16

    init(contentSize: NSSize) {
        super.init(contentRect: NSRect(origin: .zero, size: contentSize),
                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        isReleasedWhenClosed = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// 저장된 원점 + 현재 크기의 프레임이 어떤 화면의 visibleFrame 과도 겹치지 않으면 기본 위치(주 화면 우하단)로 되돌린다.
    /// 겹치면 그 화면 안으로 클램프해서 배치한다(F-10).
    func place(using prefs: Preferences) {
        guard let p = prefs.position else { return placeDefault() }
        let candidate = NSRect(origin: p, size: frame.size)
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.intersects(candidate) }) else {
            return placeDefault()
        }
        let visible = screen.visibleFrame
        let x = min(max(p.x, visible.minX), visible.maxX - frame.width)
        let y = min(max(p.y, visible.minY), visible.maxY - frame.height)
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    func placeDefault() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.maxX - frame.width - Self.margin, y: f.minY + Self.margin))
    }

    /// 패널은 펫 + 말풍선 스택이 다 들어가는 크기로 한 번만 잡는다. 말풍선이 늘고 줄 때마다 창을 키우면
    /// 창 크기 애니메이션이 끊겨 보이므로, 크기는 고정하고 안에서 움직인다.
    /// 기준점은 펫이 선 우하단 모서리다.
    func resize(to size: NSSize, prefs: Preferences) {
        let bottomRight = NSPoint(x: frame.maxX, y: frame.minY)
        setFrame(NSRect(x: bottomRight.x - size.width, y: bottomRight.y, width: size.width, height: size.height), display: true)
        prefs.position = frame.origin
    }
}
