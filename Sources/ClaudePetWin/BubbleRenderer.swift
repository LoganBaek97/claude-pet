#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

/// 말풍선 카드를 PixelSurface 에 그린다.
///
/// GDI+ 의 C++ 헤더는 Swift 에서 가져올 수 없으므로 GDI DrawTextW 로 불투명 카드를 그린다.
/// 카드는 어둡고 불투명(alpha 0xFF)하며 글자는 흰색이다.
/// mac 의 반투명 재질 카드와 달리 뒤가 비치지 않지만, 화면에서 읽는 데 문제없다.
final class BubbleRenderer {
    static let cardWidth: Int = 248
    static let cardHeight: Int = 46
    static let cardHeightWithPreview: Int = 62
    static let spacing: Int = 6
    static let cornerRadius: Int = 14
    static let dotSize: Int = 8
    static let padding: Int = 12
    static let closeSize: Int = 16

    // 카드 스타일 (불투명 어두운 카드)
    static let bgR: UInt8 = 30, bgG: UInt8 = 30, bgB: UInt8 = 30, bgA: UInt8 = 0xFF
    static let textR: UInt8 = 240, textG: UInt8 = 240, textB: UInt8 = 240

    /// 카드 한 장의 히트 정보. 클릭과 닫기 판정에 쓴다.
    struct CardHit {
        let summary: SessionSummary
        let rect: (x: Int, y: Int, w: Int, h: Int)
        let closeRect: (x: Int, y: Int, w: Int, h: Int)
    }

    private let transcripts = TranscriptStore()
    private var closed: [String: PetState] = [:]
    private(set) var isExpanded = false
    var isBubbleHidden = false

    /// 마지막으로 그린 카드의 히트 정보.
    private(set) var cardHits: [CardHit] = []
    private(set) var overflowCount = 0
    /// 호버 중인 카드 id.
    var hoveredId: String?

    func setExpanded(_ expanded: Bool) { isExpanded = expanded }

    func close(_ summary: SessionSummary) {
        closed[summary.session.sessionId] = summary.state
    }

    /// 죽은 세션 기록 정리.
    func forgetGone(liveIds: Set<String>) {
        closed = closed.filter { liveIds.contains($0.key) }
    }

    func forgetTranscripts(liveTranscripts: Set<String>) {
        transcripts.forgetAll(except: liveTranscripts)
    }

    /// 최대 카드 수 (화면 높이 제한).
    var maxCards: Int = BubbleSelection.expandedLimit

