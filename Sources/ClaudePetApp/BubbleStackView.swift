import AppKit
import ClaudePetCore

/// 세션 카드를 펫 위로 쌓는다. 아래가 가장 급한 세션이고 위로 갈수록 덜 급하다
/// (펫 바로 위가 눈이 가장 먼저 닿는 자리다).
///
/// 평소에는 유휴가 아닌 세션만 보여 주고, 마우스를 올리면 살아 있는 세션 전부로 펼친다.
/// 카드의 생성·제거·이동은 전부 스프링으로 움직이고, 시스템 "동작 줄이기" 면 즉시 반영한다.
final class BubbleStackView: NSView {
    static let spacing: CGFloat = 6
    /// 접었을 때 겹쳐 쌓는 최대 장수. 맨 앞 한 장만 온전히 보이고 뒤의 것들은 위로 살짝 고개를 내민다.
    static let collapsedLimit = 3
    /// 겹쳐 쌓을 때 뒤 카드가 내미는 높이.
    static let peek: CGFloat = 8
    /// 뒤로 갈수록 줄어드는 비율. 깊이감을 준다.
    static let depthScale: CGFloat = 0.05
    /// 펼쳤을 때 보여 주는 최대 장수. 화면을 다 덮지 않게 막는다.
    static let expandedLimit = 8

    /// 펫 위에 남은 화면 높이로 정해지는 상한. AppDelegate 가 화면과 펫 위치를 보고 넣어 준다.
    /// 이게 없으면 펫을 화면 위쪽에 두었을 때 카드가 화면 밖으로 나간다.
    var maxCards = expandedLimit {
        didSet { if maxCards != oldValue { rebuild() } }
    }

    /// `count` 장을 쌓는 데 드는 높이.
    static func height(forCards count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return CGFloat(count) * SessionBubbleView.height + CGFloat(count - 1) * spacing
    }

    var onSelect: ((SessionSummary) -> Void)?
    /// 보이는 카드 수가 바뀌어 높이가 달라지면 알린다. 히트 영역을 다시 잡아야 한다.
    var onHeightChange: (() -> Void)?

    private var cards: [String: SessionBubbleView] = [:]
    private var visible: [SessionSummary] = []
    private var aggregate: Aggregate = .empty
    private var clock: Timer?
    private let overflow = OverflowPill()
    /// 사라지는 중인 카드. 애니메이션이 끝나기 전에 창이 줄어들면 재질(블러)이 잘린 채 화면에 남는다.
    /// 이게 비기 전까지 패널 높이를 줄이지 않는다.
    private var dismissing: Set<String> = []
    /// 사용자가 닫은 말풍선. 세션 id -> 닫을 때의 상태.
    /// 그 상태가 이어지는 동안만 감춘다. 상태가 달라지면 새로 알릴 일이 생긴 것이라 다시 뜬다.
    /// 알림을 지우는 것과 같고, 세션 자체에는 아무 영향이 없다.
    private var closed: [String: PetState] = [:]

    /// 켜면 아무것도 그리지 않는다. 메뉴의 "대화창 끄기" 가 이걸 쓴다.
    var isBubbleHidden = false

    var reducedMotion = false {
        didSet {
            guard reducedMotion != oldValue else { return }
            cards.values.forEach { $0.reducedMotion = reducedMotion }
        }
    }

