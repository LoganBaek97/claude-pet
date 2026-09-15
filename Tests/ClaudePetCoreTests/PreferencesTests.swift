import XCTest
@testable import ClaudePetCore

final class PreferencesTests: XCTestCase {
    func fresh() -> Preferences {
        let suite = "test.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return Preferences(defaults: d)
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
