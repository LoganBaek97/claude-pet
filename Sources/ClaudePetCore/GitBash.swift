import Foundation

/// Windows 의 Claude Code 는 Git Bash 가 있으면 훅을 `sh -c` 로, 없으면 PowerShell 로 돈다.
/// 설치기는 같은 순서로 Git Bash 를 찾아 훅 항목의 `shell` 을 정한다.
/// 탐지 순서는 Claude Code 문서와 같다: `CLAUDE_CODE_GIT_BASH_PATH` → PATH → `C:\Program Files\Git\bin\bash.exe`.
public enum GitBash {
    public static func locate(environment: [String: String] = ProcessInfo.processInfo.environment,
                              exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> String? {
        if let explicit = environment["CLAUDE_CODE_GIT_BASH_PATH"], !explicit.isEmpty, exists(explicit) {
            return explicit
        }
        let separator: Character = environment["OS"]?.hasPrefix("Windows") == true || environment["SystemRoot"] != nil ? ";" : ":"
        for dir in (environment["PATH"] ?? environment["Path"] ?? "").split(separator: separator) where !dir.isEmpty {
            let candidate = "\(dir)\\bash.exe"
            // System32 의 bash.exe 는 WSL 스텁이라 Git Bash 가 아니다.
            if candidate.lowercased().contains("\\system32\\") { continue }
            if exists(candidate) { return candidate }
        }
        let programFiles = environment["ProgramFiles"] ?? "C:\\Program Files"
        let localAppData = environment["LOCALAPPDATA"]
        var fixed = ["\(programFiles)\\Git\\bin\\bash.exe"]
        if let localAppData { fixed.append("\(localAppData)\\Programs\\Git\\bin\\bash.exe") }
        return fixed.first(where: exists)
    }

    /// Claude 훅 항목에 쓸 셸. Git Bash 가 있으면 bash, 없으면 powershell.
    public static func claudeShell(environment: [String: String] = ProcessInfo.processInfo.environment,
                                   exists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> HookShell {
        locate(environment: environment, exists: exists) == nil ? .powershell : .bash
    }
}
