#if os(Windows)
import ClaudePetCore
import Foundation

/// 상태 디렉터리를 1초마다 폴링한다. DispatchSource 없이 SetTimer 로 구동한다.
final class StateWatcher {
    private let store: StateStore
    private let onChange: (Aggregate) -> Void
    private let probe = ProcessProbe()
    private var last: Aggregate?
    private var refreshCount = 0

    init(store: StateStore, onChange: @escaping (Aggregate) -> Void) {
        self.store = store
        self.onChange = onChange
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
    }

    /// App 의 1초 타이머가 부른다.
    func refresh(force: Bool = false) {
        let now = Date()
        refreshCount += 1
        if refreshCount % 60 == 0 {
            store.removeStale(olderThan: StateAggregator.deleteAfter, now: now)
        }
        let agg = StateAggregator.aggregate(store.loadAll(), now: now, liveness: probe.liveness(of:))
        if force || agg != last {
            last = agg
            onChange(agg)
        }
    }
}
#endif
