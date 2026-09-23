#if os(Windows)
import ClaudePetCore
import Foundation
import WinSDK

/// Windows 앱 전체를 묶는 오케스트레이터. macOS 의 AppDelegate 에 대응한다.
final class App {
    let prefs = Preferences.shared
    let executable = URL(fileURLWithPath: CommandLine.arguments[0])
    let controller = PetController()
    let overlay: OverlayWindow
    let tray: TrayIcon
    var watcher: StateWatcher?
    var warning: String? {
        didSet { updateTrayIcon() }
    }
    /// 설정 변경 신호 파일의 마지막 타임스탬프.
    private var lastPrefsSignal: TimeInterval?
    /// 호버 판정용 마지막 마우스 위치.
    private var wasHovered = false

    /// 훅이 빠진 에이전트.
    var missingHookAgents: [Agent] {
        Agent.installTargets().filter { !HooksInstaller.isInstalled(file: $0.settingsFile) }
    }

    init() {
        overlay = OverlayWindow()
        tray = TrayIcon()
    }

    func run() {
        overlay.bindApp(self)
        tray.bindApp(self)
        controller.overlayHwnd = UnsafeMutableRawPointer(overlay.hwnd)

        controller.onLayoutChange = { [weak self] in self?.layout() }
        controller.onOpenFailed = { [weak self] in self?.warning = "세션이 돌고 있는 앱을 찾지 못했습니다" }
        controller.onRender = { [weak self] in self?.render() }

        controller.isBubbleHidden = prefs.isBubbleHidden
        controller.ignoresReducedMotion = prefs.ignoresReducedMotion
        readSystemReducedMotion()
        loadSelectedPet()

        watcher = StateWatcher(store: StateStore(directory: Paths.stateDirectory)) { [weak self] agg in
            self?.controller.apply(agg)
        }

        overlay.placeDefault()
        overlay.place(using: prefs)

        if !prefs.isHidden {
            overlay.show()
            controller.start()
        }

        updateTrayIcon()
        render()

        // 1초 틱 타이머 (상태 폴링, 설정 변경 확인)
        SetTimer(overlay.hwnd, TICK_TIMER_ID, 1000, nil)
        // 호버 타이머 (50ms)
        SetTimer(overlay.hwnd, HOVER_TIMER_ID, 50, nil)

        promptForHooksIfNeeded()
        let missing = missingHookAgents
        if warning == nil && !missing.isEmpty {
            warning = missing.map(\.displayName).joined(separator: "·") + " 훅이 설치되지 않았습니다"
        }
    }

    // MARK: - 메시지 핸들링

    func handleOverlayMessage(_ hwnd: HWND, _ msg: UINT, _ wParam: WPARAM, _ lParam: LPARAM) -> LRESULT {
        switch Int32(msg) {
        case WM_TIMER:
            handleTimer(UINT_PTR(wParam))
            return 0
        case WM_NCHITTEST:
            let x = Int16(truncatingIfNeeded: lParam & 0xFFFF)        // GET_X_LPARAM
            let y = Int16(truncatingIfNeeded: (lParam >> 16) & 0xFFFF) // GET_Y_LPARAM
            return overlay.hitTest(screenX: Int32(x), screenY: Int32(y))
        case WM_LBUTTONDOWN:
            var pt = POINT()
            GetCursorPos(&pt)
            overlay.mouseDown(screenPt: pt)
            return 0
        case WM_MOUSEMOVE:
            var pt = POINT()
            GetCursorPos(&pt)
            if let move = overlay.mouseMove(screenPt: pt) {
                controller.dragMoved(dx: move.dx, dy: move.dy)
            }
            return 0
        case WM_LBUTTONUP:
            let wasDrag = overlay.mouseUp()
            if wasDrag {
                overlay.savePosition(to: prefs)
                controller.dragEnded()
                layout()
            } else {
                handleClick(lParam: lParam)
            }
            return 0
        case WM_RBUTTONUP:
            tray.showMenu(app: self)
            return 0
        case WM_DISPLAYCHANGE:
            clampPosition()
            return 0
        case WM_DPICHANGED:
            render()
            return 0
        case WM_SETTINGCHANGE:
            readSystemReducedMotion()
            return 0
        default:
            return DefWindowProcW(hwnd, msg, wParam, lParam)
        }
    }

