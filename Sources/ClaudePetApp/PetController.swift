import AppKit
import ClaudePetCore

/// 시트·디렉터·타이머를 묶어 뷰에 프레임을 밀어 넣고, 말풍선과 클릭을 다룬다.
final class PetController {
    let view = PetLayerView(frame: .zero)
    let bubble = SpeechBubbleView(frame: .zero)
    /// 말풍선 크기가 바뀌면 AppDelegate 가 패널 크기를 다시 잡는다.
    var onLayoutChange: (() -> Void)?
    var onOpenFailed: (() -> Void)?

    private(set) var sheet: SpriteSheet?
    private var director = AnimationDirector(frameCounts: [:])
    private var timer: Timer?
    private var isRunning = false
    private var observers: [NSObjectProtocol] = []
    private(set) var aggregate: Aggregate = .empty
    private(set) var pet: InstalledPet?

    /// 켜면 말풍선을 아예 띄우지 않는다. 펫 애니메이션은 그대로 둔다.
    var isBubbleHidden = false {
        didSet { if isBubbleHidden != oldValue { refreshBubble() } }
    }

    init() {
        view.onClick = { [weak self] in self?.handleClick() }
        director.reducedMotion = Self.systemReducedMotion
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.director.reducedMotion = Self.systemReducedMotion
            self.render(self.director.current)
            self.scheduleNext()
        })
    }

    deinit { observers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) } }

    private static var systemReducedMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

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
    }

    /// 패널이 숨겨져 있는 동안 렌더 타이머를 멈춘다(F-7). `start()`로 다시 켠다.
    func stop() {
        isRunning = false
        timer?.invalidate()
        timer = nil
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

    /// 상태가 실제로 바뀔 때만 프레임을 즉시 갈아 끼우고 타이머를 다시 잡는다. 같은 상태로 매초 불려도(폴링) 느린 idle 이 밀리지 않게.
    func apply(_ agg: Aggregate) {
        let stateChanged = agg.state != aggregate.state
        aggregate = agg
        director.setState(agg.state)
        if stateChanged {
            render(director.current)
            scheduleNext()
        }
        refreshBubble()
    }

    /// 현재 상태와 설정으로 말풍선을 다시 그린다. 크기가 바뀌면 패널 레이아웃을 다시 잡게 한다.
    private func refreshBubble() {
        let before = bubble.frame.size
        let after = bubble.update(text: isBubbleHidden ? nil : BubbleText.text(for: aggregate),
                                  emphasis: isBubbleHidden ? .none : BubbleText.emphasis(for: aggregate.state),
                                  maxWidth: 220)
        if before != after { onLayoutChange?() }
    }

    func handleClick() {
        if !SessionOpener.open(aggregate) { onOpenFailed?() }
    }

    private func render(_ frame: AnimationFrame) {
        guard let sheet else { return }
        let frames = sheet.frames(for: frame.row)
        guard !frames.isEmpty else { return }
        view.show(frames[min(frame.index, frames.count - 1)])
    }
}
