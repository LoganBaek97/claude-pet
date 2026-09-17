import Foundation

/// 펫이 상태를 받는 코딩 에이전트. 훅 설정 파일, 걸 이벤트, 타임아웃이 에이전트마다 다르다.
/// rawValue 는 훅 스크립트의 `--agent` 인자와 상태 파일의 `agent` 필드에 그대로 쓴다.
public enum Agent: String, CaseIterable, Codable, Sendable {
    case claude, codex

    public var displayName: String {
        switch self {
        case .claude: return "Claude Code"
        case .codex: return "Codex"
        }
    }

    /// 훅을 등록하는 파일. Claude 는 settings.json 의 `hooks` 키, Codex 는 전용 hooks.json.
    /// 두 파일 모두 루트 객체의 `hooks` 키 아래 같은 모양이라 설치기를 공유한다.
    public func settingsFile(home: URL) -> URL {
        switch self {
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        }
    }

    public var settingsFile: URL { settingsFile(home: Paths.home) }

    /// 이 에이전트가 실제로 내보내는 이벤트만 건다. Codex 에는 Notification, PostToolUseFailure,
    /// StopFailure 가 없고 Interrupt 가 있다.
    public var hookedEvents: [String] {
        switch self {
        case .claude: return EventMapper.hookedEvents
        case .codex: return [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PermissionRequest", "Stop", "Interrupt",
        ]
        }
    }

    /// 훅 타임아웃(초). Codex 는 SessionEnd 와 Interrupt 를 최대 3초까지만 허용한다.
    public func timeout(for event: String) -> Int {
        if self == .codex, event == "SessionEnd" || event == "Interrupt" { return 3 }
        return 5
    }

    /// 훅을 등록한 뒤 사용자가 더 해야 할 일. Codex 는 신뢰하지 않은 훅을 건너뛰므로 /hooks 승인이 필요하다.
    public var postInstallNote: String? {
        switch self {
        case .claude: return nil
        case .codex: return "Codex 는 신뢰한 훅만 돌립니다. codex 를 열고 /hooks 에서 claude-pet 항목을 신뢰해 주세요. 앱 경로가 바뀌면 다시 승인해야 합니다."
        }
    }

    /// Codex 는 한 번이라도 쓴 흔적(~/.codex)이 있을 때만 설치 대상이다.
    public func isAvailable(home: URL) -> Bool {
        switch self {
        case .claude: return true
        case .codex: return FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path)
        }
    }

    public static func installTargets(home: URL = Paths.home) -> [Agent] {
        allCases.filter { $0.isAvailable(home: home) }
    }
}
