#if os(macOS)
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

    /// 카드마다 높이가 다르다(미리보기가 붙으면 길어지고 호버하면 더 길어진다). 그래서 장수만으로는
    /// 높이를 셀 수 없다. 화면에 몇 장이 들어가는지 가늠할 때만 쓰고, 그때는 가장 긴 카드로 센다.
    /// 짧은 쪽으로 어림하면 미리보기가 붙은 카드가 화면 밖으로 밀려 나간다.
    /// 위에 얹히는 알약(넘친 수 또는 전체 제거)도 늘 있다고 보고 센다.
    static func height(forCards count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        let tallest = SessionBubbleView.height(previewLines: 2)
        return CGFloat(count) * tallest + CGFloat(count) * spacing + PillView.height
    }

    var onSelect: ((SessionSummary) -> Void)?
    /// 보이는 카드 수가 바뀌어 높이가 달라지면 알린다. 히트 영역을 다시 잡아야 한다.
    var onHeightChange: (() -> Void)?

    private var cards: [String: SessionBubbleView] = [:]
    private var visible: [SessionSummary] = []
    private var aggregate: Aggregate = .empty
    private var clock: Timer?
    private let overflow = PillView()
    /// 펼쳤을 때 넘친 수 알약 자리에 대신 뜬다. 살아 있는 세션의 말풍선을 한꺼번에 치운다.
    private let closeAllButton = PillView()
    /// 접혀서 안 보이는 세션 수. 알약에 적는다.
    private var hiddenCount = 0
    /// 사라지는 중인 카드. 애니메이션이 끝나기 전에 창이 줄어들면 재질(블러)이 잘린 채 화면에 남는다.
    /// 이게 비기 전까지 패널 높이를 줄이지 않는다.
    private var dismissing: Set<String> = []
    /// 마우스가 올라가 있는 카드. 그 카드만 미리보기를 두 줄로 편다.
    private var hoveredId: String?
    /// 트랜스크립트에서 읽은 미리보기 글자. 파일이 자란 것만 다시 읽는다.
    private let transcripts = TranscriptStore()
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
        closeAllButton.set(text: "전체 제거")
        closeAllButton.toolTip = "말풍선 전부 닫기"
        closeAllButton.setAccessibilityLabel("말풍선 전부 닫기")
        closeAllButton.onClick = { [weak self] in self?.closeAll() }
        closeAllButton.isHidden = true
        addSubview(closeAllButton)
    }
    required init?(coder: NSCoder) { fatalError() }

    deinit { clock?.invalidate() }

    // MARK: 입력

    func apply(_ agg: Aggregate) {
        aggregate = agg
        forgetClosedSessionsThatAreGone()
        transcripts.forgetAll(except: Set(agg.sessions.compactMap(\.session.transcript)))
        rebuild()
    }

    /// 마우스가 오르내리면 그 카드의 미리보기가 한 줄에서 두 줄로 펴진다. 높이가 달라지니 다시 쌓는다.
    private func cardHoverChanged(_ summary: SessionSummary, hovered: Bool) {
        let id = summary.session.sessionId
        if hovered {
            hoveredId = id
        } else if hoveredId == id {
            hoveredId = nil
        } else {
            return
        }
        guard preview(for: summary) != nil else { return }
        relayout()
    }

    /// 카드를 지우거나 만들지 않고 자리만 다시 잡는다.
    private func relayout() {
        let targets = slots(for: visible)
        onHeightChange?()
        for (i, summary) in visible.enumerated() {
            guard let card = cards[summary.session.sessionId] else { continue }
            move(card, to: targets[i])
        }
        // 카드 높이가 달라졌으니 그 위에 얹힌 알약도 따라 올라가야 한다. 안 그러면 카드에 덮인다.
        layoutTopRow()
        onHeightChange?()
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

    /// 살아 있는 세션의 말풍선을 전부 치운다. 하나씩 닫는 것과 같아서 상태가 달라진 세션은 다시 뜬다.
    private func closeAll() {
        for summary in aggregate.sessions { closed[summary.session.sessionId] = summary.state }
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

    /// 그 세션 카드가 차지할 높이. 미리보기가 있으면 한 줄, 마우스가 올라가 있으면 두 줄만큼 길다.
    private func height(for summary: SessionSummary) -> CGFloat {
        guard preview(for: summary) != nil else { return SessionBubbleView.height }
        let lines = hoveredId == summary.session.sessionId ? 2 : 1
        return SessionBubbleView.height(previewLines: lines)
    }

    private func preview(for summary: SessionSummary) -> String? {
        transcripts.preview(for: summary)
    }

    /// 펼친 모습은 목록, 접은 모습은 아이폰 알림처럼 겹친 더미다.
    /// 겹칠 때는 가운데를 기준으로 줄어들기 때문에, 뒤 카드가 일정하게 고개를 내밀도록 y 를 보정한다.
    private func slots(for summaries: [SessionSummary]) -> [Slot] {
        let w = SessionBubbleView.width
        let x = (bounds.width - w) / 2
        guard !summaries.isEmpty else { return [] }

        if isExpanded {
            // 아래에서 위로 쌓으면서 카드마다 제 높이만큼 자리를 준다.
            var y: CGFloat = 0
            return summaries.map { summary in
                let h = height(for: summary)
                let slot = Slot(frame: NSRect(x: x, y: y, width: w, height: h), scale: 1, alphaScale: 1)
                y += h + Self.spacing
                return slot
            }
        }

        // 접힌 더미: 맨 앞만 온전한 카드고 뒤는 빈 판이다. 판은 앞 카드 위로 일정하게 고개를 내민다.
        // 가운데를 기준으로 줄어들기 때문에 내민 높이가 일정해지도록 y 를 보정한다.
        let frontHeight = height(for: summaries[0])
        return summaries.enumerated().map { i, summary in
            guard i > 0 else {
                return Slot(frame: NSRect(x: x, y: 0, width: w, height: frontHeight), scale: 1, alphaScale: 1)
            }
            let h = SessionBubbleView.height
            let scale = max(1 - Self.depthScale * CGFloat(i), 0.7)
            let y = frontHeight + CGFloat(i) * Self.peek - h + (1 - scale) * h / 2
            return Slot(frame: NSRect(x: x, y: y, width: w, height: h),
                        scale: scale, alphaScale: max(1 - 0.3 * CGFloat(i), 0.35))
        }
    }

    /// 접힌 더미가 눈에 차지하는 높이. 맨 앞 카드 + 뒤 판들이 내민 만큼.
    private func stackedHeight(_ summaries: [SessionSummary]) -> CGFloat {
        guard let front = summaries.first else { return 0 }
        return height(for: front) + CGFloat(summaries.count - 1) * Self.peek
    }

    /// 카드가 끝나는 높이. 알약 줄은 이 위에 놓인다.
    private var cardsTop: CGFloat {
        isExpanded ? (slots(for: visible).last?.frame.maxY ?? 0) : stackedHeight(visible)
    }

    /// 더미 위 알약(넘친 수 또는 전체 제거). 보이는 것만.
    private var topRow: [PillView] { [overflow, closeAllButton].filter { !$0.isHidden } }

    /// 카드를 놓는 데 필요한 높이.
    var contentHeight: CGFloat {
        let row = topRow.map(\.frame.height).max() ?? 0
        return row > 0 ? cardsTop + Self.spacing + row : cardsTop
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
        let targets = slots(for: visible)
        let front = targets[0].frame
        // 알약 줄까지 넣는다. 빠지면 "전체 제거" 로 손을 옮기는 순간 호버가 풀려 목록이 접히고 버튼이 사라진다.
        let top = topRow.map(\.frame.maxY).reduce(cardsTop, max)
        let box = NSRect(x: front.minX, y: front.minY, width: front.width, height: top - front.minY)
        return convert(box, to: nil)
    }

    // MARK: 다시 그리기

    private func rebuild() {
        let (next, hidden) = chosen()
        let before = visible.count
        let heightBefore = contentHeight
        visible = next
        hiddenCount = hidden
        let wanted = Set(next.map(\.session.sessionId))
        let targets = slots(for: next)
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
                card.update(summary, now: now, preview: preview(for: summary))
                move(card, to: slot)
            } else {
                card = SessionBubbleView(sessionId: id)
                card.reducedMotion = reducedMotion
                card.update(summary, now: now, preview: preview(for: summary))
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
            card.onHoverChange = { [weak self] hovered in self?.cardHoverChanged(summary, hovered: hovered) }
        }

        layoutTopRow()
        // 장수가 그대로여도 높이는 달라질 수 있다(상태가 바뀌어 미리보기가 붙는 경우). 그때 창을 안 키우면
        // 위로 올라간 알약이 창 밖으로 밀려 윗부분이 잘린다.
        if before != next.count || contentHeight != heightBefore { onHeightChange?() }
    }

    /// 더미 위 가운데에 알약 하나를 얹는다. 접었을 때는 넘친 수("세션 N개 더")를 알리고,
    /// 펼쳤을 때는 같은 자리가 "전체 제거" 버튼으로 바뀐다. 펼치면 다 보이니 수를 알릴 일이 없다.
    private func layoutTopRow() {
        let y = cardsTop + Self.spacing
        let shown: PillView?
        if visible.isEmpty {
            shown = nil
        } else if isExpanded {
            shown = closeAllButton
        } else if hiddenCount > 0 {
            overflow.set(text: "세션 \(hiddenCount)개 더")
            shown = overflow
        } else {
            shown = nil
        }
        for pill in [overflow, closeAllButton] where pill !== shown { pill.isHidden = true }
        guard let shown else { return }
        let size = shown.fittingSize
        place(shown, at: NSRect(x: (bounds.width - size.width) / 2, y: y, width: size.width, height: size.height))
    }

    /// 새로 뜨는 알약은 살짝 내려앉으며 나타나고, 떠 있던 알약은 카드와 같은 곡선으로 따라 움직인다.
    private func place(_ pill: PillView, at frame: NSRect) {
        pill.layer?.zPosition = 1000
        let appearing = pill.isHidden
        guard !reducedMotion else {
            pill.frame = frame
            pill.alphaValue = 1
            pill.isHidden = false
            return
        }
        if appearing {
            pill.frame = frame.offsetBy(dx: 0, dy: -4)
            pill.alphaValue = 0
            pill.isHidden = false
        } else if pill.frame == frame {
            return
        }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = appearing ? 0.24 : 0.28
            ctx.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.2, 1.0)
            ctx.allowsImplicitAnimation = true
            pill.animator().frame = frame
            pill.animator().alphaValue = 1
        }
    }

    /// 배치는 그대로 두고 글자만 새로 쓴다. 1초마다 불린다.
    private func refreshText() {
        guard !visible.isEmpty else { return }
        let now = Date()
        var heightChanged = false
        for summary in visible {
            guard let card = cards[summary.session.sessionId] else { continue }
            card.update(summary, now: now, preview: preview(for: summary))
            // 훅이 상태 파일을 쓴 뒤에야 에이전트가 트랜스크립트를 비운다. 그 틈에 읽으면 미리보기가
            // 비어 있고 다음 초에 생긴다. 그때 카드 높이가 그대로면 글자가 들어갈 자리가 없다.
            if abs(card.frame.height - height(for: summary)) > 0.5 { heightChanged = true }
        }
        if heightChanged { relayout() }
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
        let targets = slots(for: visible)
        for (i, summary) in visible.enumerated() {
            guard let card = cards[summary.session.sessionId] else { continue }
            card.frame = targets[i].frame
            card.layer?.transform = CATransform3DMakeScale(targets[i].scale, targets[i].scale, 1)
        }
        // 너비가 바뀌면(배율 변경) 가운데 정렬이 어긋난다.
        layoutTopRow()
    }

    /// 마우스를 받아야 하는 영역. 접었을 때는 겹친 더미 하나로 본다.
    /// 뒤 카드는 줄어들어 그려지므로 각자의 프레임을 쓰면 실제보다 넓어진다.
}

