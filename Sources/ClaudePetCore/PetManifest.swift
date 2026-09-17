import Foundation

public struct PetManifest: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let spritesheetPath: String
    /// Codex 계약의 판별자. 생략하면 v1 이다. 시트 높이가 아니라 이 값으로 행 수를 정한다.
    public let spriteVersionNumber: Int?

    public init(id: String, displayName: String, description: String, spritesheetPath: String, spriteVersionNumber: Int? = nil) {
        self.id = id; self.displayName = displayName; self.description = description; self.spritesheetPath = spritesheetPath
        self.spriteVersionNumber = spriteVersionNumber
    }

    public var spriteVersion: Int { spriteVersionNumber ?? 1 }
}

public enum PetSource: String, Sendable { case user, codex, builtin }

public struct InstalledPet: Equatable, Sendable {
    public let manifest: PetManifest
    public let directory: URL
    public let source: PetSource

    public init(manifest: PetManifest, directory: URL, source: PetSource) {
        self.manifest = manifest; self.directory = directory; self.source = source
    }

    public var id: String { manifest.id }
    public var spritesheetURL: URL { directory.appendingPathComponent(manifest.spritesheetPath) }
}
