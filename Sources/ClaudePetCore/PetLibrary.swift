import Foundation

public enum PetLibrary {
    /// user → codex → builtin 순으로 모은다. 같은 id 는 먼저 나온 것이 이긴다. 각 출처 안에서는 id 순.
    public static func discover(userDirectory: URL, codexDirectory: URL, builtinDirectory: URL?) -> [InstalledPet] {
        var seen = Set<String>()
        var result: [InstalledPet] = []
        func add(_ pets: [InstalledPet]) {
            for pet in pets.sorted(by: { $0.id < $1.id }) where !seen.contains(pet.id) {
                seen.insert(pet.id)
                result.append(pet)
            }
        }
        add(scan(userDirectory, source: .user))
        add(scan(codexDirectory, source: .codex))
        if let builtin = builtinDirectory, let pet = load(directory: builtin, source: .builtin) {
            add([pet])
        }
        return result
    }

    static func scan(_ parent: URL, source: PetSource) -> [InstalledPet] {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: parent.path) else { return [] }
        return names.compactMap { load(directory: parent.appendingPathComponent($0, isDirectory: true), source: source) }
    }

    /// pet.json 과 시트 파일이 둘 다 있어야 펫으로 인정한다.
    public static func load(directory: URL, source: PetSource) -> InstalledPet? {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: directory.appendingPathComponent("pet.json").path),
              let manifest = try? JSONDecoder().decode(PetManifest.self, from: data) else { return nil }
        guard isSafeSpritesheetPath(manifest.spritesheetPath) else { return nil }
        let pet = InstalledPet(manifest: manifest, directory: directory, source: source)
        guard fm.fileExists(atPath: pet.spritesheetURL.path) else { return nil }
        return pet
    }

    /// 디렉터리 밖을 가리킬 수 있는 경로(비어 있음, "/" 포함, ".." 포함)는 거부한다(F-4).
    static func isSafeSpritesheetPath(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("/") && !path.contains("..")
    }
}
