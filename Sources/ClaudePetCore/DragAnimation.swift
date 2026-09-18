import Foundation

/// 펫을 끌고 다니는 동안 어떤 동작을 보여 줄지 고른다.
///
/// 누적 이동량이 아니라 방금 움직인 양을 넣는다. 오른쪽으로 끌고 갔다가 왼쪽으로 돌아오면
/// 펫도 따라 돌아서야 하는데, 시작점부터의 거리로는 그걸 알 수 없다.
public enum DragAnimation {
    /// 방향을 정하려면 이만큼은 움직여야 한다. 화면 좌표 기준.
    /// 너무 작으면 제자리 떨림에도 펫이 좌우로 홱홱 돌아선다.
    public static let threshold: Double = 2.0

    /// 방금 움직인 양으로 보여 줄 행을 고른다. 손이 멈췄으면 nil(평소 상태로 돌아가라는 뜻).
    ///
    /// 세로로 더 움직이면 위든 아래든 점프다. 시트에 떨어지는 행이 없어서
    /// 공중에 떠 있는 느낌 하나로 모은다.
    public static func row(dx: Double, dy: Double, threshold: Double = threshold) -> SpriteRow? {
        guard abs(dx) >= threshold || abs(dy) >= threshold else { return nil }
        guard abs(dx) >= abs(dy) else { return .jumping }
        return dx > 0 ? .runningRight : .runningLeft
    }
}


/// 느리게 끌 때도 애니메이션이 끊기지 않도록 움직임을 모아 방향을 정한다.
///
/// 이벤트 하나하나로 판단하면 천천히 끄는 동안 이동량이 문턱값에 못 미쳐 매번 "멈춤" 이 되고,
/// 달리기가 내려갔다 올라오기를 반복해 끊겨 보인다. 그래서 넘을 때까지 모은다.
/// 모으는 값은 방향이 정해질 때마다 비우므로 앞뒤로 흔들면 서로 지워진다.
///
/// 손이 정말 멈춘 것은 이쪽이 알 수 없다. 이벤트가 아예 오지 않기 때문이다.
/// 그건 호출자가 시간으로 재고 `reset()` 을 부른다.
public struct DragTracker {
    /// 축을 갈아타려면 다른 축보다 이만큼은 더 움직여야 한다.
    /// 45도 근처에서 달리기와 점프가 번갈아 뜨는 것을 막는다. 좌우를 뒤집는 데는 쓰지 않는다.
    /// 돌아서는 것은 바로바로 따라가야 한다.
    public static let axisStickiness: Double = 1.5

    private var dx: Double = 0
    private var dy: Double = 0
    private var last: SpriteRow?

    public init() {}

    /// 방금 움직인 양을 넣는다. 방향이 정해지면 그 행을, 아직 모자라면 nil 을 돌려준다.
    /// 여기서 nil 은 "멈췄다" 가 아니라 "아직 모르겠으니 보여 주던 것을 그대로 두라" 는 뜻이다.
    public mutating func accumulate(dx deltaX: Double, dy deltaY: Double) -> SpriteRow? {
        dx += deltaX
        dy += deltaY
        let h = abs(dx), v = abs(dy)
        guard h >= DragAnimation.threshold || v >= DragAnimation.threshold else { return nil }

        let horizontal: Bool
        switch last {
        case .jumping:
            horizontal = h >= v * Self.axisStickiness
        case .runningLeft, .runningRight:
            horizontal = !(v >= h * Self.axisStickiness)
        default:
            horizontal = h >= v
        }
        let row: SpriteRow = horizontal ? (dx > 0 ? .runningRight : .runningLeft) : .jumping

        dx = 0
        dy = 0
        last = row
        return row
    }

    /// 드래그가 끝났거나 손이 멈췄다. 다음 드래그는 처음부터 판단한다.
    public mutating func reset() {
        dx = 0
        dy = 0
        last = nil
    }
}
