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
        // corelibs 의 URL.path 는 Windows 에서도 슬래시(`C:/…`)를 준다(CI 실측). 구분자를 통일해 비교한다.
        let url = Paths.applicationSupport(environment: ["LOCALAPPDATA": "C:\\Users\\x\\AppData\\Local"])
        XCTAssertEqual(url.path.replacingOccurrences(of: "\\", with: "/"), "C:/Users/x/AppData/Local/ClaudePet")
    }

    func testApplicationSupportFallsBackToHomeWhenLocalAppDataMissing() {
        let url = Paths.applicationSupport(environment: [:])
        XCTAssertTrue(url.path.replacingOccurrences(of: "\\", with: "/").hasSuffix("AppData/Local/ClaudePet"))
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