/// 더미 위에 얹는 캡슐. 카드와 같은 재질·테두리·그림자를 써서 한 벌로 보이게 한다.
/// `onClick` 이 없으면 장식이라 클릭이 밑으로 통과하고, 있으면 누를 수 있고 마우스를 올리면 밝아진다.
final class PillView: NSView {
    static let height: CGFloat = 22
    static let horizontalPadding: CGFloat = 10
    private static let restingBorder = NSColor.labelColor.withAlphaComponent(0.12)
    private static let hoveredBorder = NSColor.labelColor.withAlphaComponent(0.28)

    private let label = NSTextField(labelWithString: "")
    private let material = NSVisualEffectView()
    /// 마우스를 올렸을 때 재질 위에 얇게 까는 밝은 막. 알림 센터 버튼이 호버에 반응하는 방식이다.
    private let wash = NSView()
    private var tracking: NSTrackingArea?
    private var isHovered = false

    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        material.layer?.cornerCurve = .continuous
        material.layer?.borderWidth = 0.5
        material.layer?.borderColor = Self.restingBorder.cgColor
        material.layer?.masksToBounds = true
        addSubview(material)

        wash.wantsLayer = true
        wash.layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(0.08).cgColor
        wash.alphaValue = 0
        material.addSubview(wash)

        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        // 한 줄로 못 박는다. 기본값이면 sizeToFit 너비가 반올림으로 모자랄 때 띄어쓰기에서 줄이 넘어가
        // 둘째 줄이 잘려 나간다("전체 닫기" 가 "전체" 로만 보였다).
        label.usesSingleLineMode = true
        label.maximumNumberOfLines = 1
        label.lineBreakMode = .byClipping
        addSubview(label)
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(text: String) {
        guard label.stringValue != text else { return }
        label.stringValue = text
        needsLayout = true
    }

