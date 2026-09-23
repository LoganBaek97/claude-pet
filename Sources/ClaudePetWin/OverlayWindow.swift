#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

/// 펫과 말풍선을 합성해 보여 주는 레이어드 윈도우.
///
/// WS_EX_LAYERED + UpdateLayeredWindow 로 픽셀별 알파를 쓴다.
/// 투명 픽셀은 자동으로 클릭을 통과시키고, WM_NCHITTEST 로도 확인한다.
final class OverlayWindow {
    static let className = "ClaudePetOverlay"
    static let petBubbleGap: Int = 8
    static let margin: Int = 16

    let hwnd: HWND
    private let hInstance: HINSTANCE?

    /// 현재 DIB 와 크기.
    private var dibBitmap: HBITMAP?
    private var dibBits: UnsafeMutablePointer<UInt8>?
    private var dibWidth: Int = 0
    private var dibHeight: Int = 0

    /// 마지막으로 그린 표면. WM_NCHITTEST 에서 알파를 확인할 때 쓴다.
    private var lastSurface: PixelSurface?

    /// 드래그 상태.
    private var dragStart: POINT?
    private var windowStartX: Int32 = 0
    private var windowStartY: Int32 = 0
    private var lastCursor: POINT?
    private var dragged = false

    init() {
        hInstance = GetModuleHandleW(nil)

        let classNameW = Array(Self.className.utf16) + [0]
        var wc = WNDCLASSEXW()
        wc.cbSize = UINT(MemoryLayout<WNDCLASSEXW>.size)
        wc.lpfnWndProc = overlayWndProc
        wc.hInstance = hInstance
        wc.hCursor = LoadCursorW(nil, UnsafePointer<WCHAR>(bitPattern: 32512)) // IDC_ARROW 는 매크로라 Swift 에 안 들어온다
        classNameW.withUnsafeBufferPointer { ptr in
            wc.lpszClassName = ptr.baseAddress
            RegisterClassExW(&wc)
        }

        let exStyle = DWORD(WS_EX_LAYERED) | DWORD(WS_EX_TOPMOST) | DWORD(WS_EX_TOOLWINDOW) | DWORD(WS_EX_NOACTIVATE)
        hwnd = classNameW.withUnsafeBufferPointer { ptr in
            CreateWindowExW(exStyle, ptr.baseAddress, ptr.baseAddress, DWORD(WS_POPUP),
                            0, 0, 1, 1, nil, nil, hInstance, nil)!
        }
    }

    deinit {
        if let dibBitmap { DeleteObject(dibBitmap) }
        DestroyWindow(hwnd)
    }

