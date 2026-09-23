import Foundation

// MARK: - Protocol

/// 설정값을 읽고 쓰는 저장소 추상화.
/// 메서드 이름에 `Value` 를 붙여 `UserDefaults` 의 기존 메서드와 충돌을 피한다.
public protocol PreferencesStore: AnyObject {
    func stringValue(forKey key: String) -> String?
    /// 키가 없으면 nil 을 반환한다.
    func doubleValue(forKey key: String) -> Double?
    func boolValue(forKey key: String) -> Bool
    /// value 가 nil 이면 해당 키를 제거한다.
    func set(_ value: Any?, forKey key: String)
}

// MARK: - MemoryPreferencesStore

/// 메모리에만 저장. 테스트 전용.
public final class MemoryPreferencesStore: PreferencesStore {
    private var storage: [String: Any] = [:]

    public init() {}

    public func stringValue(forKey key: String) -> String? { storage[key] as? String }
    public func doubleValue(forKey key: String) -> Double? { storage[key] as? Double }
    public func boolValue(forKey key: String) -> Bool { storage[key] as? Bool ?? false }

    public func set(_ value: Any?, forKey key: String) {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }
}

// MARK: - FilePreferencesStore

/// JSON 파일 하나에 저장. Windows 기본.
/// 원자적 쓰기(임시 파일 후 교체).
/// 읽기는 매 접근마다 파일 mtime 을 보고 바뀌었으면 다시 읽는다(CLI 가 바꾼 값을 앱이 보게).
public final class FilePreferencesStore: PreferencesStore {

    // 타입별로 나눠 저장해 JSON 숫자와 불리언 간 모호성을 없앤다.
    private struct StorageFormat: Codable {
        var strings: [String: String] = [:]
        var doubles: [String: Double] = [:]
        var bools: [String: Bool] = [:]
    }

    private let url: URL
    private var data: StorageFormat = .init()
    private var lastMtime: TimeInterval = 0
    private let lock = NSLock()

    public init(url: URL) {
        self.url = url
        reloadLocked()
    }

    // MARK: PreferencesStore

    public func stringValue(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        refreshIfNeeded()
        return data.strings[key]
    }

    public func doubleValue(forKey key: String) -> Double? {
        lock.lock(); defer { lock.unlock() }
        refreshIfNeeded()
        return data.doubles[key]
    }

    public func boolValue(forKey key: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        refreshIfNeeded()
        return data.bools[key] ?? false
    }

    public func set(_ value: Any?, forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        refreshIfNeeded()
        clearKey(key)
        if let v = value as? String { data.strings[key] = v }
        else if let v = value as? Bool { data.bools[key] = v }
        else if let v = value as? Double { data.doubles[key] = v }
        saveLocked()
    }

    // MARK: Private

    private func clearKey(_ key: String) {
        data.strings.removeValue(forKey: key)
        data.doubles.removeValue(forKey: key)
        data.bools.removeValue(forKey: key)
    }

    private func currentMtime() -> TimeInterval {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[.modificationDate] as? Date else { return 0 }
        return date.timeIntervalSince1970
    }

    private func refreshIfNeeded() {
        let m = currentMtime()
        if m != lastMtime { reloadLocked() }
    }

    private func reloadLocked() {
        guard FileManager.default.fileExists(atPath: url.path),
              let raw = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StorageFormat.self, from: raw)
        else {
            data = .init()
            lastMtime = currentMtime()
            return
        }
        data = decoded
        lastMtime = currentMtime()
    }

    private func saveLocked() {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        let tmp = url.appendingPathExtension("tmp")
        do {
            try encoded.write(to: tmp)
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            try? FileManager.default.removeItem(at: tmp)
        }
        lastMtime = currentMtime()
    }
}

// MARK: - UserDefaults conformance

#if canImport(Darwin)
extension UserDefaults: PreferencesStore {
    public func stringValue(forKey key: String) -> String? { string(forKey: key) }
    public func doubleValue(forKey key: String) -> Double? {
        guard object(forKey: key) != nil else { return nil }
        return double(forKey: key)
    }
    public func boolValue(forKey key: String) -> Bool { bool(forKey: key) }
}
#endif
