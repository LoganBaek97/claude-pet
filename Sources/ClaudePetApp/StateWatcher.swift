import ClaudePetCore
import Foundation

/// 상태 디렉터리를 DispatchSource 로 감시하고 1초 폴링을 백업으로 둔다. 콜백은 메인 스레드.
final class StateWatcher {
    private let store: StateStore
    private let onChange: (Aggregate) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var timer: Timer?
    private var last: Aggregate?
    private var refreshCount = 0

    init(store: StateStore, onChange: @escaping (Aggregate) -> Void) {
        self.store = store
        self.onChange = onChange
    }

    func start() {
        try? FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        fd = open(store.directory.path, O_EVTONLY)
        if fd >= 0 {
            let s = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend, .attrib], queue: .main)
            s.setEventHandler { [weak self] in self?.refresh() }
            s.setCancelHandler { [fd = self.fd] in close(fd) }
            s.resume()
            source = s
        }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer!, forMode: .common)
        refresh(force: true)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        source?.cancel(); source = nil
    }

    func refresh(force: Bool = false) {
        let now = Date()
        refreshCount += 1
        if refreshCount % 60 == 0 { store.removeStale(olderThan: StateAggregator.deleteAfter, now: now) }
        let agg = StateAggregator.aggregate(store.loadAll(), now: now)
        if force || agg != last {
            last = agg
            onChange(agg)
        }
    }
}