    /// GWLP_USERDATA 에 App 포인터를 등록한다. CreateWindowExW 뒤에 한 번 부른다.
    func bindApp(_ app: App) {
        let ptr = Unmanaged.passUnretained(app).toOpaque()
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, LONG_PTR(Int(bitPattern: ptr)))
    }

    // MARK: - 표시

    func show() { ShowWindow(hwnd, SW_SHOWNOACTIVATE) }
    func hide() { ShowWindow(hwnd, SW_HIDE) }
    var isVisible: Bool { IsWindowVisible(hwnd) }

    // MARK: - 위치

    /// 기본 위치: 주 모니터 작업 영역의 우하단.
    func placeDefault() {
        var pt = POINT(x: 0, y: 0)
        let mon = MonitorFromPoint(pt, DWORD(MONITOR_DEFAULTTOPRIMARY))
        var mi = MONITORINFO()
        mi.cbSize = DWORD(MemoryLayout<MONITORINFO>.size)
        GetMonitorInfoW(mon, &mi)
        let work = mi.rcWork
        let x = Int(work.right) - dibWidth - Self.margin
        let y = Int(work.bottom) - dibHeight - Self.margin
        SetWindowPos(hwnd, nil, Int32(x), Int32(y), 0, 0,
                     UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
    }

    /// 저장된 위치를 쓰되 화면 밖이면 기본 위치로.
    func place(using prefs: Preferences) {
        guard let saved = prefs.position else { return placeDefault() }
        let candidate = POINT(x: Int32(saved.x), y: Int32(saved.y))
        // 어떤 모니터에도 들어가는지 확인
        if monitorContains(x: Int(candidate.x), y: Int(candidate.y), w: dibWidth, h: dibHeight) {
            SetWindowPos(hwnd, nil, candidate.x, candidate.y, 0, 0,
                         UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
        } else {
            placeDefault()
        }
    }

    private func monitorContains(x: Int, y: Int, w: Int, h: Int) -> Bool {
        var found = false
        var rect = RECT(left: Int32(x), top: Int32(y), right: Int32(x + w), bottom: Int32(y + h))
        withUnsafeMutablePointer(to: &rect) { _ in
            let pt = POINT(x: Int32(x + w / 2), y: Int32(y + h / 2))
            let mon = MonitorFromPoint(pt, DWORD(MONITOR_DEFAULTTONULL))
            found = mon != nil
        }
        return found
    }

    func savePosition(to prefs: Preferences) {
        var rc = RECT()
        GetWindowRect(hwnd, &rc)
        prefs.position = CGPoint(x: CGFloat(rc.left), y: CGFloat(rc.top))
    }

    // MARK: - 렌더링

    /// 펫 프레임과 말풍선을 합성해 레이어드 윈도우를 갱신한다.
    func render(petFrame: SpriteFrame?, bubbleSurface: PixelSurface?, bubbleHeight: Int,
                scale: Double) {
        let (petW, petH) = Surface.scaledSize(scale: scale)
        let totalW = max(petW, BubbleRenderer.cardWidth + 24)
        let gap = bubbleHeight > 0 ? Self.petBubbleGap : 0
        let totalH = petH + gap + bubbleHeight

        ensureDIB(width: totalW, height: totalH)

        var surface = PixelSurface(width: totalW, height: totalH)

        // 말풍선 (위쪽)
        if let bs = bubbleSurface {
            let bx = max(0, (totalW - bs.width) / 2)
            surface.compositeOver(bs, dstX: bx, dstY: 0)
        }

        // 펫 (아래쪽)
        if let frame = petFrame {
            let petX = (totalW - petW) / 2
            let petY = bubbleHeight + gap
            surface.blitSpriteFrame(frame, dstX: petX, dstY: petY, dstW: petW, dstH: petH)
        }

        lastSurface = surface
        guard let bits = dibBits else { return }
        Surface.copy(surface, to: bits)

        let screenDC = GetDC(nil)
        let memDC = CreateCompatibleDC(screenDC)
        let old = SelectObject(memDC, dibBitmap)
        defer { SelectObject(memDC, old); DeleteDC(memDC); ReleaseDC(nil, screenDC) }

        var blend = BLENDFUNCTION(BlendOp: BYTE(AC_SRC_OVER), BlendFlags: 0,
                                  SourceConstantAlpha: 255, AlphaFormat: BYTE(AC_SRC_ALPHA))
        var rc = RECT()
        GetWindowRect(hwnd, &rc)
        // 펫의 하단 고정: 창이 위로 자란다
        let newTop = rc.bottom - Int32(totalH)
        var dst = POINT(x: rc.left, y: newTop)
        var size = SIZE(cx: Int32(totalW), cy: Int32(totalH))
        var src = POINT(x: 0, y: 0)
        UpdateLayeredWindow(hwnd, screenDC, &dst, &size, memDC, &src, 0, &blend, DWORD(ULW_ALPHA))
        // 크기가 바뀌면 위치도 갱신
        SetWindowPos(hwnd, nil, rc.left, newTop, Int32(totalW), Int32(totalH),
                     UINT(SWP_NOZORDER | SWP_NOACTIVATE))
    }

    private func ensureDIB(width: Int, height: Int) {
        guard width != dibWidth || height != dibHeight else { return }
        if let old = dibBitmap { DeleteObject(old) }
        let screenDC = GetDC(nil)
        defer { ReleaseDC(nil, screenDC) }
        if let result = Surface.createDIB(width: Int32(width), height: Int32(height), screenDC: screenDC) {
            dibBitmap = result.hBitmap
            dibBits = result.bits
        }
        dibWidth = width
        dibHeight = height
    }

    /// 펫 영역의 스크린 좌표 사각형.
    func petScreenRect(scale: Double, bubbleHeight: Int) -> RECT {
        let (petW, petH) = Surface.scaledSize(scale: scale)
        var rc = RECT()
        GetWindowRect(hwnd, &rc)
        let petX = Int(rc.left) + (dibWidth - petW) / 2
        let petY = Int(rc.top) + bubbleHeight + (bubbleHeight > 0 ? Self.petBubbleGap : 0)
        return RECT(left: Int32(petX), top: Int32(petY), right: Int32(petX + petW), bottom: Int32(petY + petH))
    }

    // MARK: - 마우스

    func mouseDown(screenPt: POINT) {
        SetCapture(hwnd)
        dragStart = screenPt
        var rc = RECT()
        GetWindowRect(hwnd, &rc)
        windowStartX = rc.left
        windowStartY = rc.top
        lastCursor = screenPt
        dragged = false
    }

    /// 드래그 중 호출. 반환값은 (dx, dy) 이전 커서 위치로부터의 변위.
    func mouseMove(screenPt: POINT) -> (dx: Double, dy: Double, isDrag: Bool)? {
        guard let start = dragStart else { return nil }
        let totalDx = screenPt.x - start.x
        let totalDy = screenPt.y - start.y
        if abs(totalDx) > 4 || abs(totalDy) > 4 { dragged = true }
        guard dragged else { return nil }
        SetWindowPos(hwnd, nil, windowStartX + totalDx, windowStartY + totalDy, 0, 0,
                     UINT(SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE))
        let prev = lastCursor ?? screenPt
        lastCursor = screenPt
        return (dx: Double(screenPt.x - prev.x), dy: Double(screenPt.y - prev.y), isDrag: true)
    }

    /// 마우스 업 처리. 반환값: true 이면 드래그 끝, false 이면 클릭.
    func mouseUp() -> Bool {
        ReleaseCapture()
        let wasDrag = dragged
        dragStart = nil
        lastCursor = nil
        dragged = false
        return wasDrag
    }

    /// WM_NCHITTEST: 알파가 0 인 픽셀은 HTTRANSPARENT.
    func hitTest(screenX: Int32, screenY: Int32) -> LRESULT {
        var rc = RECT()
        GetWindowRect(hwnd, &rc)
        let lx = Int(screenX - rc.left)
        let ly = Int(screenY - rc.top)
        if let s = lastSurface, s.alpha(atX: lx, y: ly) == 0 {
            return LRESULT(HTTRANSPARENT)
        }
        return LRESULT(HTCLIENT)
    }
}

// MARK: - 윈도우 프로시저

/// @convention(c) — 캡처 없음.
private let overlayWndProc: WNDPROC = { hwnd, msg, wParam, lParam in
    guard let hwnd else { return DefWindowProcW(hwnd, msg, wParam, lParam) }
    let raw = GetWindowLongPtrW(hwnd, GWLP_USERDATA)
    guard raw != 0, let ptr = UnsafeMutableRawPointer(bitPattern: UInt(bitPattern: raw)) else {
        return DefWindowProcW(hwnd, msg, wParam, lParam)
    }
    let app = Unmanaged<App>.fromOpaque(ptr).takeUnretainedValue()
    return app.handleOverlayMessage(hwnd, msg, wParam, lParam)
}
#endif
