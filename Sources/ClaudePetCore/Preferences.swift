import Foundation

public final class Preferences: @unchecked Sendable {
    public static let suiteName = "dev.logan.claude-pet.shared"
    public static let changedNotification = Notification.Name("dev.logan.claude-pet.preferencesChanged")
    public static let allowedScales: [Double] = [0.35, 0.5, 1.0]

    #if os(Windows)
    public static let shared = Preferences(store: FilePreferencesStore(
        url: Paths.applicationSupport.appendingPathComponent("preferences.json")
    ))
    #else
    public static let shared = Preferences(defaults: UserDefaults(suiteName: suiteName)!)
    #endif

    private let store: PreferencesStore
    public init(store: PreferencesStore) { self.store = store }

    #if canImport(Darwin)
    public convenience init(defaults: UserDefaults) { self.init(store: defaults) }
    #endif

    public var selectedPetId: String? {
        get { store.stringValue(forKey: "selectedPetId") }
        set { store.set(newValue, forKey: "selectedPetId") }
    }

    public var scale: Double {
        get {
            let v = store.doubleValue(forKey: "scale") ?? 0.5
            return Self.allowedScales.contains(v) ? v : 0.5
        }
        set { store.set(Self.allowedScales.contains(newValue) ? newValue : 0.5, forKey: "scale") }
    }

    public var isHidden: Bool {
        get { store.boolValue(forKey: "isHidden") }
        set { store.set(newValue, forKey: "isHidden") }
    }

    /// 말풍선을 아예 띄우지 않는다. 펫은 그대로 두고 글자만 없애고 싶을 때 쓴다.
    public var isBubbleHidden: Bool {
        get { store.boolValue(forKey: "isBubbleHidden") }
        set { store.set(newValue, forKey: "isBubbleHidden") }
    }

    /// 시스템 "동작 줄이기" 를 무시하고 펫을 계속 움직인다.
    ///
    /// 그 설정은 멀미나 전정기관 문제로 켜는 사람이 있어서 기본은 존중한다.
    /// 다만 그 설정을 켜 둔 채로 펫만은 움직이길 바라는 사람도 있어서, 본인이 직접 켤 수 있게 둔다.
    /// 앱이 마음대로 무시하지는 않는다.
    public var ignoresReducedMotion: Bool {
        get { store.boolValue(forKey: "ignoresReducedMotion") }
        set { store.set(newValue, forKey: "ignoresReducedMotion") }
    }

    public var position: CGPoint? {
        get {
            guard let x = store.doubleValue(forKey: "positionX"),
                  let y = store.doubleValue(forKey: "positionY") else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let p = newValue {
                store.set(Double(p.x), forKey: "positionX")
                store.set(Double(p.y), forKey: "positionY")
            } else {
                store.set(nil, forKey: "positionX")
                store.set(nil, forKey: "positionY")
            }
        }
    }

    // MARK: - 변경 알림

    /// Windows 폴링용: 이 파일의 mtime 이 바뀌면 설정이 바뀐 것이다.
    public static var changeSignalFile: URL {
        Paths.applicationSupport.appendingPathComponent("prefs-changed")
    }

    /// 변경 신호 파일의 마지막 수정 시각(초). 없으면 nil.
    public func changeSignalTimestamp() -> TimeInterval? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: Self.changeSignalFile.path),
              let date = attrs[.modificationDate] as? Date else { return nil }
        return date.timeIntervalSince1970
    }

    /// CLI 가 값을 바꾼 뒤 실행 중인 앱에 알린다.
    public func postChanged() {
        #if os(macOS)
        DistributedNotificationCenter.default().postNotificationName(
            Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true
        )
        #else
        let signalFile = Self.changeSignalFile
        let dir = signalFile.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let timestamp = String(Date().timeIntervalSince1970)
        try? timestamp.write(to: signalFile, atomically: true, encoding: .utf8)
        #endif
    }
}
