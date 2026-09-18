import AppKit
import ClaudePetCore

/// 시트·디렉터·타이머를 묶어 뷰에 프레임을 밀어 넣고, 말풍선 스택과 클릭을 다룬다.
final class PetController {
    let view = PetLayerView(frame: .zero)
    let stack = BubbleStackView(frame: .zero)
    /// 말풍선 높이가 바뀌면 AppDelegate 가 히트 영역을 다시 잡는다.
    var onLayoutChange: (() -> Void)?
    var onOpenFailed: (() -> Void)?

    private(set) var sheet: SpriteSheet?
    private var director = AnimationDirector(frameCounts: [:])
    private var timer: Timer?
    /// 드래그가 멈춘 것을 알아채는 타이머. 손을 멈추면 이벤트가 아예 오지 않아서,
    /// 마지막 움직임 뒤로 이만큼 조용하면 달리기를 멈춘다.
    private var dragIdle: Timer?
    private static let dragIdleSeconds = 0.2
    /// 느리게 끌 때 이벤트 하나하나는 문턱값에 못 미친다. 넘을 때까지 모아서 방향을 정한다.
    private var dragTracker = DragTracker()
    private var isRunning = false
    private var observers: [NSObjectProtocol] = []
    private(set) var aggregate: Aggregate = .empty
    private(set) var pet: InstalledPet?

    /// 켜면 말풍선을 아예 띄우지 않는다. 펫 애니메이션은 그대로 둔다.
    var isBubbleHidden = false {
        didSet {
            guard isBubbleHidden != oldValue else { return }
            stack.isBubbleHidden = isBubbleHidden
            stack.apply(aggregate)
            onLayoutChange?()
        }
    }

    init() {
        view.onClick = { [weak self] in self?.handleClick() }
        view.onDragMove = { [weak self] dx, dy in self?.dragMoved(dx: dx, dy: dy) }
        stack.onSelect = { [weak self] summary in self?.open(summary) }
        stack.onHeightChange = { [weak self] in self?.onLayoutChange?() }
        applyReducedMotion()
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.applyReducedMotion()
            self.render(self.director.current)
            self.scheduleNext()
        })
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    private static var systemReducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    private func applyReducedMotion() {
        let reduced = Self.systemReducedMotion
        director.reducedMotion = reduced
        stack.reducedMotion = reduced
    }

    func loadPet(_ pet: InstalledPet) throws {
        let sheet = try SpriteSheet(contentsOf: pet.spritesheetURL, spriteVersion: pet.manifest.spriteVersion)
        self.sheet = sheet
        self.pet = pet
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = sheet.frameCount(for: row) }
        director = AnimationDirector(frameCounts: counts)
        director.reducedMotion = Self.systemReducedMotion
        director.setState(aggregate.state)
        director.playOnce(.waving)
        render(director.current)
        scheduleNext()
    }

    func start() {
        isRunning = true
        scheduleNext()
        stack.startClock()
    }

    /// 패널이 숨겨져 있는 동안 렌더 타이머를 멈춘다(F-7). `start()`로 다시 켠다.
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
        dragIdle?.invalidate()
        dragIdle = nil
        stack.stopClock()
    }

    /// 프레임마다 길이가 달라 반복 타이머 대신 지금 프레임의 길이로 다음 advance 를 매번 예약한다.
    /// 감속 모션이면 첫 프레임 한 장으로 멈추므로 타이머를 걸지 않는다.
    private func scheduleNext() {
        timer?.invalidate(); timer = nil
        guard isRunning, !director.reducedMotion else { return }
        let next = Timer(timeInterval: Double(director.currentDurationMs) / 1000, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.render(self.director.advance())
            self.scheduleNext()
        }
        timer = next
        RunLoop.main.add(next, forMode: .common)
    }

    /// 상태가 실제로 바뀔 때만 프레임을 즉시 갈아 끼우고 타이머를 다시 잡는다.
    /// 같은 상태로 매초 불려도(폴링) 느린 idle 이 밀리지 않게.
    func apply(_ agg: Aggregate) {
        let stateChanged = agg.state != aggregate.state
        aggregate = agg
        director.setState(agg.state)
        if stateChanged {
            render(director.current)
            scheduleNext()
        }
        stack.apply(agg)
    }

    /// 마우스가 펫이나 말풍선 위에 있는 동안은 유휴 세션까지 펼쳐 보여 준다.
    func setHovered(_ hovered: Bool) {
        stack.setExpanded(hovered)
    }

    func handleClick() {
        if !SessionOpener.open(aggregate) { onOpenFailed?() }
    }

    // MARK: 끌고 다니기

    /// 끌려가는 방향으로 달리거나 뛴다. 손이 멈추면 평소 상태로 돌아간다.
    private func dragMoved(dx: Double, dy: Double) {
        // 모아 둔 값이 문턱을 넘어야 방향을 정한다. 아직 모자라면 보여 주던 것을 그대로 둔다.
        // 이벤트마다 판단하면 천천히 끌 때 달리기가 내려갔다 올라오기를 반복해 끊겨 보인다.
        //
        // 방향이 바뀐 경우에만 다시 그린다. 드래그 이벤트마다 타이머를 다시 걸면
        // 프레임 길이(120ms)가 지나기 전에 초기화되어 펫이 첫 장에 멈춰 버린다.
        if let row = dragTracker.accumulate(dx: dx, dy: dy), director.hold(row) {
            render(director.current)
            scheduleNext()
        }
        dragIdle?.invalidate()
        // 손을 멈추면 드래그 이벤트가 끊긴다. 마지막 움직임만 보고 계속 달리게 두지 않는다.
        let t = Timer(timeInterval: Self.dragIdleSeconds, repeats: false) { [weak self] _ in
            guard let self else { return }
            // 이벤트가 끊긴 것만이 손이 멈췄다는 유일한 신호다. 이동량이 작은 것은 신호가 아니다.
            self.dragTracker.reset()
            if self.director.hold(nil) {
                self.render(self.director.current)
                self.scheduleNext()
            }
        }
        dragIdle = t
        RunLoop.main.add(t, forMode: .common)
    }

    /// 손을 뗐다. 붙잡은 행을 놓고 착지 동작을 한 번 재생한다.
    func dragEnded() {
        dragIdle?.invalidate(); dragIdle = nil
        dragTracker.reset()
        director.hold(nil)
        director.playOnce(.jumping)
        render(director.current)
        scheduleNext()
    }

    /// 카드를 누르면 그 세션 하나만 담은 합성으로 연다. 펫 클릭이 대표 세션을 여는 것과 같은 길이다.
    private func open(_ summary: SessionSummary) {
        let one = Aggregate(state: summary.state, session: summary.session,
                            waitingCount: summary.state == .waiting ? 1 : 0,
                            liveSessionCount: 1, sessions: [summary])
        if !SessionOpener.open(one) { onOpenFailed?() }
    }

    private func render(_ frame: AnimationFrame) {
        guard let sheet else { return }
        let frames = sheet.frames(for: frame.row)
        guard !frames.isEmpty else { return }
        view.show(frames[min(frame.index, frames.count - 1)])
    }
}
