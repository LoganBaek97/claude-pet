import Foundation

/// 세션 카드를 선택하는 순수 규칙. macOS BubbleStackView 와 Windows BubbleRenderer 가 공유한다.
public enum BubbleSelection {
    /// 접었을 때 겹쳐 쌓는 최대 장수.
    public static let collapsedLimit = 3
    /// 펼쳤을 때 보여 주는 최대 장수.
    public static let expandedLimit = 8

    public struct Result: Equatable, Sendable {
        public let shown: [SessionSummary]
        public let hiddenCount: Int

        public init(shown: [SessionSummary], hiddenCount: Int) {
            self.shown = shown; self.hiddenCount = hiddenCount
        }
    }

    /// 말풍선에 올릴 세션을 고른다.
    ///
    /// - Parameters:
    ///   - sessions: 합성의 모든 세션 (급한 순서, 같으면 최신순).
    ///   - isExpanded: 마우스가 올라가 있으면 유휴까지 펼친다.
    ///   - isBubbleHidden: 말풍선을 아예 안 띄우는 모드.
    ///   - maxCards: 화면에 들어갈 수 있는 장수 상한.
    ///   - closed: 사용자가 닫은 세션 id -> 닫았을 때의 상태. 그 상태가 이어지는 동안만 감춘다.
    public static func choose(
        sessions: [SessionSummary],
        isExpanded: Bool,
        isBubbleHidden: Bool,
        maxCards: Int,
        closed: [String: PetState]
    ) -> Result {
        guard !isBubbleHidden else { return Result(shown: [], hiddenCount: 0) }
        let live = sessions.filter { closed[$0.session.sessionId] != $0.state }
        let pool = isExpanded ? live : live.filter { $0.state != .idle }
        let limit = min(isExpanded ? expandedLimit : collapsedLimit, max(maxCards, 1))
        let shown = Array(pool.prefix(limit))
        // 접었을 때 감춘 유휴 세션도 세어 준다. 호버하면 볼 수 있다는 힌트가 된다.
        // 사용자가 닫은 것은 세지 않는다.
        return Result(shown: shown, hiddenCount: live.count - shown.count)
    }
}
