#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

/// 시스템 트레이 아이콘과 컨텍스트 메뉴.
final class TrayIcon {
    static let className = "ClaudePetTray"
    static let callbackMsg = UINT(WM_APP + 1)

    // 메뉴 항목 ID
    private enum MenuID: Int {
        case toggleVisible = 100
        case toggleBubble
        case petSelectBase = 200  // 200 + index
        case downloadDefaultPet = 299
        case scaleSmall = 300
        case scaleMedium = 301
        case scaleLarge = 302
        case loginItem = 400
        case ignoreReducedMotion = 401
        case hookInstallBase = 500 // 500 + agent index
        case refresh = 600
        case quit = 700
    }

    private let hiddenHwnd: HWND
    private let hInstance: HINSTANCE?
    private var iconAdded = false
    private var currentIcon: HICON?
    /// TaskbarCreated 등록 메시지. 탐색기가 재시작하면 트레이를 다시 등록한다.
    private let taskbarCreatedMsg: UINT

    init() {
        hInstance = GetModuleHandleW(nil)

        let nameW = Array(Self.className.utf16) + [0]
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.lpfnWndProc = trayWndProc
        wc.hInstance = hInstance
        nameW.withUnsafeBufferPointer { ptr in
            wc.lpszClassName = ptr.baseAddress
            RegisterClassExW(&wc)
        }

        hiddenHwnd = nameW.withUnsafeBufferPointer { ptr in
            CreateWindowExW(0, ptr.baseAddress, nil, 0,
                            0, 0, 0, 0, nil, nil, hInstance, nil)!
        }

        let tbMsg = Array("TaskbarCreated".utf16) + [0]
        taskbarCreatedMsg = tbMsg.withUnsafeBufferPointer { RegisterWindowMessageW($0.baseAddress) }
    }

    deinit {
        removeIcon()
        DestroyWindow(hiddenHwnd)
    }

