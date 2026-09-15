import Foundation

public enum Paths {
    public static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    public static var applicationSupport: URL {
        home.appendingPathComponent("Library/Application Support/ClaudePet", isDirectory: true)
    }

    public static var stateDirectory: URL {
        stateDirectory(environment: ProcessInfo.processInfo.environment)
    }

    public static func stateDirectory(environment: [String: String]) -> URL {
        if let override = environment["CLAUDE_PET_STATE_DIR"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return applicationSupport.appendingPathComponent("state", isDirectory: true)
    }

    public static var petsDirectory: URL {
        applicationSupport.appendingPathComponent("pets", isDirectory: true)
    }

    public static var codexPetsDirectory: URL {
        home.appendingPathComponent(".codex/pets", isDirectory: true)
    }

    public static var claudeSettingsFile: URL {
        home.appendingPathComponent(".claude/settings.json")
    }
}
