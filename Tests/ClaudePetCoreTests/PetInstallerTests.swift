import XCTest
@testable import ClaudePetCore

final class PetInstallerTests: XCTestCase {
    var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// pet.json 과 시트를 담은 zip 을 만든다. `nested` 면 폴더 한 단계 안에 넣는다.
    func makeZip(id: String, sheetName: String = "spritesheet.png", validSheet: Bool = true, nested: Bool = false) throws -> Data {
        let work = root.appendingPathComponent("zip-\(UUID().uuidString)", isDirectory: true)
        let inner = nested ? work.appendingPathComponent(id, isDirectory: true) : work
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)
        try #"{"id":"\#(id)","displayName":"G","description":"d","spritesheetPath":"\#(sheetName)"}"#
            .write(to: inner.appendingPathComponent("pet.json"), atomically: true, encoding: .utf8)
        let image = validSheet ? TestImages.sheet(filledCells: [6, 8, 8, 4, 5, 8, 6, 6, 6])
                               : TestImages.sheet(filledCells: [], width: 10, height: 10)
        TestImages.writePNG(image, to: inner.appendingPathComponent(sheetName))
        let zip = root.appendingPathComponent("\(UUID().uuidString).zip")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = work
        p.arguments = ["-q", "-r", zip.path, "."]
        try p.run(); p.waitUntilExit()
        return try Data(contentsOf: zip)
    }

    func installer(api: [String: Data]) -> PetInstaller {
        PetInstaller(petsDirectory: root.appendingPathComponent("pets")) { url in
            guard let data = api[url.absoluteString] else { throw PetInstallerError.notFound }
            return data
        }
    }

    func testAddDownloadsUnzipsAndValidates() async throws {
        let zip = try makeZip(id: "guga")
        let meta = #"{"pet":{"id":"guga","downloadUrl":"/api/pets/guga/download?v=1"}}"#
        let inst = installer(api: [
            "https://codex-pets.net/api/pets/guga": Data(meta.utf8),
            "https://codex-pets.net/api/pets/guga/download?v=1": zip,
        ])
        let pet = try await inst.add(id: "guga")
        XCTAssertEqual(pet.id, "guga")
        XCTAssertEqual(pet.source, .user)
        XCTAssertTrue(FileManager.default.fileExists(atPath: pet.spritesheetURL.path))
        XCTAssertEqual(pet.directory.lastPathComponent, "guga")
    }

    func testNestedArchiveIsFlattened() async throws {
        let zip = try makeZip(id: "guga", nested: true)
        let meta = #"{"pet":{"id":"guga","downloadUrl":"https://codex-pets.net/api/pets/guga/download?v=2"}}"#
        let inst = installer(api: [
            "https://codex-pets.net/api/pets/guga": Data(meta.utf8),
            "https://codex-pets.net/api/pets/guga/download?v=2": zip,
        ])
        let pet = try await inst.add(id: "guga")
        XCTAssertTrue(FileManager.default.fileExists(atPath: pet.directory.appendingPathComponent("pet.json").path))
    }

    func testInvalidSheetIsRejectedAndCleanedUp() async throws {
        let zip = try makeZip(id: "bad", validSheet: false)
        let meta = #"{"pet":{"id":"bad","downloadUrl":"/dl"}}"#
        let inst = installer(api: ["https://codex-pets.net/api/pets/bad": Data(meta.utf8), "https://codex-pets.net/dl": zip])
        do {
            _ = try await inst.add(id: "bad")
            XCTFail("expected throw")
        } catch let e as PetInstallerError {
            guard case .invalidSheet = e else { return XCTFail("\(e)") }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pets/bad").path))
    }

    func testRejectsBadIdWithoutNetwork() async {
        // fetch 가 호출되면 badResponse 가 나오므로, invalidId 가 나오면 네트워크를 타지 않은 것이다.
        let inst = PetInstaller(petsDirectory: root) { _ in throw PetInstallerError.badResponse }
        do { _ = try await inst.add(id: "../etc"); XCTFail() } catch { XCTAssertEqual(error as? PetInstallerError, .invalidId) }
        do { _ = try await inst.add(id: "Guga"); XCTFail() } catch { XCTAssertEqual(error as? PetInstallerError, .invalidId, "uppercase rejected") }
    }

    func testMissingPetIsNotFound() async {
        let inst = installer(api: [:])
        do { _ = try await inst.add(id: "nope"); XCTFail() } catch { XCTAssertEqual(error as? PetInstallerError, .notFound) }
    }

    /// I-2 회귀: 이미 설치된 펫을 깨진 시트로 다시 받으면 throw 하되, 기존 pet.json/시트는 그대로 남아야 한다.
    func testReinstallWithBrokenSheetKeepsExistingPet() async throws {
        let goodZip = try makeZip(id: "guga")
        let metaGood = #"{"pet":{"id":"guga","downloadUrl":"/dl-good"}}"#
        let instGood = installer(api: [
            "https://codex-pets.net/api/pets/guga": Data(metaGood.utf8),
            "https://codex-pets.net/dl-good": goodZip,
        ])
        _ = try await instGood.add(id: "guga")
        let target = root.appendingPathComponent("pets/guga")
        let originalManifest = try Data(contentsOf: target.appendingPathComponent("pet.json"))
        let originalSheet = try Data(contentsOf: target.appendingPathComponent("spritesheet.png"))

        let badZip = try makeZip(id: "guga", validSheet: false)
        let metaBad = #"{"pet":{"id":"guga","downloadUrl":"/dl-bad"}}"#
        let instBad = installer(api: [
            "https://codex-pets.net/api/pets/guga": Data(metaBad.utf8),
            "https://codex-pets.net/dl-bad": badZip,
        ])
        do {
            _ = try await instBad.add(id: "guga")
            XCTFail("expected throw")
        } catch let e as PetInstallerError {
            guard case .invalidSheet = e else { return XCTFail("\(e)") }
        }

        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("pet.json")), originalManifest,
                       "existing pet.json must survive a failed reinstall")
        XCTAssertEqual(try Data(contentsOf: target.appendingPathComponent("spritesheet.png")), originalSheet,
                       "existing spritesheet must survive a failed reinstall")
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("pets/guga.new").path),
                       "staging directory must not be left behind")
    }

    /// F-5 회귀: 다운로드한 zip 이 20MB 를 넘으면 zip bomb 방지를 위해 badResponse 로 거부한다.
    func testRejectsOversizedZipDownload() async {
        let big = Data(count: PetInstaller.maxZipBytes + 1)
        let meta = #"{"pet":{"id":"guga","downloadUrl":"/big"}}"#
        let inst = installer(api: [
            "https://codex-pets.net/api/pets/guga": Data(meta.utf8),
            "https://codex-pets.net/big": big,
        ])
        do { _ = try await inst.add(id: "guga"); XCTFail("expected throw") }
        catch { XCTAssertEqual(error as? PetInstallerError, .badResponse) }
    }
}
