import AppKit
import ClaudePetCore

/// 강조 단계별 글자색·테두리색. 배경은 어두운 채로 두고 색은 글자와 테두리에만 쓴다.
/// 어두운 배경 위에서 읽히도록 밝은 쪽 색을 고정으로 쓴다(시스템 색은 외형에 따라 어두워질 수 있다).
private extension BubbleEmphasis {
    var foreground: NSColor {
        switch self {
        case .none: return .white
        case .question: return NSColor(red: 1.0, green: 0.65, blue: 0.15, alpha: 1)
        case .failure: return NSColor(red: 1.0, green: 0.36, blue: 0.31, alpha: 1)
        }
    }

    var borderWidth: CGFloat { self == .none ? 0 : 1.5 }
}

/// 펫 위에 붙는 캡슐형 라벨. 텍스트가 바뀔 때만 다시 그린다.
/// 펫 애니메이션이 몇 초 뒤 idle 로 가라앉으므로 지속 상태는 이 텍스트가 나른다. 그래서 running 중에도 흐리게 하지 않는다.
final class SpeechBubbleView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var currentText: String?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 9
        layer?.backgroundColor = NSColor(white: 0.1, alpha: 0.85).cgColor
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        addSubview(label)
        isHidden = true
    }
    required init?(coder: NSCoder) { fatalError() }

    /// 반환값: 새 크기(숨김이면 .zero). 호출자가 패널 크기를 맞춘다.
    /// 강조(waiting/failed)는 단계별 색으로 글자와 테두리를 칠한다.
    @discardableResult
    func update(text: String?, emphasis: BubbleEmphasis, maxWidth: CGFloat) -> NSSize {
        guard let text, !text.isEmpty else {
            isHidden = true; currentText = nil; return .zero
        }
        let textChanged = text != currentText
        if textChanged {
            currentText = text
            label.stringValue = text
            label.sizeToFit()
            let w = min(label.frame.width + 16, maxWidth)
            frame.size = NSSize(width: w, height: 20)
            label.frame = NSRect(x: 8, y: 3, width: w - 16, height: 14)
        }
        isHidden = false
        let emphasized = emphasis.isEmphasized
        // 배경은 늘 어둡게 둔다. 색은 글자와 테두리로만 준다.
        layer?.backgroundColor = NSColor(white: 0.1, alpha: emphasized ? 0.92 : 0.85).cgColor
        layer?.borderColor = emphasis.foreground.withAlphaComponent(0.9).cgColor
        layer?.borderWidth = emphasis.borderWidth
        label.textColor = emphasis.foreground
        return frame.size
    }
}
