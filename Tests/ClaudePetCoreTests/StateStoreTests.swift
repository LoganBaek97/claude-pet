import XCTest
@testable import ClaudePetCore

final class StateStoreTests: XCTestCase {
    var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func write(_ name: String, _ content: String) throws {
        try content.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testLoadsValidFilesAndSkipsBroken() throws {
        try write("a.json", #"{"session_id":"a","state":"waiting","event":"PermissionRequest","tool":"Edit","cwd":"/p/a","ts":100}"#)
        try write("b.json", #"{"session_id":"b","state":"running","event":"PreToolUse","tool":"Bash","cwd":"/p/b","ts":200}"#)
        try write("broken.json", "{nope")
        try write("ignored.txt", "x")
        let loaded = StateStore(directory: dir).loadAll().sorted { $0.sessionId < $1.sessionId }
        XCTAssertEqual(loaded.map(\.sessionId), ["a", "b"])
        XCTAssertEqual(loaded[0].state, .waiting)
    }

    func testMissingDirectoryYieldsEmpty() {
        let missing = dir.appendingPathComponent("nope")
        XCTAssertEqual(StateStore(directory: missing).loadAll(), [])
    }

    func testHookEscapedBackslashParses() throws {
        try write("c.json", #"{"session_id":"c","state":"failed","event":"PostToolUseFailure","tool":"Bash","cwd":"/Users/x/q \\","ts":5}"#)
        let s = StateStore(directory: dir).loadAll()
        XCTAssertEqual(s.first?.cwd, #"/Users/x/q \"#)
    }

    func testRemoveStaleDeletesOnlyOldFiles() throws {
        let now = Date(timeIntervalSince1970: 1_000_000)
        try write("old.json", #"{"session_id":"old","state":"idle","event":"SessionStart","tool":"","cwd":"","ts":\#(Int(now.timeIntervalSince1970) - 90_000)}"#)
        try write("new.json", #"{"session_id":"new","state":"idle","event":"SessionStart","tool":"","cwd":"","ts":\#(Int(now.timeIntervalSince1970) - 10)}"#)
        StateStore(directory: dir).removeStale(olderThan: 24 * 3600, now: now)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(names, ["new.json"])
    }
}
