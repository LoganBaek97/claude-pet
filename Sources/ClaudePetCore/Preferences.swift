import Foundation

public final class Preferences: @unchecked Sendable {
    public static let suiteName = "dev.logan.claude-pet.shared"
    public static let changedNotification = Notification.Name("dev.logan.claude-pet.preferencesChanged")
    public static let allowedScales: [Double] = [0.35, 0.5, 1.0]
    public static let shared = Preferences(defaults: UserDefaults(suiteName: suiteName)!)

    private let d: UserDefaults
    public init(defaults: UserDefaults) { d = defaults }

    public var selectedPetId: String? {
        get { d.string(forKey: "selectedPetId") }
        set { d.set(newValue, forKey: "selectedPetId") }
    }

    public var scale: Double {
        get {
            let v = d.object(forKey: "scale") as? Double ?? 0.5
            return Self.allowedScales.contains(v) ? v : 0.5
        }
        set { d.set(Self.allowedScales.contains(newValue) ? newValue : 0.5, forKey: "scale") }
    }

    public var isHidden: Bool {
        get { d.bool(forKey: "isHidden") }
        set { d.set(newValue, forKey: "isHidden") }
    }

    /// 말풍선을 아예 띄우지 않는다. 펫은 그대로 두고 글자만 없애고 싶을 때 쓴다.
    public var isBubbleHidden: Bool {
        get { d.bool(forKey: "isBubbleHidden") }
        set { d.set(newValue, forKey: "isBubbleHidden") }
    }

    public var position: CGPoint? {
        get {
            guard let x = d.object(forKey: "positionX") as? Double, let y = d.object(forKey: "positionY") as? Double else { return nil }
            return CGPoint(x: x, y: y)
        }
        set {
            if let p = newValue { d.set(p.x, forKey: "positionX"); d.set(p.y, forKey: "positionY") }
            else { d.removeObject(forKey: "positionX"); d.removeObject(forKey: "positionY") }
        }
    }

    /// CLI 가 값을 바꾼 뒤 실행 중인 앱에 알린다.
    public func postChanged() {
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
