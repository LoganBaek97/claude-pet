import XCTest
@testable import ClaudePetCore

final class PreferencesTests: XCTestCase {
    func fresh() -> Preferences {
        Preferences(store: MemoryPreferencesStore())
    }

    func testDefaults() {
        let p = fresh()
        XCTAssertNil(p.selectedPetId)
        XCTAssertEqual(p.scale, 0.5)
        XCTAssertFalse(p.isHidden)
        XCTAssertFalse(p.isBubbleHidden, "말풍선은 기본으로 보인다")
        XCTAssertNil(p.position)
    }

    func testRoundTrip() {
        let p = fresh()
        p.selectedPetId = "guga"; p.scale = 1.0; p.isHidden = true; p.isBubbleHidden = true; p.position = CGPoint(x: 10, y: 20)
        XCTAssertEqual(p.selectedPetId, "guga")
        XCTAssertEqual(p.scale, 1.0)
        XCTAssertTrue(p.isHidden)
        XCTAssertTrue(p.isBubbleHidden)
        XCTAssertEqual(p.position, CGPoint(x: 10, y: 20))
        p.position = nil
        XCTAssertNil(p.position)
    }

    func testScaleIsClampedToAllowedValues() {
        let p = fresh()
        p.scale = 0.7
        XCTAssertEqual(p.scale, 0.5, "unknown values fall back to default")
        p.scale = 0.35
        XCTAssertEqual(p.scale, 0.35)
    }
}

// MARK: 동작 줄이기 무시

extension PreferencesTests {
    /// 기본은 시스템 설정을 존중한다. 앱이 마음대로 무시하지 않는다.
    func testIgnoresReducedMotionDefaultsToOff() {
        XCTAssertFalse(fresh().ignoresReducedMotion)
    }

    func testIgnoresReducedMotionRoundTrips() {
        let p = fresh()
        p.ignoresReducedMotion = true
        XCTAssertTrue(p.ignoresReducedMotion)
        p.ignoresReducedMotion = false
        XCTAssertFalse(p.ignoresReducedMotion)
    }
}

// MARK: - UserDefaults 기반 테스트

#if canImport(Darwin)
extension PreferencesTests {
    func freshFromUserDefaults() -> Preferences {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return Preferences(defaults: d)
    }

    func testUserDefaultsRoundTrip() {
        let p = freshFromUserDefaults()
        p.selectedPetId = "test-ud"
        XCTAssertEqual(p.selectedPetId, "test-ud")
        XCTAssertEqual(p.scale, 0.5)
    }
}
#endif

// MARK: - FilePreferencesStore 테스트

extension PreferencesTests {
    func makeTempFileURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudePetTest_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("preferences.json")
    }

    func testFileStoreRoundTrip() {
        let url = makeTempFileURL()
        let p = Preferences(store: FilePreferencesStore(url: url))
        p.selectedPetId = "guga"
        p.scale = 1.0
        p.isHidden = true
        p.isBubbleHidden = true
        p.position = CGPoint(x: 10, y: 20)
        XCTAssertEqual(p.selectedPetId, "guga")
        XCTAssertEqual(p.scale, 1.0)
        XCTAssertTrue(p.isHidden)
        XCTAssertTrue(p.isBubbleHidden)
        XCTAssertEqual(p.position, CGPoint(x: 10, y: 20))
        p.position = nil
        XCTAssertNil(p.position)
    }

    func testFileStoreAtomicFileExists() {
        let url = makeTempFileURL()
        let store = FilePreferencesStore(url: url)
        store.set("hello", forKey: "key")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "파일이 생성됐어야 한다")
        let tmp = url.appendingPathExtension("tmp")
        XCTAssertFalse(FileManager.default.fileExists(atPath: tmp.path), "임시 파일이 남아 있으면 안 된다")
    }

    func testFileStoreSecondInstanceSeesMtimeReload() {
        let url = makeTempFileURL()
        // store2 는 파일이 없을 때 생성 → lastMtime = 0
        let store1 = FilePreferencesStore(url: url)
        let store2 = FilePreferencesStore(url: url)

        store1.set("hello", forKey: "key")
        // store1 이 쓰면 파일 mtime 이 0 이 아닌 값이 된다.
        // store2 는 다음 접근 시 mtime 차이를 감지해 파일을 다시 읽는다.
        XCTAssertEqual(store2.stringValue(forKey: "key"), "hello")
    }

    func testFileStoreNilRemovesKey() {
        let url = makeTempFileURL()
        let store = FilePreferencesStore(url: url)
        store.set("value", forKey: "key")
        XCTAssertEqual(store.stringValue(forKey: "key"), "value")
        store.set(nil, forKey: "key")
        XCTAssertNil(store.stringValue(forKey: "key"))
    }
}
