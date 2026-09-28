import XCTest
@testable import ClaudePetCore

final class HookCommandTests: XCTestCase {
    // macOS 에서 실행 가능한 테스트용 경로. URL.path 가 OS 중립적으로 해석된다.
    let exeURL = URL(fileURLWithPath: "/Users/x/ClaudePet/claude-pet.exe")
    let exePath = "/Users/x/ClaudePet/claude-pet.exe"
    // Windows 형식 문자열(경로 변환 테스트용)
    let winPathRaw  = "C:\\Users\\x\\claude-pet.exe"
    let winPathFwd  = "C:/Users/x/claude-pet.exe"

    // MARK: forwardSlashed

    func testForwardSlashedConvertsBackslashes() {
        XCTAssertEqual(HookCommand.forwardSlashed(winPathRaw), winPathFwd)
    }

    func testForwardSlashedLeavesUnixPathsAlone() {
        XCTAssertEqual(HookCommand.forwardSlashed("/usr/local/bin/x"), "/usr/local/bin/x")
    }

    // MARK: bashCommand / powershellCommand — 순수 문자열 함수

    func testBashCommandBuildsCorrectly() {
        XCTAssertEqual(HookCommand.bashCommand(executable: winPathFwd, agent: .claude),
                       "\"C:/Users/x/claude-pet.exe\" hook # claude-pet")
        XCTAssertEqual(HookCommand.bashCommand(executable: winPathFwd, agent: .codex),
                       "\"C:/Users/x/claude-pet.exe\" hook --agent codex # claude-pet")
    }

    func testPowershellCommandBuildsCorrectly() {
        let ps = HookCommand.powershellCommand(executable: winPathFwd, agent: .claude)
        XCTAssertTrue(ps.hasPrefix("[Console]::InputEncoding="), "PS prefix: \(ps)")
        XCTAssertTrue(ps.hasSuffix("| & \"C:/Users/x/claude-pet.exe\" hook # claude-pet"),
                      "PS suffix: \(ps)")
    }

    func testPowershellCommandWithCodexAgentIncludesFlag() {
        let ps = HookCommand.powershellCommand(executable: winPathFwd, agent: .codex)
        XCTAssertTrue(ps.contains("--agent codex"), "codex flag: \(ps)")
        XCTAssertTrue(ps.hasSuffix("| & \"C:/Users/x/claude-pet.exe\" hook --agent codex # claude-pet"),
                      "PS codex suffix: \(ps)")
    }

    // MARK: Windows Claude bash 항목 (macOS URL 로 실행)

    func testWindowsClaudeBashEntry() {
        let entry = HookCommand.entry(platform: .windows(hookExecutable: exeURL, claudeShell: .bash),
                                      agent: .claude, event: "Stop")
        XCTAssertEqual(entry["shell"] as? String, "bash")
        XCTAssertEqual(entry["command"] as? String,
                       "\"\(exePath)\" hook # claude-pet")
        XCTAssertNil(entry["commandWindows"])
        XCTAssertEqual(entry["timeout"] as? Int, 5)
    }

    // MARK: Windows Claude powershell 항목

    func testWindowsClaudePowershellEntry() {
        let entry = HookCommand.entry(platform: .windows(hookExecutable: exeURL, claudeShell: .powershell),
                                      agent: .claude, event: "Stop")
        XCTAssertEqual(entry["shell"] as? String, "powershell")
        let cmd = entry["command"] as? String ?? ""
        XCTAssertTrue(cmd.hasPrefix("[Console]::InputEncoding="), "expected PS prefix, got: \(cmd)")
        XCTAssertTrue(cmd.hasSuffix("| & \"\(exePath)\" hook # claude-pet"),
                      "expected PS suffix, got: \(cmd)")
        XCTAssertNil(entry["commandWindows"])
        XCTAssertEqual(entry["timeout"] as? Int, 5)
    }

    // MARK: Windows Codex 항목

    func testWindowsCodexEntryHasBothCommandForms() {
        let entry = HookCommand.entry(platform: .windows(hookExecutable: exeURL, claudeShell: .bash),
                                      agent: .codex, event: "PreToolUse")
        let bash = entry["command"] as? String ?? ""
        let ps   = entry["commandWindows"] as? String ?? ""
        XCTAssertTrue(bash.hasSuffix("--agent codex # claude-pet"), "bash: \(bash)")
        XCTAssertTrue(ps.contains("--agent codex"), "ps: \(ps)")
        XCTAssertTrue(ps.hasSuffix("--agent codex # claude-pet"), "ps suffix: \(ps)")
        XCTAssertNil(entry["shell"], "Codex 항목에는 shell 키가 없어야 한다")
        XCTAssertEqual(entry["timeout"] as? Int, 5)
    }

    func testWindowsCodexTimeoutThreeForSessionEndAndInterrupt() {
        for event in ["SessionEnd", "Interrupt"] {
            let entry = HookCommand.entry(platform: .windows(hookExecutable: exeURL, claudeShell: .bash),
                                          agent: .codex, event: event)
            XCTAssertEqual(entry["timeout"] as? Int, 3, event)
        }
    }

    // MARK: isOurs / isInstalled — commandWindows 만 있는 항목

    func testIsOursRecognisesCommandWindowsOnlyEntry() {
        let hook: [String: Any] = [
            "type": "command",
            "commandWindows": "[Console]::... | & \"\(exePath)\" hook # claude-pet",
        ]
        let settings: [String: Any] = [
            "hooks": ["Stop": [["hooks": [hook]]]],
        ]
        XCTAssertTrue(HooksInstaller.isInstalled(in: settings))
    }

