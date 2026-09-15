import XCTest
@testable import ClaudePetCore

final class HooksInstallerTests: XCTestCase {
    let script = URL(fileURLWithPath: "/Applications/ClaudePet.app/Contents/Resources/hook.sh")

    func groups(_ s: [String: Any], _ event: String) -> [[String: Any]] {
        ((s["hooks"] as? [String: Any])?[event] as? [[String: Any]]) ?? []
    }
    func commands(_ s: [String: Any], _ event: String) -> [String] {
        groups(s, event).flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] }.compactMap { $0["command"] as? String }
    }

    func testCommandQuotesPathAndAppendsMarker() {
        XCTAssertEqual(HooksInstaller.command(forHookScript: script),
                       "\"/Applications/ClaudePet.app/Contents/Resources/hook.sh\" # claude-pet")
    }

    func testInstallIntoEmptySettingsAddsEveryEvent() throws {
        let out = try HooksInstaller.install(into: [:], hookScript: script)
        for event in EventMapper.hookedEvents {
            XCTAssertEqual(commands(out, event).count, 1, event)
            XCTAssertTrue(commands(out, event)[0].hasSuffix(" # claude-pet"))
        }
        XCTAssertEqual(groups(out, "PreToolUse")[0]["matcher"] as? String, "*")
        XCTAssertNil(groups(out, "Stop")[0]["matcher"])
        XCTAssertTrue(HooksInstaller.isInstalled(in: out))
    }

    func testInstallPreservesExistingHooksAndOtherKeys() throws {
        let existing: [String: Any] = [
            "model": "opus",
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/orca/hook.sh"]]]]],
        ]
        let out = try HooksInstaller.install(into: existing, hookScript: script)
        XCTAssertEqual(out["model"] as? String, "opus")
        XCTAssertEqual(commands(out, "Stop"), ["/orca/hook.sh", HooksInstaller.command(forHookScript: script)])
    }

    func testInstallTwiceUpdatesPathInsteadOfDuplicating() throws {
        let first = try HooksInstaller.install(into: [:], hookScript: script)
        let moved = URL(fileURLWithPath: "/opt/ClaudePet.app/Contents/Resources/hook.sh")
        let second = try HooksInstaller.install(into: first, hookScript: moved)
        XCTAssertEqual(commands(second, "PreToolUse"), [HooksInstaller.command(forHookScript: moved)])
    }

    /// I-1 회귀: 같은 matcher 그룹 안에 남의 훅과 우리 훅이 섞여 있으면, 재설치가 남의 훅을 지우면 안 된다.
    func testInstallInSameGroupUpdatesOursAndKeepsOthers() throws {
        let mixed: [String: Any] = [
            "hooks": ["PreToolUse": [[
                "matcher": "*",
                "hooks": [
                    ["type": "command", "command": "/orca/hook.sh"],
                    ["type": "command", "command": HooksInstaller.command(forHookScript: script)],
                ],
            ]]],
        ]
        let moved = URL(fileURLWithPath: "/opt/ClaudePet.app/Contents/Resources/hook.sh")
        let out = try HooksInstaller.install(into: mixed, hookScript: moved)
        XCTAssertEqual(commands(out, "PreToolUse"), ["/orca/hook.sh", HooksInstaller.command(forHookScript: moved)])
        XCTAssertEqual(groups(out, "PreToolUse").count, 1, "no new group created")
    }

    /// SubagentStart/SubagentStop 이 hookedEvents 에서 빠졌으므로, 예전 설치가 남긴 우리 항목은 업그레이드 때 지워져야 한다.
    func testInstallRemovesOurEntriesFromEventsNoLongerHooked() throws {
        let existing: [String: Any] = [
            "hooks": ["SubagentStop": [["hooks": [
                ["type": "command", "command": "/other/hook.sh"],
                ["type": "command", "command": HooksInstaller.command(forHookScript: script)],
            ]]]],
        ]
        let out = try HooksInstaller.install(into: existing, hookScript: script)
        XCTAssertEqual(commands(out, "SubagentStop"), ["/other/hook.sh"])
        for event in EventMapper.hookedEvents {
            XCTAssertEqual(commands(out, event).count, 1, event)
        }
    }

    func testInstallThrowsWhenHooksIsNotAnObject() {
        XCTAssertThrowsError(try HooksInstaller.install(into: ["hooks": "nope"], hookScript: script)) {
            XCTAssertEqual($0 as? HooksInstallerError, .notAnObject)
        }
        XCTAssertThrowsError(try HooksInstaller.install(into: ["hooks": ["Stop": "nope"]], hookScript: script)) {
            XCTAssertEqual($0 as? HooksInstallerError, .notAnObject)
        }
    }

    func testUninstallRemovesOnlyOursAndDropsEmptyKeys() throws {
        let existing: [String: Any] = [
            "hooks": ["Stop": [["hooks": [["type": "command", "command": "/orca/hook.sh"]]]]],
        ]
        let installed = try HooksInstaller.install(into: existing, hookScript: script)
        let out = try HooksInstaller.uninstall(from: installed)
        XCTAssertEqual(commands(out, "Stop"), ["/orca/hook.sh"])
        XCTAssertNil((out["hooks"] as? [String: Any])?["PreToolUse"])
        XCTAssertFalse(HooksInstaller.isInstalled(in: out))
        let bare = try HooksInstaller.uninstall(from: try HooksInstaller.install(into: [:], hookScript: script))
        XCTAssertNil(bare["hooks"], "hooks key removed when nothing is left")
    }

    func testInstallFileWritesBackupAndValidJSON() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try #"{"model":"opus"}"#.write(to: file, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_789_000_000)
        let backup = try HooksInstaller.installFile(at: file, hookScript: script, now: now)
        XCTAssertEqual(backup.lastPathComponent.hasPrefix("settings.json.bak-"), true)
        XCTAssertEqual(try String(contentsOf: backup, encoding: .utf8), #"{"model":"opus"}"#)
        let obj = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        XCTAssertEqual(obj["model"] as? String, "opus")
        XCTAssertTrue(HooksInstaller.isInstalled(in: obj))
        XCTAssertTrue(HooksInstaller.isInstalled(file: file))
    }

    func testInstallFileCreatesMissingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent(".claude/settings.json")
        _ = try HooksInstaller.installFile(at: file, hookScript: script, now: Date())
        XCTAssertTrue(HooksInstaller.isInstalled(file: file))
    }

    func testInstallFileRefusesInvalidJSONWithoutTouchingIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        try "{broken".write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HooksInstaller.installFile(at: file, hookScript: script, now: Date())) {
            XCTAssertEqual($0 as? HooksInstallerError, .invalidJSON)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "{broken")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["settings.json"])
    }

    /// I-1 회귀: `hooks` 값이 딕셔너리가 아니면 installFile 이 원본 파일을 건드리지 않는다.
    func testInstallFileThrowsAndLeavesFileUntouchedWhenHooksIsNotAnObject() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("settings.json")
        let original = #"{"hooks":"nope"}"#
        try original.write(to: file, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try HooksInstaller.installFile(at: file, hookScript: script, now: Date())) {
            XCTAssertEqual($0 as? HooksInstallerError, .notAnObject)
        }
        XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), original)
    }
}
