import AppKit

/// 펫 위에 붙는 캡슐형 라벨. 텍스트가 바뀔 때만 다시 그리고, running 은 3초 뒤 흐려진다.
final class SpeechBubbleView: NSView {
    private let label = NSTextField(labelWithString: "")
    private var dimTimer: Timer?
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
    /// F-8: 텍스트가 실제로 바뀔 때만 dimTimer 를 재시작한다(훅 이벤트마다 같은 텍스트로 다시 불려도 카운트다운이 리셋되지 않게).
    /// emphasized(waiting/failed) 는 항상 alpha 1 을 유지한다.
    @discardableResult
    func update(text: String?, emphasized: Bool, maxWidth: CGFloat) -> NSSize {
        guard let text, !text.isEmpty else {
            dimTimer?.invalidate(); dimTimer = nil
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
        layer?.backgroundColor = (emphasized ? NSColor(red: 0.85, green: 0.3, blue: 0.25, alpha: 0.92)
                                             : NSColor(white: 0.1, alpha: 0.85)).cgColor
        if emphasized {
            dimTimer?.invalidate(); dimTimer = nil
            alphaValue = 1
        } else if textChanged {
            dimTimer?.invalidate()
            alphaValue = 1
            dimTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                self?.animator().alphaValue = 0.5
            }
        }
        return frame.size
    }
}
