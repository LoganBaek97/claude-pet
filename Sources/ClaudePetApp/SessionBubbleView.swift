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

/// 패널이 nonactivating 이라 키 윈도우가 될 수 없어서 모든 클릭이 first mouse 다.
/// NSButton 은 기본적으로 first mouse 를 받지 않아 그대로 두면 닫기 버튼이 첫 클릭을 삼킨다.
final class FirstMouseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// 세션 하나를 나르는 카드. 재질 배경 위에 상태 점, 제목, 부제를 얹는다.
/// 크기는 스스로 정하고(`fittingSize`), 어디에 놓을지는 `BubbleStackView` 가 정한다.
final class SessionBubbleView: NSView {
    static let width: CGFloat = 248
    /// 제목과 부제만 있는 카드 높이.
    static let height: CGFloat = 46
    /// 미리보기 한 줄, 두 줄이 붙었을 때의 높이. 호버하면 한 줄에서 두 줄로 편다.
    static let previewLine: CGFloat = 16
    static func height(previewLines: Int) -> CGFloat {
        height + CGFloat(previewLines) * previewLine
    }
    private static let dotSize: CGFloat = 8
    private static let padding: CGFloat = 12
    /// 재질 위에 얹는 테두리. 시스템 separator 는 재질 위에서 거의 안 보여서 라벨색을 옅게 쓴다.
    private static let restingBorder = NSColor.labelColor.withAlphaComponent(0.12)
    private static let hoveredBorder = NSColor.labelColor.withAlphaComponent(0.28)
    /// 유휴 세션은 한 발 물러나 보이게 한다. 펼쳤을 때 급한 카드와 같은 무게로 읽히면 안 된다.
    private static let idleAlpha: CGFloat = 0.62
    private static let closeSize: CGFloat = 16

