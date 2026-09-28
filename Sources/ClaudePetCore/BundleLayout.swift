import Foundation

/// 실행 파일 위치로 리소스 경로를 찾는다. .app 안이면 Contents/Resources, 아니면 저장소 레이아웃(.build/<config>/ 기준 두 단계 위).
public enum BundleLayout {
    public static func appBundle(containing executable: URL) -> URL? {
        let parts = executable.standardizedFileURL.pathComponents
        guard let i = parts.lastIndex(where: { $0.hasSuffix(".app") }),
              parts.count > i + 2, parts[i + 1] == "Contents", parts[i + 2] == "MacOS" else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: Array(parts[0...i])), isDirectory: true)
    }

    static func resources(executable: URL) -> URL {
        if let app = appBundle(containing: executable) {
            return app.appendingPathComponent("Contents/Resources", isDirectory: true)
        }
        // 심링크를 따라가지 않고 어휘적으로 두 단계 올라간다.
        // SwiftPM 의 .build/debug 는 .build/<triple>/debug 를 가리키는 심링크라
        // standardizedFileURL 로 정규화하면 저장소 루트 대신 .build 로 떨어진다.
        return executable.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    public static func hookScript(executable: URL) -> URL {
        if appBundle(containing: executable) != nil {
            return resources(executable: executable).appendingPathComponent("hook.sh")
        }
        return resources(executable: executable).appendingPathComponent("hooks/hook.sh")
    }

    /// Windows 배포 레이아웃: <root>\ClaudePetWin.exe, <root>\claude-pet.exe, <root>\pets\default\
    public static func hookExecutable(executable: URL) -> URL {
        executable.deletingLastPathComponent().appendingPathComponent("claude-pet.exe")
    }

    public static func builtinPetDirectory(executable: URL) -> URL {
#if os(Windows)
        let winPetsDefault = executable.deletingLastPathComponent()
            .appendingPathComponent("pets/default", isDirectory: true)
        if FileManager.default.fileExists(atPath: winPetsDefault.path) {
            return winPetsDefault
        }
        return resources(executable: executable).appendingPathComponent("Resources/pets/default", isDirectory: true)
#else
        if appBundle(containing: executable) != nil {
            return resources(executable: executable).appendingPathComponent("pets/default", isDirectory: true)
        }
        return resources(executable: executable).appendingPathComponent("Resources/pets/default", isDirectory: true)
#endif
    }
}
