// Windows 앱 진입점. 지금은 Phase 0 스파이크: 툴체인이 WinSDK 를 링크하고 레이어드 창·트레이 아이콘
// API 를 부를 수 있는지 CI 에서 확인한다. 창이 실제로 뜨는지는 러너에 데스크톱 세션이 있어야 알 수 있어
// 결과를 로그로만 남기고 어떤 경우에도 exit 0 으로 끝낸다. 이후 단계에서 진짜 앱으로 자란다.
#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

private func log(_ message: String) {
    FileHandle.standardError.write(Data("ClaudePetWin: \(message)\n".utf8))
}

private func lastError() -> String { "GetLastError=\(GetLastError())" }

/// 레이어드 창을 하나 만들고 반투명 사각형을 한 번 그린 뒤 닫는다. 반환값은 성공 여부.
private func spikeLayeredWindow() -> Bool {
    let className = Array("ClaudePetSpike".utf16) + [0]
    var wc = WNDCLASSEXW()
    wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
    wc.lpfnWndProc = { hwnd, msg, wParam, lParam in DefWindowProcW(hwnd, msg, wParam, lParam) }
    wc.hInstance = GetModuleHandleW(nil)
    let atom = className.withUnsafeBufferPointer { ptr -> ATOM in
        wc.lpszClassName = ptr.baseAddress
        return RegisterClassExW(&wc)
    }
    guard atom != 0 else { log("RegisterClassExW 실패 \(lastError())"); return false }

    let exStyle = DWORD(WS_EX_LAYERED) | DWORD(WS_EX_TOPMOST) | DWORD(WS_EX_TOOLWINDOW) | DWORD(WS_EX_NOACTIVATE)
    let hwnd = className.withUnsafeBufferPointer { ptr in
        CreateWindowExW(exStyle, ptr.baseAddress, ptr.baseAddress, DWORD(WS_POPUP),
                        100, 100, 192, 208, nil, nil, GetModuleHandleW(nil), nil)
    }
    guard let hwnd else { log("CreateWindowExW 실패 \(lastError())"); return false }
    defer { DestroyWindow(hwnd) }

    // 32bpp premultiplied BGRA DIB 에 반투명 사각형을 채운다.
    let width: Int32 = 192, height: Int32 = 208
    var bmi = BITMAPINFO()
    bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
    bmi.bmiHeader.biWidth = width
    bmi.bmiHeader.biHeight = -height // top-down
    bmi.bmiHeader.biPlanes = 1
    bmi.bmiHeader.biBitCount = 32
    bmi.bmiHeader.biCompression = DWORD(BI_RGB)
    var bits: UnsafeMutableRawPointer?
    let screen = GetDC(nil)
    defer { ReleaseDC(nil, screen) }
    guard let dib = CreateDIBSection(screen, &bmi, UINT(DIB_RGB_COLORS), &bits, nil, 0), let bits else {
        log("CreateDIBSection 실패 \(lastError())"); return false
    }
    defer { DeleteObject(dib) }
    let pixels = bits.assumingMemoryBound(to: UInt8.self)
    for i in 0..<Int(width * height) {
        pixels[i * 4 + 0] = 0x40; pixels[i * 4 + 1] = 0x40; pixels[i * 4 + 2] = 0xC0; pixels[i * 4 + 3] = 0xC0
    }
    let memDC = CreateCompatibleDC(screen)
    defer { DeleteDC(memDC) }
    let old = SelectObject(memDC, dib)
    defer { SelectObject(memDC, old) }

    var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: BYTE(AC_SRC_ALPHA))
    var dst = POINT(x: 100, y: 100)
    var size = SIZE(cx: width, cy: height)
    var src = POINT(x: 0, y: 0)
    guard UpdateLayeredWindow(hwnd, screen, &dst, &size, memDC, &src, 0, &blend, DWORD(ULW_ALPHA)) else {
        log("UpdateLayeredWindow 실패 \(lastError())"); return false
    }
    ShowWindow(hwnd, SW_SHOWNOACTIVATE)
    log("레이어드 창 생성·갱신 성공")
    return true
}

/// 트레이 아이콘을 하나 등록하고 바로 지운다.
private func spikeTrayIcon() -> Bool {
    var nid = NOTIFYICONDATAW()
    nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
    nid.uID = 1
    nid.uFlags = UINT(NIF_ICON | NIF_TIP)
    nid.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: UInt(IDI_APPLICATION))!)
    let tip = Array("Claude Pet".utf16)
    withUnsafeMutablePointer(to: &nid.szTip) { raw in
        raw.withMemoryRebound(to: WCHAR.self, capacity: 128) { dst in
            for (i, ch) in tip.enumerated() { dst[i] = ch }
            dst[tip.count] = 0
        }
    }
    guard Shell_NotifyIconW(DWORD(NIM_ADD), &nid) else { log("Shell_NotifyIconW 실패 \(lastError())"); return false }
    Shell_NotifyIconW(DWORD(NIM_DELETE), &nid)
    log("트레이 아이콘 등록·해제 성공")
    return true
}

/// corelibs Foundation 이 Windows 에서 경로를 어떤 모양으로 주는지 기록한다. `URL.path` 가 `C:/…` 인지
/// `/C:/…` 인지에 따라 Paths 계층에 정규화가 필요할 수 있다. 파일 왕복(쓰기·읽기·교체·삭제)도 확인한다.
private func spikeFoundationFacts() -> Bool {
    let sample = URL(fileURLWithPath: #"C:\Users\x\a.json"#)
    log("URL.path 모양: \(sample.path)  lastPathComponent=\(sample.lastPathComponent)")
    log("home: \(FileManager.default.homeDirectoryForCurrentUser.path)")
    log("LOCALAPPDATA: \(ProcessInfo.processInfo.environment["LOCALAPPDATA"] ?? "(없음)")")
    log("Core 상태 디렉터리: \(Paths.stateDirectory.path)")
    let fm = FileManager.default
    let dir = fm.temporaryDirectory.appendingPathComponent("claude-pet-spike-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
    do {
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("s.json")
        let tmp = dir.appendingPathComponent("s.json.tmp")
        try Data("{\"a\":1}".utf8).write(to: tmp, options: .atomic)
        try Data("{\"a\":0}".utf8).write(to: file, options: .atomic)
        _ = try fm.replaceItemAt(file, withItemAt: tmp)
        guard let back = fm.contents(atPath: file.path), String(decoding: back, as: UTF8.self) == "{\"a\":1}" else {
            log("파일 왕복 실패: 내용 불일치"); return false
        }
        let names = try fm.contentsOfDirectory(atPath: dir.path)
        log("contentsOfDirectory: \(names)")
        try fm.removeItem(at: dir)
        log("파일 왕복 성공")
        return true
    } catch {
        log("파일 왕복 실패: \(error)")
        return false
    }
}

let args = CommandLine.arguments.dropFirst()
if args.contains("--spike") {
    let facts = spikeFoundationFacts()
    let window = spikeLayeredWindow()
    let tray = spikeTrayIcon()
    log("spike 결과 foundation=\(facts) window=\(window) tray=\(tray)")
    exit(0)
}
log("아직 구현되지 않았습니다. --spike 로 툴체인 점검만 할 수 있습니다.")
exit(0)
#else
// Windows 전용 실행 파일. 다른 플랫폼에서는 빈 진입점만 남겨 패키지 전체 빌드를 막지 않는다.
#endif
