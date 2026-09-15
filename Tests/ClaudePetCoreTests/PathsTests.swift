import XCTest
@testable import ClaudePetCore

final class PathsTests: XCTestCase {
    func testStateDirectoryIsUnderApplicationSupport() {
        let path = Paths.stateDirectory.path
        XCTAssertTrue(path.hasSuffix("/Library/Application Support/ClaudePet/state"), path)
    }

    func testStateDirectoryHonoursEnvironmentOverride() {
        let custom = Paths.stateDirectory(environment: ["CLAUDE_PET_STATE_DIR": "/tmp/x"])
        XCTAssertEqual(custom.path, "/tmp/x")
    }

    func testClaudeSettingsFile() {
        XCTAssertTrue(Paths.claudeSettingsFile.path.hasSuffix("/.claude/settings.json"))
    }
}