    /// 말풍선 영역을 그려 돌려준다. 카드가 없으면 nil.
    ///
    /// Windows 좌표계(top-down): y=0 이 맨 위. 카드는 위에서 아래로 쌓이고,
    /// 가장 급한 세션이 펫에 가장 가까운 아래쪽에 온다(mac 과 동일한 시각 효과).
    func render(aggregate: Aggregate, surfaceWidth: Int) -> (surface: PixelSurface, totalHeight: Int)? {
        let selection = BubbleSelection.choose(
            sessions: aggregate.sessions,
            isExpanded: isExpanded,
            isBubbleHidden: isBubbleHidden,
            maxCards: maxCards,
            closed: closed
        )
        overflowCount = selection.hiddenCount

        guard !selection.shown.isEmpty else {
            cardHits = []
            return nil
        }

        let now = Date()
        let cards = selection.shown
        // 급한 순서가 앞(index 0)이고 펫에 가장 가까운 아래에 온다.
        // 위에서 아래로: 덜 급한 것이 위, 급한 것이 아래.
        // cards 는 이미 급한 순서. 거꾸로 배치하면 index 0 이 맨 아래.
        let reversed = cards.reversed()

        let cardW = Self.cardWidth
        var totalH = 0
        var rects: [(x: Int, y: Int, w: Int, h: Int)] = []
        for _ in reversed {
            let h = Self.cardHeight
            let x = max(0, (surfaceWidth - cardW) / 2)
            rects.append((x: x, y: totalH, w: cardW, h: h))
            totalH += h + Self.spacing
        }
        if totalH > 0 { totalH -= Self.spacing } // 마지막 spacing 제거

        // 넘침 알약
        let overflowH = 18
        if overflowCount > 0 {
            totalH += Self.spacing + overflowH
        }

        guard totalH > 0 else { cardHits = []; return nil }

        var surface = PixelSurface(width: surfaceWidth, height: totalH)
        var hits: [CardHit] = []

        // 카드 그리기 (reversed 순서로 위에서 아래)
        for (i, summary) in reversed.enumerated() {
            let rect = rects[i]
            // 배경
            surface.fillRoundedRect(x: rect.x, y: rect.y, w: rect.w, h: rect.h,
                                     radius: Self.cornerRadius,
                                     r: Self.bgR, g: Self.bgG, b: Self.bgB, a: Self.bgA)
            // 상태 점
            let dotColor = stateColor(summary.state)
            let dotY = rect.y + Self.padding
            let dotX = rect.x + Self.padding
            surface.fillRect(x: dotX, y: dotY, w: Self.dotSize, h: Self.dotSize,
                            r: dotColor.r, g: dotColor.g, b: dotColor.b, a: 255)

            // 텍스트는 GDI 로 그린다 (별도 함수)
            let title = BubbleText.title(for: summary)
            let elapsed = BubbleText.elapsed(now.timeIntervalSince(summary.session.timestamp))
            let detail = "\(BubbleText.detail(for: summary)) · \(elapsed)"
            drawCardText(&surface, rect: rect, title: title, detail: detail)

            // 닫기 버튼 영역 (호버 중일 때만 시각적으로 보이지만 히트 영역은 항상 잡는다)
            let closeX = rect.x + rect.w - Self.padding - Self.closeSize
            let closeY = rect.y + Self.padding
            let closeRect = (x: closeX, y: closeY, w: Self.closeSize, h: Self.closeSize)
            if hoveredId == summary.session.sessionId {
                // X 표시: 작은 사각형으로 대체
                surface.fillRect(x: closeX + 4, y: closeY + 7, w: 8, h: 2,
                                r: 180, g: 180, b: 180, a: 255)
            }

            hits.append(CardHit(summary: summary, rect: rect, closeRect: closeRect))
        }

        // 넘침 알약
        if overflowCount > 0 {
            let pillW = 80
            let pillH = overflowH
            let pillX = max(0, (surfaceWidth - pillW) / 2)
            let pillY = totalH - pillH
            surface.fillRoundedRect(x: pillX, y: pillY, w: pillW, h: pillH, radius: 9,
                                     r: 60, g: 60, b: 60, a: 200)
        }

        // hits 를 원래 순서로 되돌린다 (index 0 = 가장 급한 것)
        cardHits = hits.reversed()
        return (surface, totalH)
    }

    /// GDI DrawTextW 로 카드에 텍스트를 그린다.
    /// 카드 배경이 이미 불투명(alpha 0xFF)이므로 GDI 가 alpha 를 건드려도 보정할 수 있다.
    private func drawCardText(_ surface: inout PixelSurface, rect: (x: Int, y: Int, w: Int, h: Int),
                               title: String, detail: String) {
        let textX = rect.x + Self.padding + Self.dotSize + 9
        let textW = max(0, rect.x + rect.w - Self.padding - Self.closeSize - 8 - textX)
        guard textW > 0 else { return }

        // 제목 (13px, semibold)
        let titleY = rect.y + 8
        drawText(surface: &surface, text: title, x: textX, y: titleY, w: textW, h: 16,
                 fontSize: 13, bold: true)
        // 부제 (11px, regular)
        let detailY = titleY + 17
        drawText(surface: &surface, text: detail, x: textX, y: detailY, w: textW, h: 14,
                 fontSize: 11, bold: false)
    }