    /// 마우스가 스택 위에 있으면 유휴 세션까지 펼친다.
    private(set) var isExpanded = false {
        didSet {
            guard isExpanded != oldValue else { return }
            // 펼치면 높이가 크게 늘어난다. 창을 먼저 키운 뒤 카드를 움직여야 잘리지 않는다.
            if isExpanded { onHeightChange?() }
            rebuild()
            onHeightChange?()
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        overflow.isHidden = true
        addSubview(overflow)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { clock?.invalidate() }

    // MARK: 입력

    func apply(_ agg: Aggregate) {
        aggregate = agg
        forgetClosedSessionsThatAreGone()
        rebuild()
    }

    func setExpanded(_ expanded: Bool) { isExpanded = expanded }

    /// 경과 시간 글자가 멈춰 보이지 않게 1초마다 부제만 다시 쓴다. 카드 배치는 건드리지 않는다.
    func startClock() {
        guard clock == nil else { return }
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in self?.refreshText() }
        RunLoop.main.add(t, forMode: .common)
        clock = t
    }

    func stopClock() {
        clock?.invalidate()
        clock = nil
    }

    // MARK: 화면에 올릴 세션 고르기

    private func chosen() -> (shown: [SessionSummary], hidden: Int) {
        guard !isBubbleHidden else { return ([], 0) }
        let live = aggregate.sessions.filter { closed[$0.session.sessionId] != $0.state }
        let pool = isExpanded ? live : live.filter { $0.state != .idle }
        let limit = min(isExpanded ? Self.expandedLimit : Self.collapsedLimit, max(maxCards, 1))
        let shown = Array(pool.prefix(limit))
        // 접었을 때 감춘 유휴 세션도 세어 준다. 호버하면 볼 수 있다는 힌트가 된다.
        // 사용자가 닫은 것은 세지 않는다. 치우기로 한 것을 숫자로 다시 들이밀 이유가 없다.
        return (shown, live.count - shown.count)
    }

    /// 말풍선 하나를 치운다. 그 세션의 상태가 달라지기 전까지 다시 뜨지 않는다.
    private func close(_ summary: SessionSummary) {
        closed[summary.session.sessionId] = summary.state
        rebuild()
        onHeightChange?()
    }

    /// 죽어서 목록에서 빠진 세션의 기록은 들고 있을 이유가 없다.
    private func forgetClosedSessionsThatAreGone() {
        let liveIds = Set(aggregate.sessions.map(\.session.sessionId))
        closed = closed.filter { liveIds.contains($0.key) }
    }

    /// 카드 한 장이 놓일 자리와 모양. 아래(펫에 가까운 쪽)가 가장 급한 세션이다.
    struct Slot {
        let frame: NSRect
        let scale: CGFloat
        let alphaScale: CGFloat
    }

    /// 펼친 모습은 목록, 접은 모습은 아이폰 알림처럼 겹친 더미다.
    /// 겹칠 때는 가운데를 기준으로 줄어들기 때문에, 뒤 카드가 일정하게 고개를 내밀도록 y 를 보정한다.
    private func slots(for count: Int) -> [Slot] {
        let w = SessionBubbleView.width, h = SessionBubbleView.height
        let x = (bounds.width - w) / 2
        return (0..<count).map { i in
            if isExpanded {
                return Slot(frame: NSRect(x: x, y: CGFloat(i) * (h + Self.spacing), width: w, height: h),
                            scale: 1, alphaScale: 1)
            }
            let scale = max(1 - Self.depthScale * CGFloat(i), 0.7)
            let y = CGFloat(i) * Self.peek + (1 - scale) * h / 2
            return Slot(frame: NSRect(x: x, y: y, width: w, height: h),
                        scale: scale, alphaScale: i == 0 ? 1 : max(1 - 0.3 * CGFloat(i), 0.35))
        }
    }

    /// 접힌 더미가 눈에 차지하는 높이. 맨 앞 카드 + 뒤 카드들이 내민 만큼.
    private func stackedHeight(_ count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return SessionBubbleView.height + CGFloat(count - 1) * Self.peek
    }

    /// 카드를 놓는 데 필요한 높이.
    var contentHeight: CGFloat {
        let cards = isExpanded ? Self.height(forCards: visible.count) : stackedHeight(visible.count)
        guard !overflow.isHidden else { return cards }
        return cards + Self.spacing + overflow.frame.height
    }

    /// 패널이 실제로 덮어야 하는 높이. 사라지는 중인 카드까지 포함한다.
    /// 창을 먼저 줄이면 그 카드의 블러가 잘린 자국으로 남는다.
    var occupiedHeight: CGFloat {
        let live = subviews.filter { !$0.isHidden }.map(\.frame.maxY).max() ?? 0
        return max(contentHeight, live)
    }

    /// 지금 떠 있는 말풍선이 차지하는 영역 하나. 창 좌표로 돌려준다.
    ///
    /// 카드마다 따로 주면 카드 사이 6pt 틈에 커서가 들어갔을 때 어느 사각형에도 안 잡혀
    /// 펼친 목록이 도로 접힌다. 그래서 틈까지 포함한 한 덩어리로 본다.
    var hoverBox: NSRect? {
        guard !visible.isEmpty else { return nil }
        let targets = slots(for: visible.count)
        let front = targets[0].frame
        var top = isExpanded ? (targets.last?.frame.maxY ?? front.maxY) : stackedHeight(visible.count)
        if !overflow.isHidden { top = max(top, overflow.frame.maxY) }
        let box = NSRect(x: front.minX, y: front.minY, width: front.width, height: top - front.minY)
        return convert(box, to: nil)
    }

    // MARK: 다시 그리기

    private func rebuild() {
        let (next, hiddenCount) = chosen()
        let before = visible.count
        visible = next
        let wanted = Set(next.map(\.session.sessionId))
        let targets = slots(for: next.count)
        let now = Date()

        // 카드가 늘어날 때는 창을 먼저 키운다. 그러지 않으면 새 카드가 창 밖에서 한두 프레임 잘려 보인다.
        if next.count > before { onHeightChange?() }

        // 사라질 카드
        for (id, card) in cards where !wanted.contains(id) {
            cards.removeValue(forKey: id)
            dismiss(card)
        }

        // 남거나 새로 생기는 카드
        for (i, summary) in next.enumerated() {
            let id = summary.session.sessionId
            let slot = targets[i]
            let card: SessionBubbleView
            if let existing = cards[id] {
                card = existing
                card.update(summary, now: now)
                move(card, to: slot)
            } else {
                card = SessionBubbleView(sessionId: id)
                card.reducedMotion = reducedMotion
                card.update(summary, now: now)
                addSubview(card)
                cards[id] = card
                appear(card, at: slot)
            }
            // 앞 카드가 뒤 카드를 덮는다. 겹쳐 쌓았을 때 맨 앞이 온전히 보이려면 이 순서여야 한다.
            card.layer?.zPosition = CGFloat(next.count - i)
            // 접었을 때 뒤 카드는 장식이다. 클릭도 글자도 맨 앞 카드만 갖는다.
            card.isInteractive = isExpanded || i == 0
            card.showsContent = isExpanded || i == 0
            // 콜백은 최신 상태를 물고 있어야 한다(상태가 바뀌면 여는 곳도, 닫는 기준도 달라진다).
            card.onClick = { [weak self] in self?.onSelect?(summary) }
            card.onClose = { [weak self] in self?.close(summary) }
        }

        let hadOverflow = !overflow.isHidden
        layoutOverflow(count: hiddenCount, top: targets.map(\.frame.maxY).max())
        if before != next.count || hadOverflow != !overflow.isHidden { onHeightChange?() }
    }

    /// 넘친 세션 수를 더미 위에 올린다. 0 이면 감춘다.
    private func layoutOverflow(count: Int, top: CGFloat?) {
        guard count > 0, let top else {
            overflow.isHidden = true
            return
        }
        overflow.set(count: count)
        let size = overflow.fittingSize
        let y = isExpanded ? top + Self.spacing : stackedHeight(visible.count) + Self.spacing
        overflow.frame = NSRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height)
        overflow.layer?.zPosition = 1000
        overflow.isHidden = false
    }