    let sessionId: String
    var onClick: (() -> Void)?
    /// 닫기 버튼. 그 세션의 말풍선을 지금 상태에 한해 치운다.
    var onClose: (() -> Void)?
    /// 호버가 바뀌면 미리보기가 한 줄에서 두 줄로 펴져 카드 높이가 달라진다. 스택이 다시 쌓아야 한다.
    var onHoverChange: ((Bool) -> Void)?
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
            if !showsContent {
                badge.isHidden = true
                previewLabel.isHidden = true
                closeButton.isHidden = true
                closeButton.alphaValue = 0
            } else {
                needsLayout = true
            }
        }
    }

    private let material = NSVisualEffectView()
    private let dot = NSView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let badge = NSTextField(labelWithString: "")
    private let previewLabel = NSTextField(labelWithString: "")
    private let closeButton = FirstMouseButton()
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

        previewLabel.font = .systemFont(ofSize: 11, weight: .regular)
        previewLabel.textColor = .tertiaryLabelColor
        // "정해진 줄 수까지 감고 마지막 줄만 말줄임" 은 이 셋이 다 있어야 한다.
        // wraps 로 여러 줄을 허용하고, 줄바꿈은 단어 단위로 두고, 마지막 줄 줄임은
        // truncatesLastVisibleLine 이 맡는다. lineBreakMode 를 .byTruncatingTail 로 주면
        // 줄 수와 상관없이 첫 줄에서 잘린다.
        previewLabel.usesSingleLineMode = false
        previewLabel.cell?.wraps = true
        previewLabel.cell?.isScrollable = false
        previewLabel.cell?.truncatesLastVisibleLine = true
        previewLabel.lineBreakMode = .byWordWrapping
        previewLabel.maximumNumberOfLines = 1
        previewLabel.isHidden = true
        addSubview(previewLabel)

        // macOS 알림처럼 좌상단 모서리에 걸친다. 마우스를 올렸을 때만 보인다.
        closeButton.bezelStyle = .circular
        closeButton.isBordered = false
        closeButton.image = NSImage(systemSymbolName: "xmark.circle.fill",
                                    accessibilityDescription: "말풍선 닫기")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        closeButton.imagePosition = .imageOnly
        closeButton.contentTintColor = .secondaryLabelColor
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.alphaValue = 0
        closeButton.isHidden = true
        closeButton.toolTip = "이 말풍선 닫기"
        addSubview(closeButton)
    }

    @objc private func closeClicked() { onClose?() }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: 내용

    func update(_ summary: SessionSummary, now: Date, preview: String?) {
        let title = BubbleText.title(for: summary)
        let elapsed = BubbleText.elapsed(now.timeIntervalSince(summary.session.timestamp))
        let detail = "\(BubbleText.detail(for: summary)) · \(elapsed)"
        let isCodex = summary.session.agent == .codex

        if titleLabel.stringValue != title { titleLabel.stringValue = title }
        if detailLabel.stringValue != detail { detailLabel.stringValue = detail }
        if isCodex, badge.stringValue.isEmpty { badge.stringValue = "Codex" }
        badge.isHidden = !isCodex || !showsContent
        badge.layer?.backgroundColor = NSColor.secondaryLabelColor.withAlphaComponent(0.14).cgColor

        let previewText = preview ?? ""
        if previewLabel.stringValue != previewText { previewLabel.stringValue = previewText }
        previewLabel.isHidden = previewText.isEmpty || !showsContent

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

    /// 미리보기가 있으면 평소 한 줄, 마우스를 올리면 두 줄. 없으면 0.
    var previewLines: Int {
        guard showsContent, previewLabel.stringValue.isEmpty == false else { return 0 }
        return isHovered ? 2 : 1
    }

    /// 이 카드가 지금 차지해야 하는 높이.
    var wantedHeight: CGFloat { Self.height(previewLines: previewLines) }

    // MARK: 배치

    override func layout() {
        super.layout()
        material.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: 14, cornerHeight: 14, transform: nil)

        let p = Self.padding
        // 제목 줄은 카드 위쪽에 붙인다. 미리보기가 붙어 카드가 길어져도 제목 자리는 그대로다.
        let titleY = bounds.height - 22
        dot.frame = NSRect(x: p, y: titleY + (16 - Self.dotSize) / 2, width: Self.dotSize, height: Self.dotSize)
        // 치우는 버튼은 제목 줄 끝에 둔다. 자리는 호버 여부와 상관없이 늘 비워 두어 글자가 밀리지 않게 한다.
        closeButton.frame = NSRect(x: bounds.width - p - Self.closeSize, y: titleY + (16 - Self.closeSize) / 2,
                                   width: Self.closeSize, height: Self.closeSize)

        let textX = dot.frame.maxX + 9
        let textWidth = max(0, closeButton.frame.minX - 8 - textX)

        // 배지는 제목 바로 옆에 붙는다. 제목이 길면 제목이 먼저 줄고 배지는 자리를 지킨다.
        titleLabel.sizeToFit()
        var titleWidth = min(titleLabel.frame.width, textWidth)
        if !badge.isHidden {
            badge.sizeToFit()
            let w = badge.frame.width + 8
            titleWidth = min(titleWidth, max(0, textWidth - w - 6))
            badge.frame = NSRect(x: textX + titleWidth + 6, y: titleY + 2, width: badge.frame.width + 8, height: 13)
        }
        titleLabel.frame = NSRect(x: textX, y: titleY, width: titleWidth, height: 16)
        let detailY = titleY - 17
        detailLabel.frame = NSRect(x: textX, y: detailY, width: textWidth, height: 14)
        // 줄 수는 지금 받은 높이에서 뽑는다. 호버 상태로 따로 세면 스택이 정한 높이와 어긋나
        // 글자가 말줄임표도 없이 잘린다. 높이를 정하는 쪽은 스택 하나뿐이어야 한다.
        let previewHeight = max(0, detailY - 8)
        previewLabel.maximumNumberOfLines = max(1, Int((previewHeight / Self.previewLine).rounded()))
        previewLabel.frame = NSRect(x: textX, y: 6, width: textWidth, height: previewHeight)
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

    func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        let showClose = hovered && showsContent
        if showClose { closeButton.isHidden = false }
        let apply = {
            self.material.layer?.borderColor = (hovered ? Self.hoveredBorder : Self.restingBorder).cgColor
            self.layer?.shadowOpacity = hovered ? 0.28 : 0.18
            self.alphaValue = hovered ? 1 : self.restingAlpha
            self.closeButton.alphaValue = showClose ? 1 : 0
        }
        if reducedMotion {
            apply()
            closeButton.isHidden = !showClose
        } else {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.16
                ctx.allowsImplicitAnimation = true
                apply()
            } completionHandler: { [weak self] in
                guard let self, !showClose else { return }
                self.closeButton.isHidden = true
            }
        }
        onHoverChange?(hovered)
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
