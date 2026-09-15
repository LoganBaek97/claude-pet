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

    init() {
        view.onClick = { [weak self] in self?.handleClick() }
    }

    func loadPet(_ pet: InstalledPet) throws {
        let sheet = try SpriteSheet(contentsOf: pet.spritesheetURL)
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
        let before = bubble.frame.size
        let after = bubble.update(text: BubbleText.text(for: agg), emphasis: BubbleText.emphasis(for: agg.state), maxWidth: 220)
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
