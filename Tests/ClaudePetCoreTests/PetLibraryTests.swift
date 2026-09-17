import XCTest
@testable import ClaudePetCore

final class PetLibraryTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    func makePet(_ base: String, _ id: String, name: String = "N", sheet: String = "spritesheet.webp") throws -> URL {
        let dir = root.appendingPathComponent("\(base)/\(id)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let json = #"{"id":"\#(id)","displayName":"\#(name)","description":"d","spritesheetPath":"\#(sheet)"}"#
        try json.write(to: dir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
        try Data().write(to: dir.appendingPathComponent(sheet))
        return dir
    }

    func testSpriteVersionDefaultsToV1WhenOmitted() throws {
        let dir = try makePet("user", "old")
        XCTAssertEqual(PetLibrary.load(directory: dir, source: .user)?.manifest.spriteVersion, 1)
        let v2 = root.appendingPathComponent("user/new", isDirectory: true)
        try FileManager.default.createDirectory(at: v2, withIntermediateDirectories: true)
        try #"{"id":"new","displayName":"N","description":"d","spriteVersionNumber":2,"spritesheetPath":"spritesheet.webp"}"#
            .write(to: v2.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
        try Data().write(to: v2.appendingPathComponent("spritesheet.webp"))
        XCTAssertEqual(PetLibrary.load(directory: v2, source: .user)?.manifest.spriteVersion, 2)
    }

    func testDiscoversUserThenCodexAndDedupesById() throws {
        _ = try makePet("user", "guga", name: "user-guga")
        _ = try makePet("user", "clawd")
        _ = try makePet("codex", "guga", name: "codex-guga")
        _ = try makePet("codex", "dario")
        let pets = PetLibrary.discover(userDirectory: root.appendingPathComponent("user"),
                                       codexDirectory: root.appendingPathComponent("codex"),
                                       builtinDirectory: nil)
        XCTAssertEqual(pets.map(\.id), ["clawd", "guga", "dario"], "user pets sorted, then codex pets sorted")
        XCTAssertEqual(pets.first { $0.id == "guga" }?.manifest.displayName, "user-guga")
        XCTAssertEqual(pets.first { $0.id == "dario" }?.source, .codex)
    }

    func testBuiltinComesLast() throws {
        let builtin = try makePet("builtin", "default", sheet: "spritesheet.png")
        let pets = PetLibrary.discover(userDirectory: root.appendingPathComponent("user"),
                                       codexDirectory: root.appendingPathComponent("codex"),
                                       builtinDirectory: builtin)
        XCTAssertEqual(pets.map(\.id), ["default"])
        XCTAssertEqual(pets[0].source, .builtin)
        XCTAssertEqual(pets[0].spritesheetURL.lastPathComponent, "spritesheet.png")
    }

    /// F-4 회귀: spritesheetPath 가 디렉터리 밖을 가리킬 수 있으면(빈 값/ "/" 포함/ ".." 포함) 펫을 무효로 본다.
    func testRejectsUnsafeSpritesheetPath() throws {
        for badPath in ["../secret.webp", "sub/spritesheet.webp", "/etc/passwd", ""] {
            let dir = root.appendingPathComponent("user/evil-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let json = #"{"id":"evil","displayName":"E","description":"d","spritesheetPath":"\#(badPath)"}"#
            try json.write(to: dir.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
            XCTAssertNil(PetLibrary.load(directory: dir, source: .user), "should reject spritesheetPath \(badPath)")
        }
    }

    func testSkipsDirectoriesWithoutManifestOrSheet() throws {
        let noSheet = root.appendingPathComponent("user/nosheet", isDirectory: true)
        try FileManager.default.createDirectory(at: noSheet, withIntermediateDirectories: true)
        try #"{"id":"nosheet","displayName":"x","description":"","spritesheetPath":"missing.webp"}"#
            .write(to: noSheet.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("user/empty"), withIntermediateDirectories: true)
        let pets = PetLibrary.discover(userDirectory: root.appendingPathComponent("user"),
                                       codexDirectory: root.appendingPathComponent("none"), builtinDirectory: nil)
        XCTAssertEqual(pets, [])
    }
}
