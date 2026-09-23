#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - 유틸

func log(_ message: String) {
    FileHandle.standardError.write(Data("ClaudePetWin: \(message)\n".utf8))
}

private func lastError() -> String { "GetLastError=\(GetLastError())" }

// MARK: - DPI 인식

private func setDpiAwareness() {
    // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = ((DPI_AWARENESS_CONTEXT)-4)
    // SetProcessDpiAwarenessContext 가 가져와지지 않을 수 있으므로 동적 로드한다.
    let user32 = Array("user32.dll".utf16) + [0]
    let fnName = "SetProcessDpiAwarenessContext"
    if let mod = user32.withUnsafeBufferPointer({ LoadLibraryW($0.baseAddress) }) {
        typealias Fn = @convention(c) (UnsafeMutableRawPointer?) -> WindowsBool
        if let raw = GetProcAddress(mod, fnName) {
            let fn = unsafeBitCast(raw, to: Fn.self)
            _ = fn(UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: Int(-4))))
        } else {
            SetProcessDPIAware()
        }
        FreeLibrary(mod)
    } else {
        SetProcessDPIAware()
    }
}

// MARK: - 단일 인스턴스

private func acquireMutex() -> Bool {
    let name = Array("Local\\ClaudePetWin".utf16) + [0]
    let handle = name.withUnsafeBufferPointer { buf in
        CreateMutexW(nil, true, buf.baseAddress)
    }
    if GetLastError() == DWORD(ERROR_ALREADY_EXISTS) {
        if let handle { CloseHandle(handle) }
        return false
    }
    // 핸들을 닫지 않는다: 프로세스가 끝날 때 OS 가 회수한다.
    return handle != nil
}

// MARK: - --spike (Phase 0 게이트, 기존 코드)

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
    let width: Int32 = 192, height: Int32 = 208
    var bmi = BITMAPINFO()
    bmi.bmiHeader.biSize = DWORD(MemoryLayout<BITMAPINFOHEADER>.size)
    bmi.bmiHeader.biWidth = width
    bmi.bmiHeader.biHeight = -height
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

private func spikeTrayIcon() -> Bool {
    var nid = NOTIFYICONDATAW()
    nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
    nid.uID = 1
    nid.uFlags = UINT(NIF_ICON | NIF_TIP)
    nid.hIcon = LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: UInt(32512))!)  // IDI_APPLICATION
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
        try fm.replaceItemAtomically(file, with: tmp) // corelibs Windows 에는 replaceItemAt 이 없다
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

// MARK: - --self-test

