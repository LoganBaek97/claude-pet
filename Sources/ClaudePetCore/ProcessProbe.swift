import Darwin
import Foundation

/// 세션 프로세스가 아직 있는지 본다.
///
/// pid 만 보면 위험하다. pid 는 돌려 쓰이므로 죽은 세션의 번호를 엉뚱한 프로그램이 물려받을 수 있다.
/// 그래서 그 프로세스가 정말 claude/codex 인지도 확인한다.
/// 판단이 틀려도 말풍선 한 장이 더 보이거나 덜 보일 뿐이라 되돌릴 수 없는 일은 일어나지 않는다.
public struct ProcessProbe: Sendable {
    /// 에이전트로 인정하는 이름.
    static let agentNames: Set<String> = ["claude", "codex"]

    public init() {}

    public func liveness(of session: SessionState) -> SessionLiveness {
        guard let pid = session.agentPid, pid > 0 else { return .unknown }
        guard Self.exists(pid) else { return .gone }
        return Self.isAgent(pid) ? .alive : .gone
    }

    /// 신호 0 은 아무것도 보내지 않고 보낼 수 있는지만 확인한다.
    /// 살아 있지만 남의 것이면 EPERM 이 오는데, 그것도 "있다" 는 뜻이다.
    static func exists(_ pid: Int32) -> Bool {
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// 두 가지를 본다. 한쪽만으로는 설치 방식에 따라 놓친다.
    ///
    /// 1. 커널이 들고 있는 짧은 이름(`p_comm`). 실행할 때 쓴 경로의 마지막 조각이라 보통 `claude` 다.
    /// 2. 실행 파일의 실제 경로. CLI 로 깐 Claude Code 는 심볼릭 링크를 따라가면 파일 이름이
    ///    버전 번호다(`~/.local/share/claude/versions/2.1.274`). 그래서 마지막 조각이 아니라
    ///    경로에 `claude`/`codex` 디렉터리가 있는지로 본다.
    static func isAgent(_ pid: Int32) -> Bool {
        if let name = processName(pid), agentNames.contains(name) { return true }
        guard let path = executablePath(pid) else { return false }
        return pathLooksLikeAgent(path)
    }

    /// 경로를 조각내 `claude`/`codex` 라는 조각이 통째로 있는지 본다.
    /// 문자열 포함이나 접두사로 보면 `claude-pet`(이 앱 자신)까지 에이전트로 걸린다.
    /// 설치 경로들은 어디엔가 이 조각을 꼭 갖고 있다.
    /// `~/.local/share/claude/versions/2.1.274`, `…/Claude/claude-code/…/MacOS/claude`, `…/bin/codex`.
    static func pathLooksLikeAgent(_ path: String) -> Bool {
        path.split(separator: "/").contains { agentNames.contains($0.lowercased()) }
    }

    /// 커널이 들고 있는 짧은 프로세스 이름. 없는 프로세스면 nil.
    static func processName(_ pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return withUnsafeBytes(of: &info.kp_proc.p_comm) { raw in
            guard let base = raw.baseAddress else { return nil }
            return String(cString: base.assumingMemoryBound(to: CChar.self))
        }
    }

    static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }
}
