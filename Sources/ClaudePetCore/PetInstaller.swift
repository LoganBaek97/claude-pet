import Foundation

public enum PetInstallerError: Error, Equatable {
    case invalidId
    case notFound
    case badResponse
    case noManifestInArchive
    case invalidSheet(String)
}

public struct PetInstaller: Sendable {
    public static let apiBase = URL(string: "https://codex-pets.net")!
    /// zip 다운로드 상한. 초과하면 zip bomb 방지를 위해 badResponse 로 거부한다.
    public static let maxZipBytes = 20 * 1024 * 1024

    public let petsDirectory: URL
    private let fetch: @Sendable (URL) async throws -> Data

    public init(petsDirectory: URL, fetch: @escaping @Sendable (URL) async throws -> Data) {
        self.petsDirectory = petsDirectory
        self.fetch = fetch
    }

    /// URLSession 으로 받는 기본 구현. 2xx 가 아니면 notFound(404) 또는 badResponse.
    public static func live(petsDirectory: URL) -> PetInstaller {
        PetInstaller(petsDirectory: petsDirectory) { url in
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { throw PetInstallerError.badResponse }
            if http.statusCode == 404 { throw PetInstallerError.notFound }
            guard (200..<300).contains(http.statusCode) else { throw PetInstallerError.badResponse }
            return data
        }
    }

    public func add(id: String) async throws -> InstalledPet {
        guard !id.isEmpty, id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-").contains($0) }),
              !id.hasPrefix(".") else { throw PetInstallerError.invalidId }

        let metaData = try await fetch(Self.apiBase.appendingPathComponent("api/pets/\(id)"))
        guard let obj = try? JSONSerialization.jsonObject(with: metaData) as? [String: Any],
              let pet = obj["pet"] as? [String: Any],
              let download = pet["downloadUrl"] as? String,
              let downloadURL = URL(string: download, relativeTo: Self.apiBase)?.absoluteURL else {
            throw PetInstallerError.badResponse
        }
        let zipData = try await fetch(downloadURL)
        guard zipData.count <= Self.maxZipBytes else { throw PetInstallerError.badResponse }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent("claude-pet-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }
        let zipFile = work.appendingPathComponent("pet.zip")
        try zipData.write(to: zipFile)
        let extracted = work.appendingPathComponent("x", isDirectory: true)
        try fm.createDirectory(at: extracted, withIntermediateDirectories: true)
        try Self.unzip(zipFile, to: extracted)
        Self.removeSymlinks(in: extracted)

        guard let sourceDir = Self.findManifestDirectory(in: extracted, depth: 2) else {
            throw PetInstallerError.noManifestInArchive
        }

        // 기존 <pets>/<id> 를 지우기 전에 검증부터 끝낸다(I-2): 새 zip 이 깨져 있어도 이미 설치된 펫을 잃지 않는다.
        guard let sourcePet = PetLibrary.load(directory: sourceDir, source: .user) else {
            throw PetInstallerError.noManifestInArchive
        }
        do {
            _ = try SpriteSheet(contentsOf: sourcePet.spritesheetURL, spriteVersion: sourcePet.manifest.spriteVersion)
        } catch {
            throw PetInstallerError.invalidSheet("\(error)")
        }

        try fm.createDirectory(at: petsDirectory, withIntermediateDirectories: true)
        let target = petsDirectory.appendingPathComponent(id, isDirectory: true)
        let staged = petsDirectory.appendingPathComponent("\(id).new", isDirectory: true)
        try? fm.removeItem(at: staged)
        try fm.copyItem(at: sourceDir, to: staged)
        defer { try? fm.removeItem(at: staged) }
        if fm.fileExists(atPath: target.path) {
            _ = try fm.replaceItemAt(target, withItemAt: staged)
        } else {
            try fm.moveItem(at: staged, to: target)
        }

        return InstalledPet(manifest: sourcePet.manifest, directory: target, source: .user)
    }

    static func unzip(_ zip: URL, to dir: URL) throws {
        let p = Process()
#if os(Windows)
        let systemRoot = ProcessInfo.processInfo.environment["SystemRoot"] ?? "C:\\Windows"
        p.executableURL = URL(fileURLWithPath: "\(systemRoot)\\System32\\tar.exe")
        p.arguments = ["-xf", zip.path, "-C", dir.path]
#else
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-o", "-q", zip.path, "-d", dir.path]
#endif
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw PetInstallerError.badResponse }
    }

    /// 전개된 아카이브 안의 심링크를 모두 지운다(zip 에 심링크를 넣어 디렉터리 밖 파일을 가리키게 할 수 있으므로).
    static func removeSymlinks(in dir: URL) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: dir.path) else { return }
        for case let name as String in enumerator {
            let path = dir.appendingPathComponent(name).path
            guard let attrs = try? fm.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeSymbolicLink else { continue }
            try? fm.removeItem(atPath: path)
        }
    }

    static func findManifestDirectory(in dir: URL, depth: Int) -> URL? {
        let fm = FileManager.default
        if fm.fileExists(atPath: dir.appendingPathComponent("pet.json").path) { return dir }
        guard depth > 0, let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return nil }
        for name in names.sorted() where !name.hasPrefix(".") && name != "__MACOSX" {
            let child = dir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: child.path, isDirectory: &isDir), isDir.boolValue,
               let found = findManifestDirectory(in: child, depth: depth - 1) { return found }
        }
        return nil
    }
}
