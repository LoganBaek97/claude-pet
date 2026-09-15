import Foundation

public struct AnimationFrame: Equatable, Sendable {
    public let row: SpriteRow
    public let index: Int
    public init(row: SpriteRow, index: Int) { self.row = row; self.index = index }
}

/// 합성 상태와 일회성 연출을 시트 행과 프레임 번호로 바꾼다. 스레드 안전하지 않다. 메인 스레드에서만 쓴다.
public final class AnimationDirector {
    public static let fps = 10
    public static let walkEveryTicks = 200
    public static let walkProbability = 0.3

    private let frameCounts: [SpriteRow: Int]
    private let random: () -> Double
    private var state: PetState = .idle
    private var baseRow: SpriteRow = .idle
    private var oneShots: [SpriteRow] = []
    private var index = 0
    private var ticksSinceWalkCheck = 0

    public init(frameCounts: [SpriteRow: Int], random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.frameCounts = frameCounts
        self.random = random
    }

    public var current: AnimationFrame { AnimationFrame(row: activeRow, index: index) }

    private var activeRow: SpriteRow { oneShots.first ?? baseRow }

    private func count(_ row: SpriteRow) -> Int { max(1, frameCounts[row] ?? 1) }

    public func setState(_ newState: PetState) {
        guard newState != state else { return }
        let previous = state
        state = newState
        baseRow = SpriteRow.base(for: newState)
        ticksSinceWalkCheck = 0
        if previous == .waiting && newState == .running {
            playOnce(.jumping)
        } else if oneShots.isEmpty {
            index = 0
        }
    }

    public func playOnce(_ row: SpriteRow) {
        let wasIdle = oneShots.isEmpty
        oneShots.append(row)
        if wasIdle { index = 0 }
    }

    public func advance() -> AnimationFrame {
        let row = activeRow
        let next = index + 1
        if next < count(row) {
            index = next
        } else if !oneShots.isEmpty {
            oneShots.removeFirst()
            index = 0
        } else {
            index = 0
        }
        maybeQueueWalk()
        return current
    }

    private func maybeQueueWalk() {
        guard state == .running, oneShots.isEmpty, activeRow == .running else { return }
        ticksSinceWalkCheck += 1
        guard ticksSinceWalkCheck >= Self.walkEveryTicks else { return }
        ticksSinceWalkCheck = 0
        guard random() < Self.walkProbability else { return }
        playOnce(random() < 0.5 ? .runningRight : .runningLeft)
    }
}
