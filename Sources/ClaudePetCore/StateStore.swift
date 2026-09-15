import Foundation

public struct StateStore: Sendable {
    public let directory: URL

    public init(directory: URL) { self.directory = directory }

    /// 디렉터리의 *.json 을 모두 읽는다. 깨진 파일은 건너뛴다. 디렉터리가 없으면 빈 배열.
    public func loadAll() -> [SessionState] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return [] }
        let decoder = JSONDecoder()
        return names.compactMap { name in
            guard name.hasSuffix(".json") else { return nil }
            guard let data = fm.contents(atPath: directory.appendingPathComponent(name).path) else { return nil }
            return try? decoder.decode(SessionState.self, from: data)
        }
    }

    /// ts 가 `olderThan` 초보다 오래된 파일을 지운다. 파싱 안 되는 파일은 건드리지 않는다.
    public func removeStale(olderThan maxAge: TimeInterval, now: Date) {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: directory.path) else { return }
        let decoder = JSONDecoder()
        for name in names where name.hasSuffix(".json") {
            let url = directory.appendingPathComponent(name)
            guard let data = fm.contents(atPath: url.path),
                  let s = try? decoder.decode(SessionState.self, from: data) else { continue }
            if now.timeIntervalSince(s.timestamp) > maxAge {
                try? fm.removeItem(at: url)
            }
        }
    }
}
