import AppKit

/// 프레임 한 장을 픽셀 보간 없이 그린다. 클릭/드래그는 콜백으로 넘긴다.
final class PetLayerView: NSView {
    var onClick: (() -> Void)?
    var onRightClick: ((NSEvent) -> Void)?
    var onDragEnd: (() -> Void)?

    private var dragStart: NSPoint?
    private var windowStart: NSPoint?
    private var moved = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .nearest
        layer?.minificationFilter = .nearest
    }
    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: CGImage) { layer?.contents = image }

    /// 패널이 nonactivating 이고 키 윈도우가 될 수 없어서 모든 클릭이 first mouse 다.
    /// 이걸 받지 않으면 클릭과 드래그가 통째로 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        windowStart = window?.frame.origin
        moved = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart, let origin = windowStart, let window else { return }
        let now = NSEvent.mouseLocation
        let dx = now.x - start.x, dy = now.y - start.y
        if abs(dx) > 4 || abs(dy) > 4 { moved = true }
        if moved { window.setFrameOrigin(NSPoint(x: origin.x + dx, y: origin.y + dy)) }
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil; windowStart = nil }
        if moved { onDragEnd?() } else { onClick?() }
    }

    override func rightMouseDown(with event: NSEvent) { onRightClick?(event) }
}
