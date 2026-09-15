import Foundation

/// Codex v1 시트의 행 순서. rawValue 가 행 번호(0 이 맨 위).
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
