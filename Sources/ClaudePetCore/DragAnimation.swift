import Foundation

/// 펫을 끌고 다니는 동안 어떤 동작을 보여 줄지 고른다.
///
/// 누적 이동량이 아니라 방금 움직인 양을 넣는다. 오른쪽으로 끌고 갔다가 왼쪽으로 돌아오면
/// 펫도 따라 돌아서야 하는데, 시작점부터의 거리로는 그걸 알 수 없다.
public enum DragAnimation {
    /// 이만큼도 안 움직였으면 손이 멈춘 것으로 본다. 화면 좌표 기준.
    public static let threshold: Double = 1.0

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
