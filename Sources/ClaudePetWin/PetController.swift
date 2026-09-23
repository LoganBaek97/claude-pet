#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

// 타이머 ID. OverlayWindow 의 HWND 에 건다.
let FRAME_TIMER_ID: UINT_PTR = 1
let TICK_TIMER_ID: UINT_PTR = 2
let HOVER_TIMER_ID: UINT_PTR = 3
let DRAG_IDLE_TIMER_ID: UINT_PTR = 4

/// 시트·디렉터·타이머를 묶어 프레임을 밀어 넣고, 말풍선과 클릭을 다룬다.
final class PetController {
    private(set) var sheet: SpriteSheet?
    private var director = AnimationDirector(frameCounts: [:])
    private var dragTracker = DragTracker()
    private(set) var aggregate: Aggregate = .empty
    private(set) var pet: InstalledPet?
    let bubbles = BubbleRenderer()

    /// 현재 프레임의 SpriteFrame. 렌더에 쓴다.
    private(set) var currentFrame: SpriteFrame?

    var onLayoutChange: (() -> Void)?
    var onOpenFailed: (() -> Void)?
    /// 다시 그려 달라는 요청.
    var onRender: (() -> Void)?

    /// 오버레이 창 핸들. 타이머를 거는 데 쓴다.
    var overlayHwnd: UnsafeMutableRawPointer? // HWND. 창이 컨트롤러보다 오래 산다

    var isBubbleHidden = false {
        didSet {
            guard isBubbleHidden != oldValue else { return }
            bubbles.isBubbleHidden = isBubbleHidden
            onLayoutChange?()
        }
    }

    var ignoresReducedMotion = false {
        didSet {
            guard ignoresReducedMotion != oldValue else { return }
            applyReducedMotion()
            updateFrame()
            scheduleNext()
        }
    }

    /// 시스템 SPI_GETCLIENTAREAANIMATION 값.
    var systemReducedMotion = false {
        didSet {
            guard systemReducedMotion != oldValue else { return }
            applyReducedMotion()
            updateFrame()
            scheduleNext()
        }
    }

    private func applyReducedMotion() {
        director.reducedMotion = systemReducedMotion && !ignoresReducedMotion
    }

    func loadPet(_ pet: InstalledPet) throws {
        let sheet = try SpriteSheet(contentsOf: pet.spritesheetURL, spriteVersion: pet.manifest.spriteVersion)
        self.sheet = sheet
        self.pet = pet
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = sheet.frameCount(for: row) }
        director = AnimationDirector(frameCounts: counts)
        applyReducedMotion()
        director.setState(aggregate.state)
        director.playOnce(.waving)
        updateFrame()
        scheduleNext()
    }

    func apply(_ agg: Aggregate) {
        let stateChanged = agg.state != aggregate.state
        aggregate = agg
        director.setState(agg.state)
        bubbles.forgetGone(liveIds: Set(agg.sessions.map(\.session.sessionId)))
        bubbles.forgetTranscripts(liveTranscripts: Set(agg.sessions.compactMap(\.session.transcript)))
        if stateChanged {
            updateFrame()
            scheduleNext()
        }
        onLayoutChange?()
        onRender?()
    }

    func setHovered(_ hovered: Bool) {
        bubbles.setExpanded(hovered)
    }

    func handleClick() {
        if !SessionOpener.open(aggregate) { onOpenFailed?() }
    }

    func handleCardClick(_ summary: SessionSummary) {
        let one = Aggregate.single(summary)
        if !SessionOpener.open(one) { onOpenFailed?() }
    }

    func closeCard(_ summary: SessionSummary) {
        bubbles.close(summary)
        onLayoutChange?()
        onRender?()
    }

    // MARK: - 타이머

    func start() {
        scheduleNext()
    }

    func stop() {
        guard let hwnd = overlayHwnd.flatMap({ HWND(OpaquePointer($0)) }) else { return }
        KillTimer(hwnd, FRAME_TIMER_ID)
        KillTimer(hwnd, DRAG_IDLE_TIMER_ID)
        dragTracker.reset()
        director.hold(nil)
    }

    func scheduleNext() {
        guard let hwnd = overlayHwnd.flatMap({ HWND(OpaquePointer($0)) }) else { return }
        KillTimer(hwnd, FRAME_TIMER_ID)
        guard !director.reducedMotion else { return }
        SetTimer(hwnd, FRAME_TIMER_ID, UINT(director.currentDurationMs), nil)
    }

    /// WM_TIMER(FRAME_TIMER_ID) 가 부르는 곳.
    func advanceFrame() {
        _ = director.advance()
        updateFrame()
        scheduleNext()
        onRender?()
    }

    private func updateFrame() {
        guard let sheet else { return }
        let af = director.current
        let frames = sheet.frames(for: af.row)
        guard !frames.isEmpty else { return }
        currentFrame = frames[min(af.index, frames.count - 1)]
    }

    // MARK: - 드래그

    func dragMoved(dx: Double, dy: Double) {
        if let row = dragTracker.accumulate(dx: dx, dy: dy), director.hold(row) {
            updateFrame()
            scheduleNext()
            onRender?()
        }
        // 드래그 멈춤 감지 타이머
        guard let hwnd = overlayHwnd.flatMap({ HWND(OpaquePointer($0)) }) else { return }
        KillTimer(hwnd, DRAG_IDLE_TIMER_ID)
        SetTimer(hwnd, DRAG_IDLE_TIMER_ID, 200, nil)
    }

    /// WM_TIMER(DRAG_IDLE_TIMER_ID) 가 부르는 곳.
    func dragIdle() {
        guard let hwnd = overlayHwnd.flatMap({ HWND(OpaquePointer($0)) }) else { return }
        KillTimer(hwnd, DRAG_IDLE_TIMER_ID)
        dragTracker.reset()
        if director.hold(nil) {
            updateFrame()
            scheduleNext()
            onRender?()
        }
    }

    func dragEnded() {
        guard let hwnd = overlayHwnd.flatMap({ HWND(OpaquePointer($0)) }) else { return }
        KillTimer(hwnd, DRAG_IDLE_TIMER_ID)
        dragTracker.reset()
        director.hold(nil)
        director.playOnce(.jumping)
        updateFrame()
        scheduleNext()
        onRender?()
    }
}
#endif
