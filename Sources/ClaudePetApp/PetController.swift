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
    private(set) var aggregate: Aggregate = .empty
    private(set) var pet: InstalledPet?

    /// 켜면 말풍선을 아예 띄우지 않는다. 펫 애니메이션은 그대로 둔다.
    var isBubbleHidden = false {
        didSet { if isBubbleHidden != oldValue { refreshBubble() } }
    }

    init() {
        view.onClick = { [weak self] in self?.handleClick() }
    }

    func loadPet(_ pet: InstalledPet) throws {
        let sheet = try SpriteSheet(contentsOf: pet.spritesheetURL, spriteVersion: pet.manifest.spriteVersion)
        self.sheet = sheet
        self.pet = pet
        var counts: [SpriteRow: Int] = [:]
        for row in SpriteRow.allCases { counts[row] = sheet.frameCount(for: row) }
        director = AnimationDirector(frameCounts: counts)
        director.setState(aggregate.state)
        director.playOnce(.waving)
        render(director.current)
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / Double(AnimationDirector.fps), repeats: true) { [weak self] _ in
            guard let self else { return }
            self.render(self.director.advance())
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    /// 패널이 숨겨져 있는 동안 렌더 타이머를 멈춘다(F-7). `start()`로 다시 켠다.
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func apply(_ agg: Aggregate) {
        aggregate = agg
        director.setState(agg.state)
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