    func bindApp(_ app: App) {
        let ptr = Unmanaged.passUnretained(app).toOpaque()
        SetWindowLongPtrW(hiddenHwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: ptr)))
    }

    // MARK: - 아이콘

    func addIcon(frame: SpriteFrame?, hasWarning: Bool) {
        let icon = makeIcon(from: frame, hasWarning: hasWarning)
        var nid = NOTIFYICONDATAW()
        nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        nid.hWnd = hiddenHwnd
        nid.uID = 1
        nid.uFlags = UINT(NIF_MESSAGE | NIF_ICON | NIF_TIP)
        nid.uCallbackMessage = Self.callbackMsg
        nid.hIcon = icon
        let tip = Array("Claude Pet".utf16)
        withUnsafeMutablePointer(to: &nid.szTip) { raw in
            raw.withMemoryRebound(to: WCHAR.self, capacity: 128) { dst in
                for (i, ch) in tip.enumerated() where i < 127 { dst[i] = ch }
                dst[min(tip.count, 127)] = 0
            }
        }
        if iconAdded {
            Shell_NotifyIconW(DWORD(NIM_MODIFY), &nid)
        } else {
            Shell_NotifyIconW(DWORD(NIM_ADD), &nid)
            iconAdded = true
        }
        if let old = currentIcon { DestroyIcon(old) }
        currentIcon = icon
    }

    func removeIcon() {
        guard iconAdded else { return }
        var nid = NOTIFYICONDATAW()
        nid.cbSize = DWORD(MemoryLayout<NOTIFYICONDATAW>.size)
        nid.hWnd = hiddenHwnd
        nid.uID = 1
        Shell_NotifyIconW(DWORD(NIM_DELETE), &nid)
        iconAdded = false
        if let icon = currentIcon { DestroyIcon(icon); currentIcon = nil }
    }

    /// SpriteFrame 의 첫 idle 프레임을 16/32px 아이콘으로 변환한다.
    private func makeIcon(from frame: SpriteFrame?, hasWarning: Bool) -> HICON {
        let size = Int(GetSystemMetrics(SM_CXSMICON)) // 보통 16
        guard let frame, frame.width > 0, frame.height > 0 else {
            // 기본 앱 아이콘
            return LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: UInt(32512))!)  // IDI_APPLICATION = 32512
        }
        // 최근접 보간으로 축소
        var surface = PixelSurface(width: size, height: size)
        surface.blitSpriteFrame(frame, dstX: 0, dstY: 0, dstW: size, dstH: size)

        // 경고 점 (우하단 노란색 4x4)
        if hasWarning {
            let ds = max(3, size / 4)
            surface.fillRect(x: size - ds, y: size - ds, w: ds, h: ds,
                            r: 255, g: 200, b: 0, a: 255)
        }

        return createIconFromSurface(surface, size: size)
    }

    private func createIconFromSurface(_ surface: PixelSurface, size: Int) -> HICON {
        let screenDC = GetDC(nil)
        defer { ReleaseDC(nil, screenDC) }
        // 컬러 비트맵 (BGRA)
        guard let (colorBmp, bits) = Surface.createDIB(width: Int32(size), height: Int32(size), screenDC: screenDC) else {
            return LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: UInt(32512))!)
        }
        Surface.copy(surface, to: bits)
        // 마스크 비트맵 (monochrome — 0 = 불투명, 1 = 투명)
        let maskBmp = CreateBitmap(Int32(size), Int32(size), 1, 1, nil)

        var ii = ICONINFO()
        ii.fIcon = true
        ii.xHotspot = 0
        ii.yHotspot = 0
        ii.hbmMask = maskBmp
        ii.hbmColor = colorBmp
        let icon = CreateIconIndirect(&ii)
        DeleteObject(colorBmp)
        DeleteObject(maskBmp)
        return icon ?? LoadIconW(nil, UnsafePointer<WCHAR>(bitPattern: UInt(32512))!)
    }

    // MARK: - 메뉴

    func showMenu(app: App) {
        let menu = CreatePopupMenu()
        guard let menu else { return }
        defer { DestroyMenu(menu) }

        if let w = app.warning {
            appendItem(menu, id: 0, title: w, enabled: false)
            AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
        }

        appendItem(menu, id: MenuID.toggleVisible.rawValue,
                   title: app.overlay.isVisible ? "펫 숨기기" : "펫 보이기")
        appendItem(menu, id: MenuID.toggleBubble.rawValue,
                   title: app.controller.isBubbleHidden ? "대화창 켜기" : "대화창 끄기")

        // 펫 선택 서브메뉴
        let petMenu = CreatePopupMenu()!
        for (i, pet) in app.availablePets().enumerated() {
            let title = pet.source == .codex ? "\(pet.manifest.displayName) (codex)" : pet.manifest.displayName
            let id = MenuID.petSelectBase.rawValue + i
            appendItem(petMenu, id: id, title: title, checked: pet.id == app.controller.pet?.id)
        }
        if app.availablePets().allSatisfy({ $0.source == .builtin }) {
            AppendMenuW(petMenu, UINT(MF_SEPARATOR), 0, nil)
            appendItem(petMenu, id: MenuID.downloadDefaultPet.rawValue, title: "펫 받기 (guga)…")
        }
        let petTitle = Array("펫 선택".utf16) + [0]
        petTitle.withUnsafeBufferPointer { ptr in
            AppendMenuW(menu, UINT(MF_POPUP), UINT_PTR(Int(bitPattern: OpaquePointer(petMenu))), ptr.baseAddress)
        }

        // 크기 서브메뉴
        let sizeMenu = CreatePopupMenu()!
        for (title, id, s) in [("작게", MenuID.scaleSmall.rawValue, 0.35),
                                 ("보통", MenuID.scaleMedium.rawValue, 0.5),
                                 ("크게", MenuID.scaleLarge.rawValue, 1.0)] {
            appendItem(sizeMenu, id: id, title: title, checked: app.prefs.scale == s)
        }
        let sizeTitle = Array("크기".utf16) + [0]
        sizeTitle.withUnsafeBufferPointer { ptr in
            AppendMenuW(menu, UINT(MF_POPUP), UINT_PTR(Int(bitPattern: OpaquePointer(sizeMenu))), ptr.baseAddress)
        }

        AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)

        // 로그인 시 실행
        appendItem(menu, id: MenuID.loginItem.rawValue, title: "로그인 시 실행",
                   checked: LoginItem.isEnabled)

        // 동작 줄이기 무시
        if app.controller.systemReducedMotion {
            appendItem(menu, id: MenuID.ignoreReducedMotion.rawValue,
                       title: "동작 줄이기 무시하고 움직이기",
                       checked: app.controller.ignoresReducedMotion)
        }

        // 훅 상태
        for (i, agent) in Agent.installTargets().enumerated() {
            let installed = HooksInstaller.isInstalled(file: agent.settingsFile)
            if installed {
                appendItem(menu, id: 0, title: "\(agent.displayName) 훅: 설치됨", enabled: false)
            } else {
                appendItem(menu, id: MenuID.hookInstallBase.rawValue + i,
                           title: "\(agent.displayName) 훅 설치하기…")
            }
        }
        if Agent.codex.isAvailable(home: Paths.home) {
            // Codex 줄은 위에서 이미 처리됨
        }

        appendItem(menu, id: MenuID.refresh.rawValue, title: "상태 다시 읽기")
        AppendMenuW(menu, UINT(MF_SEPARATOR), 0, nil)
        appendItem(menu, id: MenuID.quit.rawValue, title: "종료")

        SetForegroundWindow(hiddenHwnd)
        var pt = POINT()
        GetCursorPos(&pt)
        TrackPopupMenuEx(menu, UINT(TPM_RIGHTBUTTON), pt.x, pt.y, hiddenHwnd, nil)
        PostMessageW(hiddenHwnd, UINT(WM_NULL), 0, 0)
    }

    private func appendItem(_ menu: HMENU, id: Int, title: String, enabled: Bool = true, checked: Bool = false) {
        var flags = UINT(MF_STRING)
        if !enabled { flags |= UINT(MF_GRAYED) }
        if checked { flags |= UINT(MF_CHECKED) }
        let wide = Array(title.utf16) + [0]
        wide.withUnsafeBufferPointer { ptr in
            AppendMenuW(menu, flags, UINT_PTR(id), ptr.baseAddress)
        }
    }

    // MARK: - 메뉴 명령 처리

    func handleCommand(_ id: Int, app: App) {
        switch id {
        case MenuID.toggleVisible.rawValue: app.toggleVisible()
        case MenuID.toggleBubble.rawValue: app.toggleBubble()
        case MenuID.downloadDefaultPet.rawValue: app.downloadDefaultPet()
        case MenuID.scaleSmall.rawValue: app.setScale(0.35)
        case MenuID.scaleMedium.rawValue: app.setScale(0.5)
        case MenuID.scaleLarge.rawValue: app.setScale(1.0)
        case MenuID.loginItem.rawValue: app.toggleLoginItem()
        case MenuID.ignoreReducedMotion.rawValue: app.toggleIgnoreReducedMotion()
        case MenuID.refresh.rawValue: app.refresh()
        case MenuID.quit.rawValue: PostQuitMessage(0)
        default:
            if id >= MenuID.petSelectBase.rawValue && id < MenuID.downloadDefaultPet.rawValue {
                let index = id - MenuID.petSelectBase.rawValue
                let pets = app.availablePets()
                if index < pets.count { app.selectPet(id: pets[index].id) }
            } else if id >= MenuID.hookInstallBase.rawValue && id < MenuID.hookInstallBase.rawValue + 10 {
                let index = id - MenuID.hookInstallBase.rawValue
                let targets = Agent.installTargets()
                if index < targets.count { app.installHooks(agent: targets[index]) }
            }
        }
    }

    /// 트레이 콜백과 메시지를 처리한다.
    func handleMessage(_ hwnd: HWND, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM,
                       app: App) -> LRESULT? {
        if msg == taskbarCreatedMsg {
            // 탐색기가 재시작함. 아이콘을 다시 등록한다.
            iconAdded = false
            let frame = app.controller.sheet?.frames(for: .idle).first
            addIcon(frame: frame, hasWarning: app.warning != nil)
            return 0
        }
        if msg == Self.callbackMsg {
            let action = Int16(truncatingIfNeeded: lParam & 0xFFFF) // LOWORD
            switch Int32(action) {
            case WM_RBUTTONUP, WM_CONTEXTMENU:
                showMenu(app: app)
            case WM_LBUTTONDBLCLK:
                if !app.overlay.isVisible { app.toggleVisible() }
            default: break
            }
            return 0
        }
        if msg == UINT(WM_COMMAND) {
            let cmdId = Int(wParam & 0xFFFF)  // LOWORD
            handleCommand(cmdId, app: app)
            return 0
        }
        return nil
    }
}

// MARK: - 윈도우 프로시저

private let trayWndProc: WNDPROC = { hwnd, msg, wParam, lParam in
    guard let hwnd else { return DefWindowProcW(hwnd, msg, wParam, lParam) }
    let raw = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: Int(raw)) else { // LONG_PTR 은 Int64
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
    let app = Unmanaged<App>.fromOpaque(ptr).takeUnretainedValue()
    if let result = app.tray.handleMessage(hwnd, msg, wParam, lParam, app: app) {
        return result
    }
    return DefWindowProcW(hwnd, msg, wParam, lParam)
}
#endif
