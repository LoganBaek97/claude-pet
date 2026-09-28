import ClaudePetCore
import XCTest

final class GitBashTests: XCTestCase {
    func testExplicitPathWins() {
        let env = ["CLAUDE_CODE_GIT_BASH_PATH": "D:\\Git\\bin\\bash.exe", "SystemRoot": "C:\\Windows"]
        XCTAssertEqual(GitBash.locate(environment: env, exists: { _ in true }), "D:\\Git\\bin\\bash.exe")
    }

    func testSkipsSystem32WslStub() {
        let env = ["Path": "C:\\Windows\\System32;C:\\Program Files\\Git\\cmd", "SystemRoot": "C:\\Windows"]
        let found = GitBash.locate(environment: env, exists: { $0 == "C:\\Windows\\System32\\bash.exe" || $0 == "C:\\Program Files\\Git\\bin\\bash.exe" })
        XCTAssertEqual(found, "C:\\Program Files\\Git\\bin\\bash.exe")
    }

    func testNoGitBashMeansPowershell() {
        let env = ["Path": "C:\\Windows\\System32", "SystemRoot": "C:\\Windows", "ProgramFiles": "C:\\Program Files"]
        XCTAssertNil(GitBash.locate(environment: env, exists: { _ in false }))
        XCTAssertEqual(GitBash.claudeShell(environment: env, exists: { _ in false }), .powershell)
    }
}
