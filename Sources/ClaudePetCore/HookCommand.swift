import Foundation

public enum HookShell: String, Sendable {
    case bash, powershell
}

/// 훅 항목을 어디서 어떻게 돌릴지. mac 은 hook.sh, Windows 는 네이티브 CLI 의 `hook` 서브커맨드.
public enum HookPlatform: Equatable, Sendable {
    case macOS(hookScript: URL)
    case windows(hookExecutable: URL, claudeShell: HookShell)
}

public enum HookCommand {
    /// 우리 훅을 식별하는 마커. HooksInstaller.marker 의 원본.
    public static let marker = "# claude-pet"

    /// C:\a\b → C:/a/b (Windows 경로만; POSIX 경로는 그대로).
    /// corelibs 의 `URL.path` 가 드라이브 앞에 `/` 를 붙여 `/C:/…` 로 주는 경우도 걷어 낸다.
    static func forwardSlashed(_ path: String) -> String {
        var p = path.replacingOccurrences(of: "\\", with: "/")
        if p.count >= 3, p.hasPrefix("/"), p[p.index(p.startIndex, offsetBy: 2)] == ":",
           p[p.index(after: p.startIndex)].isLetter {
            p.removeFirst()
        }
        return p
    }

    /// sh 형: `"C:/…/claude-pet.exe" hook[ --agent codex] # claude-pet`
    static func bashCommand(executable: String, agent: Agent) -> String {
        let flag = agent == .claude ? "" : " --agent \(agent.rawValue)"
        return "\"\(executable)\" hook\(flag) \(marker)"
    }

    /// PowerShell 형. stdin 을 명시적으로 넘기고 UTF-8 을 강제한다.
    static func powershellCommand(executable: String, agent: Agent) -> String {
        let flag = agent == .claude ? "" : " --agent \(agent.rawValue)"
        return "[Console]::InputEncoding=[Text.UTF8Encoding]::new(); $OutputEncoding=[Text.UTF8Encoding]::new(); [Console]::In.ReadToEnd() | & \"\(executable)\" hook\(flag) \(marker)"
    }

    /// 한 이벤트의 훅 항목 딕셔너리. timeout 은 agent.timeout(for:) 그대로.
    public static func entry(platform: HookPlatform, agent: Agent, event: String) -> [String: Any] {
        let timeout = agent.timeout(for: event)
        switch platform {
        case .macOS(let hookScript):
            let flag = agent == .claude ? "" : " --agent \(agent.rawValue)"
            let command = "\"\(hookScript.path)\"\(flag) \(marker)"
            return ["type": "command", "command": command, "timeout": timeout]
        case .windows(let hookExecutable, let claudeShell):
            let exe = forwardSlashed(hookExecutable.path)
            let bash = bashCommand(executable: exe, agent: agent)
            let ps = powershellCommand(executable: exe, agent: agent)
            if agent == .codex {
                // Codex 는 shell 키를 모른다. command(bash) + commandWindows(ps) 두 키를 준다.
                return ["type": "command", "command": bash, "commandWindows": ps, "timeout": timeout]
            } else {
                // Claude: shell 로 실행 환경을 고정하고 해당 형태의 커맨드를 쓴다.
                let command = claudeShell == .bash ? bash : ps
                return ["type": "command", "shell": claudeShell.rawValue, "command": command, "timeout": timeout]
            }
        }
    }
}