private func selfTest() -> Int32 {
    log("=== self-test 시작 ===")
    var failures: Int32 = 0

    // 1. 내장 펫 디코딩
    let exe = URL(fileURLWithPath: CommandLine.arguments[0])
    let builtinDir = BundleLayout.builtinPetDirectory(executable: exe)
    log("내장 펫 디렉터리: \(builtinDir.path)")

    var pet: InstalledPet?
    if let p = PetLibrary.load(directory: builtinDir, source: .builtin) {
        pet = p
    } else {
        // CI 는 저장소 루트에서 swift run 하므로 Resources/pets/default 가 cwd 기준으로 있을 수 있다.
        let cwdFallback = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/pets/default", isDirectory: true)
        log("내장 펫 폴백: \(cwdFallback.path)")
        pet = PetLibrary.load(directory: cwdFallback, source: .builtin)
    }

    if let pet {
        log("펫 발견: \(pet.manifest.displayName)")
        do {
            let sheet = try SpriteSheet(contentsOf: pet.spritesheetURL, spriteVersion: pet.manifest.spriteVersion)
            for row in SpriteRow.allCases {
                let count = sheet.frameCount(for: row)
                if count < 1 {
                    log("FAIL: \(row) 프레임 0 개")
                    failures += 1
                } else {
                    log("ok: \(row) 프레임 \(count) 개")
                }
            }
            if sheet.frameCount(for: .idle) < 1 {
                log("FAIL: idle 프레임 부족")
                failures += 1
            }

            // 2. Surface 합성
            let frame = sheet.frames(for: .idle)[0]
            var surface = PixelSurface(width: 96, height: 104)
            surface.blitSpriteFrame(frame, dstX: 0, dstY: 0, dstW: 96, dstH: 104)
            if surface.hasVisiblePixels {
                log("ok: Surface 합성 성공 (0.5 스케일)")
            } else {
                log("FAIL: Surface 에 보이는 픽셀 없음")
                failures += 1
            }
        } catch {
            log("FAIL: 시트 디코딩 실패: \(error)")
            failures += 1
        }
    } else {
        log("FAIL: 내장 펫을 찾지 못함")
        failures += 1
    }

    // 3. 말풍선 렌더
    let s1 = SessionState(sessionId: "test-1", state: .waiting, event: "PermissionRequest", tool: "Bash",
                          cwd: "/tmp/project", ts: Date().timeIntervalSince1970)
    let s2 = SessionState(sessionId: "test-2", state: .running, event: "PreToolUse", tool: "Edit",
                          cwd: "/tmp/other", ts: Date().timeIntervalSince1970 - 60)
    let sum1 = SessionSummary(session: s1, state: .waiting)
    let sum2 = SessionSummary(session: s2, state: .running)
    let agg = Aggregate(state: .waiting, session: s1, waitingCount: 1, liveSessionCount: 2,
                        sessions: [sum1, sum2])
    let renderer = BubbleRenderer()
    if let result = renderer.render(aggregate: agg, surfaceWidth: 280) {
        if result.surface.hasVisiblePixels {
            log("ok: 말풍선 렌더 성공 (높이 \(result.totalHeight))")
        } else {
            log("FAIL: 말풍선 렌더에 보이는 픽셀 없음")
            failures += 1
        }
    } else {
        log("FAIL: 말풍선 렌더 nil 반환")
        failures += 1
    }

    // 4. StateWatcher refresh (빈 디렉터리 — 오류 없이 돌아야 한다)
    let stateDir: URL
    if let env = ProcessInfo.processInfo.environment["CLAUDE_PET_STATE_DIR"], !env.isEmpty {
        stateDir = URL(fileURLWithPath: env, isDirectory: true)
    } else {
        stateDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-pet-selftest-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
    }
    var watcherAgg: Aggregate?
    let watcher = StateWatcher(store: StateStore(directory: stateDir)) { agg in watcherAgg = agg }
    watcher.refresh(force: true)
    log("ok: StateWatcher refresh 완료 (sessions=\(watcherAgg?.liveSessionCount ?? 0))")

    // 5. UI 테스트: 오버레이 창 생성 (러너에 데스크톱이 없을 수도 있지만 있으면 확인)
    log("--- UI 테스트 ---")
    do {
        let overlay = OverlayWindow()
        overlay.show()
        if overlay.isVisible {
            log("ok: OverlayWindow 생성·표시 성공")
        } else {
            log("FAIL: OverlayWindow 표시 실패")
            failures += 1
        }
        // 잠시 대기 후 파괴
        Sleep(500)
        overlay.hide()
        log("ok: OverlayWindow 숨기기 성공")
    }

    // 트레이: 실패해도 경고만 (탐색기가 없을 수 있다)
    let trayOk = spikeTrayIcon()
    if trayOk {
        log("ok: 트레이 아이콘 테스트 성공")
    } else {
        log("WARN: 트레이 아이콘 테스트 실패 (탐색기 없음?) — \(lastError())")
        // 경고이지 실패가 아니다
    }

    log("=== self-test 끝: 실패 \(failures) 건 ===")
    return failures
}

// MARK: - 진입점

let args = Set(CommandLine.arguments.dropFirst())

if args.contains("--spike") {
    let facts = spikeFoundationFacts()
    let window = spikeLayeredWindow()
    let tray = spikeTrayIcon()
    log("spike 결과 foundation=\(facts) window=\(window) tray=\(tray)")
    exit(0)
}

if args.contains("--self-test") {
    setDpiAwareness()
    SpriteDecoders.default = WICDecoder.self
    let failures = selfTest()
    exit(failures)
}

// 정상 앱 실행
setDpiAwareness()

guard acquireMutex() else {
    log("이미 실행 중인 인스턴스가 있습니다.")
    exit(0)
}

SpriteDecoders.default = WICDecoder.self

let app = App()
app.run()

var msg = MSG()
while GetMessageW(&msg, nil, 0, 0) != 0 {
    TranslateMessage(&msg)
    DispatchMessageW(&msg)
}

app.tray.removeIcon()

#else
// Windows 전용 실행 파일. 다른 플랫폼에서는 빈 진입점만 남겨 패키지 전체 빌드를 막지 않는다.
#endif