    private func handleTimer(_ id: UINT_PTR) {
        switch id {
        case FRAME_TIMER_ID:
            controller.advanceFrame()
        case TICK_TIMER_ID:
            tick()
        case HOVER_TIMER_ID:
            checkHover()
        case DRAG_IDLE_TIMER_ID:
            controller.dragIdle()
        default:
            break
        }
    }

    /// 1초 틱: 상태 폴링, 설정 변경 확인.
    private func tick() {
        watcher?.refresh()
        // 설정 변경 신호 파일 확인
        if let ts = prefs.changeSignalTimestamp(), ts != lastPrefsSignal {
            lastPrefsSignal = ts
            controller.isBubbleHidden = prefs.isBubbleHidden
            controller.ignoresReducedMotion = prefs.ignoresReducedMotion
            loadSelectedPet()
            layout()
        }
    }

    /// 50ms 호버 체크. 마우스가 펫/말풍선 영역 위인지 보고 expanded 를 전환한다.
    private func checkHover() {
        guard overlay.isVisible else { return }
        var pt = POINT()
        GetCursorPos(&pt)
        var rc = RECT()
        GetWindowRect(overlay.hwnd, &rc)
        let inside = pt.x >= rc.left && pt.x < rc.right && pt.y >= rc.top && pt.y < rc.bottom
        if inside != wasHovered {
            wasHovered = inside
            controller.setHovered(inside)
            render()
        }
    }

    /// 클릭이 펫 위인지 말풍선 카드 위인지 판단한다.
    private func handleClick(lParam: LPARAM) {
        var pt = POINT()
        GetCursorPos(&pt)
        var rc = RECT()
        GetWindowRect(overlay.hwnd, &rc)
        let localX = Int(pt.x - rc.left)
        let localY = Int(pt.y - rc.top)

        // 카드 닫기 버튼
        for hit in controller.bubbles.cardHits {
            let cr = hit.closeRect
            if localX >= cr.x && localX < cr.x + cr.w && localY >= cr.y && localY < cr.y + cr.h {
                controller.closeCard(hit.summary)
                return
            }
        }
        // 카드 클릭
        for hit in controller.bubbles.cardHits {
            let r = hit.rect
            if localX >= r.x && localX < r.x + r.w && localY >= r.y && localY < r.y + r.h {
                controller.handleCardClick(hit.summary)
                return
            }
        }
        // 펫 클릭
        controller.handleClick()
    }

    // MARK: - 렌더링

    func render() {
        let agg = controller.aggregate
        let bubbleResult = controller.bubbles.render(aggregate: agg, surfaceWidth: max(
            Surface.scaledSize(scale: prefs.scale).w, BubbleRenderer.cardWidth + 24))
        overlay.render(petFrame: controller.currentFrame,
                      bubbleSurface: bubbleResult?.surface,
                      bubbleHeight: bubbleResult?.totalHeight ?? 0,
                      scale: prefs.scale)
    }

    func layout() {
        render()
    }

    // MARK: - 시스템

    func readSystemReducedMotion() {
        var animEnabled: Int32 = 1
        withUnsafeMutablePointer(to: &animEnabled) { ptr in
            SystemParametersInfoW(UINT(SPI_GETCLIENTAREAANIMATION), 0, ptr, 0)
        }
        controller.systemReducedMotion = animEnabled == 0
    }

    private func clampPosition() {
        overlay.place(using: prefs)
        render()
    }

    // MARK: - 펫 로드

    func availablePets() -> [InstalledPet] {
        PetLibrary.discover(userDirectory: Paths.petsDirectory, codexDirectory: Paths.codexPetsDirectory,
                            builtinDirectory: BundleLayout.builtinPetDirectory(executable: executable))
    }

    func loadSelectedPet() {
        let pets = availablePets()
        let ordered = ([pets.first { $0.id == prefs.selectedPetId }]
                       + pets.map(Optional.some)
                       + [pets.last { $0.source == .builtin }]).compactMap { $0 }
        for pet in ordered {
            do {
                try controller.loadPet(pet)
                updateTrayIcon()
                return
            } catch {
                log("펫 로드 실패 \(pet.id): \(error)")
            }
        }
        log("로드 가능한 펫 없음")
        warning = "펫 시트를 불러오지 못했습니다"
    }

    // MARK: - 메뉴 동작

    func toggleVisible() {
        if overlay.isVisible {
            overlay.hide()
            prefs.isHidden = true
            controller.stop()
        } else {
            overlay.show()
            prefs.isHidden = false
            controller.start()
            render()
        }
    }

