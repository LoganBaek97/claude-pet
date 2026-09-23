#if os(macOS)
import AppKit
import ClaudePetCore

/// 프레임 한 장을 픽셀 보간 없이 그린다. 클릭/드래그는 콜백으로 넘긴다.
final class PetLayerView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnd: (() -> Void)?
    /// 끌려가는 동안 방금 움직인 양을 알린다. 누적이 아니라 직전 이벤트로부터의 차이다.
    /// 되돌아올 때도 펫이 따라 돌아서야 해서 순간 방향이 필요하다.
    var onDragMove: ((Double, Double) -> Void)?

    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var lastPoint: NSPoint?
    private var moved = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ frame: SpriteFrame) { layer?.contents = frame.makeCGImage() }

    /// 패널이 nonactivating 이고 키 윈도우가 될 수 없어서 모든 클릭이 first mouse 다.
    /// 이걸 받지 않으면 클릭과 드래그가 통째로 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        lastPoint = NSEvent.mouseLocation
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if abs(dx) > 4 || abs(dy) > 4 { moved = true }
        guard moved else { return }
        window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy))
        let previous = lastPoint ?? now
        lastPoint = now
        onDragMove?(Double(now.x - previous.x), Double(now.y - previous.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; windowStart = nil; lastPoint = nil }
        if moved { onDragEnd?() } else { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}
#endif