    // MARK: 크로스 플랫폼 교체 — mac→windows

    func testInstallingWindowsOverMacReplacesEntryWholly() throws {
        let script = URL(fileURLWithPath: "/Applications/ClaudePet.app/hook.sh")
        let mac = try HooksInstaller.install(into: [:], platform: .macOS(hookScript: script), agent: .claude)
        let win = try HooksInstaller.install(into: mac, platform: .windows(hookExecutable: exeURL, claudeShell: .bash), agent: .claude)

        for event in Agent.claude.hookedEvents {
            let hooks = ((win["hooks"] as? [String: Any])?[event] as? [[String: Any]])?
                .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] } ?? []
            // 우리 항목은 정확히 하나
            let ours = hooks.filter {
                ($0["command"] as? String)?.hasSuffix(HooksInstaller.marker) == true ||
                ($0["commandWindows"] as? String)?.hasSuffix(HooksInstaller.marker) == true
            }
            XCTAssertEqual(ours.count, 1, "event \(event): ours count should be 1")
            // mac command 가 남아 있으면 안 된다
            let macCmd = hooks.compactMap { $0["command"] as? String }.filter { $0.contains("hook.sh") }
            XCTAssertTrue(macCmd.isEmpty, "event \(event): stale mac command found")
        }
        XCTAssertTrue(HooksInstaller.isInstalled(in: win))
    }

    // MARK: 크로스 플랫폼 교체 — windows→mac

    func testInstallingMacOverWindowsReplacesEntryWholly() throws {
        let script = URL(fileURLWithPath: "/Applications/ClaudePet.app/hook.sh")
        let win = try HooksInstaller.install(into: [:], platform: .windows(hookExecutable: exeURL, claudeShell: .bash), agent: .claude)
        let mac = try HooksInstaller.install(into: win, platform: .macOS(hookScript: script), agent: .claude)

        for event in Agent.claude.hookedEvents {
            let hooks = ((mac["hooks"] as? [String: Any])?[event] as? [[String: Any]])?
                .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] } ?? []
            let ours = hooks.filter { ($0["command"] as? String)?.hasSuffix(HooksInstaller.marker) == true }
            XCTAssertEqual(ours.count, 1, "event \(event)")
            // shell 키나 commandWindows 가 남아 있으면 안 된다
            XCTAssertFalse(hooks.contains { $0["shell"] != nil }, "event \(event): stale shell key found")
            XCTAssertFalse(hooks.contains { $0["commandWindows"] != nil }, "event \(event): stale commandWindows key found")
        }
    }

    // MARK: uninstall removes Windows entries

    func testUninstallRemovesWindowsEntries() throws {
        let win = try HooksInstaller.install(into: [:], platform: .windows(hookExecutable: exeURL, claudeShell: .bash), agent: .claude)
        XCTAssertTrue(HooksInstaller.isInstalled(in: win))
        let out = try HooksInstaller.uninstall(from: win)
        XCTAssertFalse(HooksInstaller.isInstalled(in: out))
        XCTAssertNil(out["hooks"], "hooks key removed when nothing left")
    }

    func testUninstallRemovesCodexWindowsEntries() throws {
        let win = try HooksInstaller.install(into: [:], platform: .windows(hookExecutable: exeURL, claudeShell: .bash), agent: .codex)
        XCTAssertTrue(HooksInstaller.isInstalled(in: win))
        let out = try HooksInstaller.uninstall(from: win)
        XCTAssertFalse(HooksInstaller.isInstalled(in: out))
    }

    // MARK: 재설치가 항목을 통째로 바꾼다

    func testReinstallWindowsReplacesEntryWholly() throws {
        let first = try HooksInstaller.install(into: [:], platform: .windows(hookExecutable: exeURL, claudeShell: .bash), agent: .claude)
        let newExeURL = URL(fileURLWithPath: "/New/claude-pet.exe")
        let second = try HooksInstaller.install(into: first, platform: .windows(hookExecutable: newExeURL, claudeShell: .powershell), agent: .claude)

        for event in Agent.claude.hookedEvents {
            let hooks = ((second["hooks"] as? [String: Any])?[event] as? [[String: Any]])?
                .flatMap { ($0["hooks"] as? [[String: Any]]) ?? [] } ?? []
            let ours = hooks.filter { ($0["command"] as? String)?.hasSuffix(HooksInstaller.marker) == true }
            XCTAssertEqual(ours.count, 1, "event \(event)")
            // 새 shell 이 powershell 이어야 한다
            XCTAssertEqual(ours[0]["shell"] as? String, "powershell", "event \(event)")
            // 새 exe 경로가 반영됐어야 한다
            let cmd = ours[0]["command"] as? String ?? ""
            XCTAssertTrue(cmd.contains("/New/claude-pet.exe"), "event \(event): new exe path expected in: \(cmd)")
        }
    }

    func testForwardSlashedDropsLeadingSlashBeforeDriveLetter() {
        XCTAssertEqual(HookCommand.forwardSlashed("/C:/Users/x/claude-pet.exe"), "C:/Users/x/claude-pet.exe")
        XCTAssertEqual(HookCommand.forwardSlashed("/usr/local/bin/x"), "/usr/local/bin/x")
    }
}
