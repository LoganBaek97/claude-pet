import Foundation

public struct PetManifest: Codable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let spritesheetPath: String

    public init(id: String, displayName: String, description: String, spritesheetPath: String) {
        self.id = id; self.displayName = displayName; self.description = description; self.spritesheetPath = spritesheetPath
    }
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
