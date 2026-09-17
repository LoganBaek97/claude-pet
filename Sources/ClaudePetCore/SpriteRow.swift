import Foundation

/// Codex 시트의 표준 행 순서. rawValue 가 행 번호(0 이 맨 위). v1 은 이 아홉 행이 전부고 v2 는 뒤에 look 두 행이 더 있다.
public enum SpriteRow: Int, CaseIterable, Sendable {
    case idle = 0, runningRight, runningLeft, waving, jumping, failed, waiting, running, review

    public var nominalFrameCount: Int {
        switch self {
        case .idle: return 6
        case .runningRight, .runningLeft: return 8
        case .waving: return 4
        case .jumping: return 5
        case .failed: return 8
        case .waiting: return 6
        case .running: return 6
        case .review: return 6
        }
    }

    /// Codex 런타임의 프레임 길이(ms). 마지막 프레임을 길게 잡아 멈칫하는 리듬을 만든다. idle 은 프레임마다 다르다.
    var normalFrameMs: Int {
        switch self {
        case .idle: return 140
        case .runningRight, .runningLeft, .running: return 120
        case .waving, .jumping, .failed: return 140
        case .waiting, .review: return 150
        }
    }

    var lastFrameMs: Int {
        switch self {
        case .idle: return 320
        case .runningRight, .runningLeft, .running: return 220
        case .waving, .jumping, .review: return 280
        case .failed: return 240
        case .waiting: return 260
        }
    }

    /// idle 의 마지막 앞 프레임들. 한 사이클 280+110+110+140+140+320 = 1100ms.
    static let idleLeadFrameMs = [280, 110, 110, 140, 140]

    /// 실제 시트의 프레임 수(`count`)에서 `index` 번째 프레임을 보여줄 시간. 시트가 공칭보다 짧거나 길어도 마지막 프레임이 긴 규칙은 유지한다.
    public func frameDurationMs(index: Int, of count: Int) -> Int {
        if index >= count - 1 { return lastFrameMs }
        if self == .idle { return Self.idleLeadFrameMs[min(index, Self.idleLeadFrameMs.count - 1)] }
        return normalFrameMs
    }

    public static func base(for state: PetState) -> SpriteRow {
        switch state {
        case .idle: return .idle
        case .running: return .running
        case .waiting: return .waiting
        case .failed: return .failed
        case .review: return .review
        }
    }
}