    var textWidth: CGFloat { ceil(label.intrinsicContentSize.width) }

    override var fittingSize: NSSize {
        NSSize(width: textWidth + Self.horizontalPadding * 2, height: Self.height)
    }

    override func layout() {
        super.layout()
        material.frame = bounds
        material.layer?.cornerRadius = bounds.height / 2
        wash.frame = material.bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2,
                                   cornerHeight: bounds.height / 2, transform: nil)
        let h = ceil(label.intrinsicContentSize.height)
        label.frame = NSRect(x: (bounds.width - textWidth) / 2, y: (bounds.height - h) / 2, width: textWidth, height: h)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        tracking = nil
        guard onClick != nil else { return }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ hovered: Bool) {
        guard hovered != isHovered else { return }
        isHovered = hovered
        material.layer?.borderColor = (hovered ? Self.hoveredBorder : Self.restingBorder).cgColor
        label.textColor = hovered ? .labelColor : .secondaryLabelColor
        wash.alphaValue = hovered ? 1 : 0
    }

    override var isHidden: Bool {
        didSet { if isHidden { setHovered(false) } }
    }

    /// 장식일 때는 클릭이 밑으로 통과해야 한다.
    override func hitTest(_ point: NSPoint) -> NSView? { onClick == nil ? nil : super.hitTest(point) }
    /// 패널이 nonactivating 이라 모든 클릭이 first mouse 다. 이걸 받지 않으면 첫 클릭이 삼켜진다.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { onClick != nil }
    override func mouseDown(with event: NSEvent) { if onClick == nil { super.mouseDown(with: event) } }
    override func mouseUp(with event: NSEvent) {
        guard let onClick, bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick()
    }
}

#endif
