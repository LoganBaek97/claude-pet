import Foundation

public enum HooksInstallerError: Error, Equatable {
    case invalidJSON
    case notAnObject
}

public enum HooksInstaller {
    public static let marker = "# claude-pet"
    static let toolEvents: Set<String> = ["PreToolUse", "PostToolUse", "PostToolUseFailure", "PermissionRequest"]

    /// Claude 는 인자 없이, 다른 에이전트는 `--agent <id>` 를 마커 앞에 붙인다.
    /// `#` 뒤는 셸 주석이라 스크립트에 전달되지 않고, 식별용으로만 남는다.
    public static func command(forHookScript script: URL, agent: Agent = .claude) -> String {
        let flag = agent == .claude ? "" : " --agent \(agent.rawValue)"
        return "\"\(script.path)\"\(flag) \(marker)"
    }

    static func isOurs(_ hook: [String: Any]) -> Bool {
        (hook["command"] as? String)?.hasSuffix(marker) == true
    }

    static func groupIsOurs(_ group: [String: Any]) -> Bool {
        ((group["hooks"] as? [[String: Any]]) ?? []).contains(where: isOurs)
    }

    // MARK: 순수 변환

    /// `settings["hooks"]` 또는 `hooks[event]` 가 딕셔너리/배열이 아닌 예상 밖 타입이면 조용히 버리지 않고 던진다.
    public static func install(into settings: [String: Any], hookScript: URL, agent: Agent = .claude) throws -> [String: Any] {
        var out = settings
        var hooks: [String: Any]
        if let raw = settings["hooks"] {
            guard let dict = raw as? [String: Any] else { throw HooksInstallerError.notAnObject }
            hooks = dict
        } else {
            hooks = [:]
        }
        let command = command(forHookScript: hookScript, agent: agent)
        for event in agent.hookedEvents {
            let entry: [String: Any] = ["type": "command", "command": command, "timeout": agent.timeout(for: event)]
            var groups: [[String: Any]]
            if let raw = hooks[event] {
                guard let arr = raw as? [[String: Any]] else { throw HooksInstallerError.notAnObject }
                groups = arr
            } else {
                groups = []
            }
            if let i = groups.firstIndex(where: groupIsOurs) {
                var group = groups[i]
                var hooksInGroup = (group["hooks"] as? [[String: Any]]) ?? []
                if let j = hooksInGroup.firstIndex(where: isOurs) { hooksInGroup[j] = entry }
                else { hooksInGroup.append(entry) }
                group["hooks"] = hooksInGroup
                groups[i] = group
            } else {
                var group: [String: Any] = ["hooks": [entry]]
                if toolEvents.contains(event) { group["matcher"] = "*" }
                groups.append(group)
            }
            hooks[event] = groups
        }
        // hookedEvents 에서 빠진 이벤트(예: 예전 버전이 걸어 둔 SubagentStart/SubagentStop, Codex 파일에 남은
        // Notification)에 남은 우리 항목은 업그레이드 시 지운다. uninstall 과 같은 규칙: 남의 훅은 보존하고,
        // 비게 된 그룹/키는 없앤다.
        let hookedSet = Set(agent.hookedEvents)
        for event in hooks.keys where !hookedSet.contains(event) {
            guard let groups = hooks[event] as? [[String: Any]] else { throw HooksInstallerError.notAnObject }
            let kept = groups.compactMap { group -> [String: Any]? in
                var g = group
                let remaining = ((g["hooks"] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
                if remaining.isEmpty && groupIsOurs(group) { return nil }
                g["hooks"] = remaining
                return g
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        out["hooks"] = hooks
        return out
    }

    public static func uninstall(from settings: [String: Any]) throws -> [String: Any] {
        var out = settings
        guard let raw = settings["hooks"] else { return out }
        guard var hooks = raw as? [String: Any] else { throw HooksInstallerError.notAnObject }
        for (event, value) in hooks {
            guard let groups = value as? [[String: Any]] else { throw HooksInstallerError.notAnObject }
            let kept = groups.compactMap { group -> [String: Any]? in
                var g = group
                let remaining = ((g["hooks"] as? [[String: Any]]) ?? []).filter { !isOurs($0) }
                if remaining.isEmpty && groupIsOurs(group) { return nil }
                g["hooks"] = remaining
                return g
            }
            if kept.isEmpty { hooks.removeValue(forKey: event) } else { hooks[event] = kept }
        }
        if hooks.isEmpty { out.removeValue(forKey: "hooks") } else { out["hooks"] = hooks }
        return out
    }

    public static func isInstalled(in settings: [String: Any]) -> Bool {
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { value in
            ((value as? [[String: Any]]) ?? []).contains(where: groupIsOurs)
        }
    }

    // MARK: 파일 IO

    static func read(_ url: URL) throws -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: url.path) else { return [:] }
        if data.isEmpty { return [:] }
        guard let obj = try? JSONSerialization.jsonObject(with: data) else { throw HooksInstallerError.invalidJSON }
        guard let dict = obj as? [String: Any] else { throw HooksInstallerError.notAnObject }
        return dict
    }

    static func backupName(for url: URL, now: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(url.lastPathComponent).bak-\(f.string(from: now))"
    }

    /// 백업을 만든 뒤에만 쓴다. 파일이 없으면 백업 없이 새로 만든다. 반환값은 백업 경로(없으면 원본 경로).
    @discardableResult
    public static func installFile(at url: URL, hookScript: URL, agent: Agent = .claude, now: Date) throws -> URL {
        let settings = try read(url)
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var backup = url
        if fm.fileExists(atPath: url.path) {
            backup = url.deletingLastPathComponent().appendingPathComponent(backupName(for: url, now: now))
            try fm.copyItem(at: url, to: backup)
        }
        try write(try install(into: settings, hookScript: hookScript, agent: agent), to: url)
        return backup
    }

    @discardableResult
    public static func uninstallFile(at url: URL, now: Date) throws -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        let settings = try read(url)
        guard isInstalled(in: settings) else { return nil }
        let backup = url.deletingLastPathComponent().appendingPathComponent(backupName(for: url, now: now))
        try fm.copyItem(at: url, to: backup)
        try write(try uninstall(from: settings), to: url)
        return backup
    }

    public static func isInstalled(file url: URL) -> Bool {
        (try? read(url)).map(isInstalled(in:)) ?? false
    }

    static func write(_ settings: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    }
}