    /// 배치는 그대로 두고 글자만 새로 쓴다. 1초마다 불린다.
    private func refreshText() {
        guard !visible.isEmpty else { return }
        let now = Date()
        for summary in visible {
            cards[summary.session.sessionId]?.update(summary, now: now)
        }
    }

    // MARK: 애니메이션

    private func appear(_ card: SessionBubbleView, at slot: Slot) {
        guard !reducedMotion else { return settle(card, at: slot) }
        card.frame = slot.frame.offsetBy(dx: 0, dy: -8)
        card.alphaValue = 0
        card.layer?.transform = CATransform3DMakeScale(slot.scale * 0.96, slot.scale * 0.96, 1)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.34
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            settle(card, at: slot)
        }
    }

    /// 애니메이션 없이 최종 모습으로 맞춘다. 애니메이션 블록 안에서 부르면 그대로 움직인다.
    private func settle(_ card: SessionBubbleView, at slot: Slot) {
        card.animator().frame = slot.frame
        card.animator().alphaValue = card.restingAlpha * slot.alphaScale
        card.layer?.transform = CATransform3DMakeScale(slot.scale, slot.scale, 1)
    }

    private func dismiss(_ card: SessionBubbleView) {
        guard !reducedMotion else {
            card.removeFromSuperview()
            return
        }
        dismissing.insert(card.sessionId)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
            ctx.allowsImplicitAnimation = true
            card.animator().alphaValue = 0
            card.animator().frame = card.frame.offsetBy(dx: 0, dy: -6)
        } completionHandler: { [weak self] in
            card.removeFromSuperview()
            guard let self else { return }
            self.dismissing.remove(card.sessionId)
            // 마지막 카드가 빠져야 비로소 패널을 줄일 수 있다.
            if self.dismissing.isEmpty { self.onHeightChange?() }
        }
    }

    private func move(_ card: SessionBubbleView, to slot: Slot) {
        guard !reducedMotion else { return settle(card, at: slot) }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            settle(card, at: slot)
        }
    }

    override func layout() {
        super.layout()
        let targets = slots(for: visible.count)
        for (i, summary) in visible.enumerated() {
            guard let card = cards[summary.session.sessionId] else { continue }
            card.frame = targets[i].frame
            card.layer?.transform = CATransform3DMakeScale(targets[i].scale, targets[i].scale, 1)
        }
    }

    /// 마우스를 받아야 하는 영역. 접었을 때는 겹친 더미 하나로 본다.
    /// 뒤 카드는 줄어들어 그려지므로 각자의 프레임을 쓰면 실제보다 넓어진다.
}

/// 접혀서 보이지 않는 세션이 몇 개인지 알리는 작은 알약. 누를 수 없고, 마우스를 올리면 카드가 펼쳐진다.
final class OverflowPill: NSView {
    private let label = NSTextField(labelWithString: "")
    private let material = NSVisualEffectView()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerRadius = 9
        material.layer?.cornerCurve = .continuous
        material.layer?.masksToBounds = true
        addSubview(material)

        label.font = .systemFont(ofSize: 10, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        addSubview(label)
        alphaValue = 0.75
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(count: Int) {
        let text = "세션 \(count)개 더"
        if label.stringValue != text {
            label.stringValue = text
            label.sizeToFit()
            needsLayout = true
        }
    }

    override var fittingSize: NSSize { NSSize(width: label.frame.width + 20, height: 18) }

    override func layout() {
        super.layout()
        material.frame = bounds
        label.frame = NSRect(x: 10, y: (bounds.height - label.frame.height) / 2,
                             width: bounds.width - 20, height: label.frame.height)
    }

    /// 알약은 장식이다. 클릭이 밑으로 통과해야 한다.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
