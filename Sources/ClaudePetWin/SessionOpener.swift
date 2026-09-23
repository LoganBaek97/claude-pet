#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

enum SessionOpener {
    /// 세션이 돌고 있는 앱을 앞으로 가져온다. 아무것도 열지 못하면 false.
    @discardableResult
    static func open(_ agg: Aggregate) -> Bool {
        switch SessionOpenPlanner.plan(for: agg) {
        case .deepLink(let url):
            return shellOpen(url.absoluteString)
        case .activate(let pid, let bundlePath):
            if let pid, activateByPid(pid, bundlePath: bundlePath) { return true }
            if agg.session?.agent == .claude { return openClaudeDesktop() }
            return false
        case .claudeDesktop:
            return openClaudeDesktop()
        case .stay:
            return false
        }
    }

    private static func shellOpen(_ target: String) -> Bool {
        let wide = Array(target.utf16) + [0]
        let result = wide.withUnsafeBufferPointer { buf in
            ShellExecuteW(nil, nil, buf.baseAddress, nil, nil, SW_SHOWNORMAL)
        }
        // ShellExecuteW 는 성공하면 32 보다 큰 HINSTANCE 를 돌려준다.
        return Int(bitPattern: result) > 32
    }

    /// pid 가 살아 있고 그 실행 파일 경로가 bundlePath 와 같으면 앞으로 가져온다.
    private static func activateByPid(_ pid: Int32, bundlePath: String) -> Bool {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(pid)) else {
            // 프로세스가 없다. 실행 파일을 새로 연다.
            return shellOpen(bundlePath)
        }
        CloseHandle(h)
        // 실행 파일 경로 확인 (경로를 슬래시로 통일해 대소문자 무시 비교)
        if let actual = executablePath(pid) {
            let norm1 = actual.replacingOccurrences(of: "\\", with: "/").lowercased()
            let norm2 = bundlePath.replacingOccurrences(of: "\\", with: "/").lowercased()
            guard norm1 == norm2 else { return false }
        }
        // 창 찾기
        var found: HWND?
        var targetPid = DWORD(pid)
        withUnsafeMutablePointer(to: &found) { foundPtr in
            withUnsafeMutablePointer(to: &targetPid) { pidPtr in
                // 두 포인터를 하나의 구조체로 묶어 전달한다.
                var ctx = EnumCtx(targetPid: pidPtr.pointee, result: nil)
                withUnsafeMutablePointer(to: &ctx) { ctxPtr in
                    EnumWindows({ hwnd, lParam -> WindowsBool in
                        guard let hwnd, lParam != 0 else { return true }
                        let ctx = UnsafeMutablePointer<EnumCtx>(bitPattern: Int(lParam))! // LPARAM 은 Int64
                        var wPid: DWORD = 0
                        GetWindowThreadProcessId(hwnd, &wPid)
                        guard wPid == ctx.pointee.targetPid else { return true }
                        // 보이는 최상위 윈도우만 (owner 가 없는 것)
                        guard IsWindowVisible(hwnd), GetWindow(hwnd, UINT(GW_OWNER)) == nil else { return true }
                        ctx.pointee.result = hwnd
                        return false // 찾았으면 중단
                    }, LPARAM(Int(bitPattern: ctxPtr)))
                    found = ctx.result
                }
            }
        }
        guard let wnd = found else { return shellOpen(bundlePath) }
        if IsIconic(wnd) { ShowWindow(wnd, SW_RESTORE) }
        if !SetForegroundWindow(wnd) {
            AllowSetForegroundWindow(DWORD(pid))
            if !SetForegroundWindow(wnd) {
                var fi = FLASHWINFO()
                fi.cbSize = UINT(MemoryLayout<FLASHWINFO>.size)
                fi.hwnd = wnd
                fi.dwFlags = DWORD(FLASHW_ALL | FLASHW_TIMERNOFG)
                fi.uCount = 3
                fi.dwTimeout = 0
                FlashWindowEx(&fi)
            }
        }
        return true
    }

    private struct EnumCtx {
        var targetPid: DWORD
        var result: HWND?
    }

    /// Claude Desktop 의 URL 스킴 핸들러가 있는지 레지스트리에서 본다.
    private static func openClaudeDesktop() -> Bool {
        var key: HKEY?
        let path = "claude\\shell\\open\\command"
        let status = path.withCString(encodedAs: UTF16.self) { p in
            RegOpenKeyExW(HKEY_CLASSES_ROOT, p, 0, DWORD(KEY_QUERY_VALUE), &key)
        }
        if let key { RegCloseKey(key) }
        guard status == ERROR_SUCCESS else { return false }
        return shellOpen("claude://code/continue?session=last&source=desktop_action")
    }

    private static func executablePath(_ pid: Int32) -> String? {
        guard let h = OpenProcess(DWORD(PROCESS_QUERY_LIMITED_INFORMATION), false, DWORD(pid)) else { return nil }
        defer { CloseHandle(h) }
        var buf = [WCHAR](repeating: 0, count: Int(MAX_PATH) + 1)
        var size = DWORD(buf.count)
        guard QueryFullProcessImageNameW(h, 0, &buf, &size) else { return nil }
        return String(decodingCString: buf, as: UTF16.self)
    }
}
#endif