    func toggleBubble() {
        prefs.isBubbleHidden.toggle()
        controller.isBubbleHidden = prefs.isBubbleHidden
        layout()
    }

    func selectPet(id: String) {
        guard let pet = availablePets().first(where: { $0.id == id }) else { return }
        do {
            try controller.loadPet(pet)
            prefs.selectedPetId = id
            warning = nil
        } catch {
            warning = "펫을 불러오지 못했습니다: \(pet.manifest.displayName)"
        }
        updateTrayIcon()
        render()
    }

    func setScale(_ s: Double) {
        prefs.scale = s
        layout()
    }

    func toggleLoginItem() {
        do {
            if LoginItem.isEnabled { try LoginItem.disable() } else { try LoginItem.enable(appExecutable: executable) }
        } catch {
            messageBox("로그인 항목을 바꾸지 못했습니다", "\(error)")
        }
    }

    func toggleIgnoreReducedMotion() {
        prefs.ignoresReducedMotion.toggle()
        controller.ignoresReducedMotion = prefs.ignoresReducedMotion
    }

    func installHooks(agent: Agent) {
        do {
            let hookExe = BundleLayout.hookExecutable(executable: executable)
            let shell = GitBash.claudeShell()
            let platform = HookPlatform.windows(hookExecutable: hookExe, claudeShell: shell)
            let backup = try HooksInstaller.installFile(at: agent.settingsFile, platform: platform,
                                                         agent: agent, now: Date())
            var msg = "\(agent.displayName) 백업: \(backup.path)"
            if let note = agent.postInstallNote { msg += "\n\n\(note)" }
            msg += "\n\n새로 시작하는 \(agent.displayName) 세션부터 펫이 반응합니다."
            messageBox("훅을 설치했습니다", msg)
            // 경고 갱신
            let still = missingHookAgents
            if warning?.hasSuffix("훅이 설치되지 않았습니다") == true {
                warning = still.isEmpty ? nil : still.map(\.displayName).joined(separator: "·") + " 훅이 설치되지 않았습니다"
            }
        } catch {
            messageBox("\(agent.displayName) 훅 설치 실패", "\(error)")
        }
    }

    func downloadDefaultPet() {
        Task {
            do {
                let pet = try await PetInstaller.live(petsDirectory: Paths.petsDirectory).add(id: "guga")
                selectPet(id: pet.id)
            } catch {
                messageBox("펫을 받지 못했습니다", "\(error)")
            }
        }
    }

    func refresh() {
        watcher?.refresh(force: true)
        let pets = availablePets()
        let target = pets.first { $0.id == prefs.selectedPetId }?.id ?? pets.first?.id
        if controller.pet?.id != target { loadSelectedPet() }
    }

    // MARK: - 첫 실행 훅 설치

    func promptForHooksIfNeeded() {
        guard ProcessInfo.processInfo.environment["CLAUDE_PET_SKIP_FIRST_RUN"] != "1" else { return }
        let missing = missingHookAgents
        guard !missing.isEmpty else { return }
        let names = missing.map(\.displayName).joined(separator: "·")
        let files = missing.map { agent -> String in
            let path = agent.settingsFile.path.replacingOccurrences(of: Paths.home.path + "/", with: "~/")
            return path.replacingOccurrences(of: Paths.home.path + "\\", with: "~/")
        }
        let text = "\(files.joined(separator: ", ")) 에 펫 훅을 추가합니다. 기존 설정은 백업 후 보존됩니다."
        let titleW = Array("\(names) 훅을 설치할까요?".utf16) + [0]
        let textW = Array(text.utf16) + [0]
        let result = titleW.withUnsafeBufferPointer { t in
            textW.withUnsafeBufferPointer { b in
                MessageBoxW(nil, b.baseAddress, t.baseAddress, UINT(MB_YESNO | MB_ICONQUESTION))
            }
        }
        if result == IDYES {
            for agent in missing { installHooks(agent: agent) }
        }
    }

    // MARK: - 유틸

    func updateTrayIcon() {
        let frame = controller.sheet?.frames(for: .idle).first
        tray.addIcon(frame: frame, hasWarning: warning != nil)
    }

    func messageBox(_ title: String, _ text: String) {
        let t = Array(title.utf16) + [0]
        let b = Array(text.utf16) + [0]
        t.withUnsafeBufferPointer { tp in
            b.withUnsafeBufferPointer { bp in
                MessageBoxW(nil, bp.baseAddress, tp.baseAddress, UINT(MB_OK))
            }
        }
    }
}
#endif