    /// GDI 로 한 줄 텍스트를 그린다. DIB 의 해당 영역에 쓰고 alpha 를 보정한다.
    private func drawText(surface: inout PixelSurface, text: String, x: Int, y: Int, w: Int, h: Int,
                           fontSize: Int, bold: Bool) {
        guard w > 0, h > 0 else { return }
        let screenDC = GetDC(nil)
        defer { ReleaseDC(nil, screenDC) }
        let memDC = CreateCompatibleDC(screenDC)
        defer { DeleteDC(memDC) }

        guard let (dib, bits) = Surface.createDIB(width: Int32(w), height: Int32(h), screenDC: screenDC) else { return }
        let old = SelectObject(memDC, dib)
        defer { SelectObject(memDC, old); DeleteObject(dib) }

        // 배경을 카드 색으로 채운다
        var bgRect = RECT(left: 0, top: 0, right: Int32(w), bottom: Int32(h))
        let bgBrush = CreateSolidBrush(COLORREF(UInt32(Self.bgR) | UInt32(Self.bgG) << 8 | UInt32(Self.bgB) << 16))
        FillRect(memDC, &bgRect, bgBrush)
        DeleteObject(bgBrush)

        // 폰트
        let weight: Int32 = bold ? FW_SEMIBOLD : FW_NORMAL
        let fontName = Array("Malgun Gothic".utf16) + [0]
        var font = fontName.withUnsafeBufferPointer { buf in
            CreateFontW(Int32(-fontSize), 0, 0, 0, weight, 0, 0, 0,
                       DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                       DWORD(ANTIALIASED_QUALITY), DWORD(DEFAULT_PITCH), buf.baseAddress)
        }
        if font == nil {
            let fallback = Array("Segoe UI".utf16) + [0]
            font = fallback.withUnsafeBufferPointer { buf in
                CreateFontW(Int32(-fontSize), 0, 0, 0, weight, 0, 0, 0,
                           DWORD(DEFAULT_CHARSET), DWORD(OUT_DEFAULT_PRECIS), DWORD(CLIP_DEFAULT_PRECIS),
                           DWORD(ANTIALIASED_QUALITY), DWORD(DEFAULT_PITCH), buf.baseAddress)
            }
        }
        let oldFont = SelectObject(memDC, font)
        defer { SelectObject(memDC, oldFont); if let font { DeleteObject(font) } }

        SetTextColor(memDC, COLORREF(UInt32(Self.textR) | UInt32(Self.textG) << 8 | UInt32(Self.textB) << 16))
        SetBkMode(memDC, Int32(TRANSPARENT))

        let wide = Array(text.utf16) + [0]
        var rc = RECT(left: 0, top: 0, right: Int32(w), bottom: Int32(h))
        wide.withUnsafeBufferPointer { buf in
            DrawTextW(memDC, buf.baseAddress, Int32(text.utf16.count), &rc,
                     UINT(DT_LEFT | DT_TOP | DT_SINGLELINE | DT_END_ELLIPSIS | DT_NOPREFIX))
        }

        // DIB 에서 읽어 surface 에 복사. GDI 가 alpha 를 0 으로 남기므로 0xFF 로 보정한다.
        let stride = w * 4
        for row in 0..<h {
            let srcRow = row * stride
            let dstY = y + row
            guard dstY >= 0, dstY < surface.height else { continue }
            for col in 0..<w {
                let si = srcRow + col * 4
                let dstX = x + col
                guard dstX >= 0, dstX < surface.width else { continue }
                let di = (dstY * surface.width + dstX) * 4
                // GDI 는 BGR 순서, alpha 는 0. surface 도 BGRA.
                // 카드 배경과 같은 픽셀은 건드리지 않는다 (이미 fillRoundedRect 가 그렸다).
                let bitsB = bits[si + 0], bitsG = bits[si + 1], bitsR = bits[si + 2]
                if bitsR != Self.bgR || bitsG != Self.bgG || bitsB != Self.bgB {
                    // 텍스트 픽셀이다. 불투명으로 덮어쓴다.
                    surface.pixels[di + 0] = bitsB
                    surface.pixels[di + 1] = bitsG
                    surface.pixels[di + 2] = bitsR
                    surface.pixels[di + 3] = 0xFF
                }
            }
        }
    }

    /// 말풍선 전체 높이.
    func totalHeight(for aggregate: Aggregate, surfaceWidth: Int) -> Int {
        let sel = BubbleSelection.choose(
            sessions: aggregate.sessions, isExpanded: isExpanded, isBubbleHidden: isBubbleHidden,
            maxCards: maxCards, closed: closed)
        guard !sel.shown.isEmpty else { return 0 }
        var h = sel.shown.count * Self.cardHeight + max(0, sel.shown.count - 1) * Self.spacing
        if sel.hiddenCount > 0 { h += Self.spacing + 18 }
        return h
    }

    private func stateColor(_ state: PetState) -> (r: UInt8, g: UInt8, b: UInt8) {
        switch state {
        case .idle:    return (128, 128, 128)
        case .running: return (50, 130, 246)
        case .waiting: return (255, 159, 10)
        case .failed:  return (255, 59, 48)
        case .review:  return (52, 199, 89)
        }
    }
}
#endif
