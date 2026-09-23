import XCTest
@testable import ClaudePetCore

final class SessionStateTests: XCTestCase {
    func makeSession(cwd: String) -> SessionState {
        SessionState(sessionId: "s", state: .idle, cwd: cwd, ts: 1)
    }

    func testProjectNameUnixPaths() {
        XCTAssertEqual(makeSession(cwd: "/Users/x/myproject").projectName, "myproject")
        XCTAssertEqual(makeSession(cwd: "/Users/x/myproject/").projectName, "myproject")
        XCTAssertEqual(makeSession(cwd: "/single").projectName, "single")
    }

    func testProjectNameEmptyCwd() {
        XCTAssertEqual(makeSession(cwd: "").projectName, "")
    }

    func testProjectNameWindowsPaths() {
        XCTAssertEqual(makeSession(cwd: #"C:\proj"#).projectName, "proj")
        XCTAssertEqual(makeSession(cwd: #"C:\proj\"#).projectName, "proj", "끝 구분자 무시")
        XCTAssertEqual(makeSession(cwd: #"C:\Users\x\my-workspace"#).projectName, "my-workspace")
    }

    func testProjectNameMixedSeparators() {
        XCTAssertEqual(makeSession(cwd: "/Users/x/mixed\\path").projectName, "path")
    }
}
