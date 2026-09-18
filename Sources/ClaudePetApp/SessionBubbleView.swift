import AppKit
import ClaudePetCore

/// 상태마다의 색. 카드 배경은 재질에 맡기고 색은 점과 배지에만 준다.
/// 시스템 색을 쓰면 라이트·다크 양쪽에서 알아서 맞는다.
extension PetState {
    var accent: NSColor {
        switch self {
        case .idle: return .secondaryLabelColor
        case .running: return .systemBlue
        case .waiting: return .systemOrange
        case .failed: return .systemRed
        case .review: return .systemGreen
        }
    }
}

/// 세션 하나를 나르는 카드. 재질 배경 위에 상태 점, 제목, 부제를 얹는다.
/// 크기는 스스로 정하고(`fittingSize`), 어디에 놓을지는 `BubbleStackView` 가 정한다.
final class SessionBubbleView: NSView {
    static let width: CGFloat = 248
    static let height: CGFloat = 46
    private static let dotSize: CGFloat = 8
    private static let padding: CGFloat = 12
    /// 재질 위에 얹는 테두리. 시스템 separator 는 재질 위에서 거의 안 보여서 라벨색을 옅게 쓴다.
    private static let restingBorder = NSColor.labelColor.withAlphaComponent(0.12)
    private static let hoveredBorder = NSColor.labelColor.withAlphaComponent(0.28)
    /// 유휴 세션은 한 발 물러나 보이게 한다. 펼쳤을 때 급한 카드와 같은 무게로 읽히면 안 된다.
    private static let idleAlpha: CGFloat = 0.62

    let sessionId: String
    var onClick: (() -> Void)?
    /// 끄면 클릭도 호버도 받지 않는다. 겹쳐 쌓았을 때 뒤에 깔린 카드가 이렇다.
    var isInteractive = true {
        didSet { if !isInteractive, isHovered { setHovered(false) } }
    }

    /// 끄면 글자와 점 없이 빈 판만 남는다. 겹쳐 쌓은 뒤 카드는 아이폰 알림처럼 판만 보인다.
    /// 재질 위로 뒤 카드 글자가 비쳐 읽히는 것도 이걸로 막는다.
    var showsContent = true {
        didSet {
            guard showsContent != oldValue else { return }
            dot.isHidden = !showsContent
            titleLabel.isHidden = !showsContent
            detailLabel.isHidden = !showsContent
            if !showsContent { badge.isHidden = true } else { needsLayout = true }
        }
    }

    private let material = NSVisualEffectView()
    private let dot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private var tracking: NSTrackingArea?
    private var isHovered = false

    /// 켜면 점이 숨쉬지 않고 카드도 즉시 반응한다. 시스템 "동작 줄이기" 를 따른다.
    var reducedMotion = false {
        didSet { if reducedMotion != oldValue { applyPulse() } }
    }

    init(sessionId: String) {
        self.sessionId = sessionId
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: Self.height))
        wantsLayer = true

        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 14
        material.layer?.cornerCurve = .continuous
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = Self.restingBorder.cgColor
        material.layer?.masksToBounds = true
        addSubview(material)

        // 그림자는 재질 뷰가 아니라 바깥 레이어에 준다. masksToBounds 와 같이 못 쓴다.
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.18
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)

        dot.wantsLayer = true
        dot.layer?.cornerRadius = Self.dotSize / 2
        addSubview(dot)

        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingMiddle
        titleLabel.maximumNumberOfLines = 1
        addSubview(titleLabel)

        detailLabel.font = .systemFont(ofSize: 11, weight: .regular)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.maximumNumberOfLines = 1
        addSubview(detailLabel)

        badge.font = .systemFont(ofSize: 9, weight: .semibold)
        badge.textColor = .secondaryLabelColor
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 4
        badge.layer?.cornerCurve = .continuous
        badge.alignment = .center
        badge.isHidden = true
        addSubview(badge)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 내용

    func update(_ summary: SessionSummary, now: Date) {
        let title = BubbleText.title(for: summary)
        let elapsed = BubbleText.elapsed(now.timeIntervalSince(summary.session.timestamp))
        let detail = "\(BubbleText.detail(for: summary)) · \(elapsed)"
        let isCodex = summary.session.agent == .codex

        if titleLabel.stringValue != title { titleLabel.stringValue = title }
        if detailLabel.stringValue != detail { detailLabel.stringValue = detail }
        if isCodex, badge.stringValue.isEmpty { badge.stringValue = "Codex" }
        badge.isHidden = !isCodex || !showsContent
        badge.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.14).cgColor

        dot.layer?.backgroundColor = summary.state.accent.cgColor
        isRunning = summary.state == .running
        restingAlpha = summary.state == .idle ? Self.idleAlpha : 1
        if !isHovered { alphaValue = restingAlpha }
        applyPulse()
        needsLayout = true
    }

    private var isRunning = false
    /// 마우스가 올라가 있지 않을 때의 불투명도. 유휴 카드만 낮다.
    private(set) var restingAlpha: CGFloat = 1

    // MARK: 배치

    override func layout() {
        super.layout()
        material.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)

        let p = Self.padding
        dot.frame = NSRect(x: p, y: (bounds.height - Self.dotSize) / 2, width: Self.dotSize, height: Self.dotSize)

        let textX = dot.frame.maxX + 9
        var titleWidth = bounds.width - textX - p
        if !badge.isHidden {
            badge.sizeToFit()
            let w = badge.frame.width + 4
            badge.frame = NSRect(x: bounds.width - p - w, y: bounds.height / 2 + 2, width: w, height: 13)
            titleWidth -= w + 6
        }
        titleLabel.frame = NSRect(x: textX, y: bounds.height / 2 + 1, width: max(0, titleWidth), height: 16)
        detailLabel.frame = NSRect(x: textX, y: bounds.height / 2 - 16, width: bounds.width - textX - p, height: 14)
    }

    // MARK: 호버와 클릭

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(isInteractive) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        let apply = {
            self.material.layer?.borderColor = (hovered ? Self.hoveredBorder : Self.restingBorder).cgColor
            self.layer?.shadowOpacity = hovered ? 0.28 : 0.18
            self.alphaValue = hovered ? 1 : self.restingAlpha
        }
        if reducedMotion {
            apply()
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                apply()
            }
        }
    }

    /// 패널이 nonactivating 이라 모든 클릭이 first mouse 다. 이걸 받지 않으면 클릭이 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { isInteractive }

    override func hitTest(_ point: NSPoint) -> NSView? { isInteractive ? super.hitTest(point) : nil }
    override func mouseUp(with event: NSEvent) { if isInteractive { onClick?() } }

    // MARK: 숨쉬는 점

    private func applyPulse() {
        let key = "petPulse"
        dot.layer?.removeAnimation(forKey: key)
        guard isRunning, !reducedMotion else {
            dot.layer?.opacity = 1
            return
        }
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue = 0.35
        a.duration = 0.9
        a.autoreverses = true
        a.repeatCount = .infinity
        a.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        dot.layer?.add(a, forKey: key)
    }
}
