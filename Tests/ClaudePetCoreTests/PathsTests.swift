import XCTest
@testable import ClaudePetCore

final class PathsTests: XCTestCase {
#if os(macOS)
    func testStateDirectoryIsUnderApplicationSupport() {
        let path = Paths.stateDirectory.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/ClaudePet/state"), path)
    }
#endif

#if os(Windows)
    func testApplicationSupportUsesLocalAppData() {
        let url = Paths.applicationSupport(environment: ["LOCALAPPDATA": "C:\\Users\\x\\AppData\\Local"])
        XCTAssertEqual(url.path, "C:\\Users\\x\\AppData\\Local\\ClaudePet")
    }

    func testApplicationSupportFallsBackToHomeWhenLocalAppDataMissing() {
        let url = Paths.applicationSupport(environment: [:])
        XCTAssertTrue(url.path.hasSuffix("AppData\\Local\\ClaudePet"))
    }
#endif

    func testStateDirectoryHonoursEnvironmentOverride() {
        let custom = Paths.stateDirectory(environment: ["CLAUDE_PET_STATE_DIR": "/tmp/x"])
        XCTAssertEqual(custom.path, "/tmp/x")
    }

    func testClaudeSettingsFile() {
        XCTAssertTrue(Paths.claudeSettingsFile.path.hasSuffix("/.claude/settings.json"))
    }
}
