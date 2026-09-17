import Foundation

public struct AnimationFrame: Equatable, Sendable {
    public let row: SpriteRow
    public let index: Int
    public init(row: SpriteRow, index: Int) { self.row = row; self.index = index }
}

/// 합성 상태와 일회성 연출을 시트 행과 프레임 번호로 바꾼다. 타이머는 모른다. 프레임마다 `currentDurationMs` 를 돌려주고
/// 호출자가 그 시간 뒤에 `advance()` 를 부른다. 스레드 안전하지 않다. 메인 스레드에서만 쓴다.
///
/// 재생 규칙은 Codex 와 같다. 비-idle 상태의 행은 `burstPlays` 회 재생한 뒤 느린 idle 로 가라앉아 거기서 무한 루프하고,
/// idle 상태는 처음부터 느린 idle 을 돈다. 지속 상태는 말풍선 텍스트가 나르고 애니메이션은 "무언가 일어났다"는 짧은 신호다.
public final class AnimationDirector {
    public static let burstPlays = 3
    /// 가라앉은 idle 은 원속도의 1/6 로 돈다(Codex `Ylo`). 한 사이클 6.6초.
    public static let settledIdleSlowdown = 6
    /// running 상태에서 이 시간마다 `walkProbability` 로 좌우 산책을 한 사이클 끼운다. claude-pet 고유 연출.
    public static let walkEveryMs = 20_000
    public static let walkProbability = 0.3

    private let frameCounts: [SpriteRow: Int]
    private let random: () -> Double
    private var state: PetState = .idle
    private var baseRow: SpriteRow = .idle
    private var oneShots: [SpriteRow] = []
    private var index = 0
    private var playsDone = 0
    private var msSinceWalkCheck = 0

    /// 시스템 감속 모션. 켜면 상태 행의 첫 프레임 한 장만 보이고 넘어가지 않는다. 일회성 연출도 받지 않는다.
    public var reducedMotion = false {
        didSet { if reducedMotion { oneShots = []; index = 0 } }
    }

    public init(frameCounts: [SpriteRow: Int], random: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.frameCounts = frameCounts
        self.random = random
    }

    public var current: AnimationFrame { AnimationFrame(row: activeRow, index: index) }

    /// 지금 프레임을 보여줄 시간. 가라앉은 idle 만 느리게, 일회성 연출과 버스트는 원속도로.
    public var currentDurationMs: Int {
        let row = activeRow
        let ms = row.frameDurationMs(index: index, of: count(row))
        return oneShots.isEmpty && isSettled ? ms * Self.settledIdleSlowdown : ms
    }

    private var isSettled: Bool { state == .idle || playsDone >= Self.burstPlays }

    private var activeRow: SpriteRow {
        if reducedMotion { return baseRow }
        return oneShots.first ?? (isSettled ? .idle : baseRow)
    }

    private func count(_ row: SpriteRow) -> Int { max(1, frameCounts[row] ?? 1) }

    public func setState(_ newState: PetState) {
        guard newState != state else { return }
        let previous = state
        state = newState
        baseRow = SpriteRow.base(for: newState)
        playsDone = 0
        msSinceWalkCheck = 0
        if reducedMotion { index = 0; return }
        if previous == .waiting && newState == .running {
            playOnce(.jumping)
        } else if oneShots.isEmpty {
            index = 0
        }
    }

    public func playOnce(_ row: SpriteRow) {
        guard !reducedMotion else { return }
        let wasIdle = oneShots.isEmpty
        oneShots.append(row)
        if wasIdle { index = 0 }
    }

    public func advance() -> AnimationFrame {
        guard !reducedMotion else { return current }
        msSinceWalkCheck += currentDurationMs
        let row = activeRow
        let next = index + 1
        if next < count(row) {
            index = next
        } else if !oneShots.isEmpty {
            oneShots.removeFirst()
            index = 0
        } else {
            index = 0
            if !isSettled { playsDone += 1 } // 마지막 재생이 끝나면 activeRow 가 idle 로 넘어간다
        }
        maybeQueueWalk()
        return current
    }

    private func maybeQueueWalk() {
        guard state == .running, oneShots.isEmpty else { return }
        guard msSinceWalkCheck >= Self.walkEveryMs else { return }
        msSinceWalkCheck = 0
        guard random() < Self.walkProbability else { return }
        playOnce(random() < 0.5 ? .runningRight : .runningLeft)
    }
}
