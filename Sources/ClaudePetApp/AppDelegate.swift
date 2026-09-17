import AppKit
import ClaudePetCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// F-12: 훅 미설치 경고 문구. 시트 로드 실패 경고와 겹치면 시트 경고가 우선한다(warning 이 이미 있으면 덮지 않음).
    static let hooksMissingWarning = "Claude Code 훅이 설치되지 않았습니다"

    let prefs = Preferences.shared
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    lazy var panel = OverlayPanel(contentSize: petSize())
    let controller = PetController()
    let container = NSView(frame: .zero)
    var watcher: StateWatcher?
    var hover: HoverTracker?
    var statusMenu: StatusMenu?
    var warning: String? { didSet { statusMenu?.updateIcon() } }

    func petSize() -> NSSize {
        NSSize(width: CGFloat(SpriteSheet.cellWidth) * prefs.scale, height: CGFloat(SpriteSheet.cellHeight) * prefs.scale)
    }

    /// 컨테이너 = 펫 위에 말풍선(높이 20 + 간격 4). 너비는 둘 중 넓은 쪽, 펫은 하단 중앙.
    func layout() {
        let pet = petSize()
        let bubbleSize = controller.bubble.isHidden ? NSSize.zero : controller.bubble.frame.size
        let width = max(pet.width, bubbleSize.width)
        let height = pet.height + (bubbleSize.height > 0 ? bubbleSize.height + 4 : 0)
        panel.resize(to: NSSize(width: width, height: height), prefs: prefs)
        container.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        controller.view.frame = NSRect(x: (width - pet.width) / 2, y: 0, width: pet.width, height: pet.height)
        controller.bubble.frame.origin = NSPoint(x: (width - bubbleSize.width) / 2, y: pet.height + 4)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.view.frame = NSRect(origin: .zero, size: petSize())
        panel.contentView = container
        container.addSubview(controller.view)
        container.addSubview(controller.bubble)
        controller.onLayoutChange = { [weak self] in self?.layout() }
        controller.onOpenFailed = { [weak self] in self?.warning = "Claude Desktop 을 찾지 못했습니다" }
        controller.view.onDragEnd = { [weak self] in
            guard let self else { return }
            self.prefs.position = self.panel.frame.origin
        }
        panel.place(using: prefs)
        layout()
        panel.place(using: prefs)
        hover = HoverTracker(panel: panel) { [weak self] in
            guard let self else { return .zero }
            let inView = self.controller.view.bounds
            let inWindow = self.controller.view.convert(inView, to: nil)
            return self.panel.convertToScreen(inWindow)
        }

        controller.isBubbleHidden = prefs.isBubbleHidden
        loadSelectedPet()

        watcher = StateWatcher(store: StateStore(directory: Paths.stateDirectory)) { [weak self] agg in
            self?.controller.apply(agg)
        }
        watcher?.start()

        // 숨긴 채로 시작하면 렌더·호버 타이머를 켜지 않는다. toggleVisible 이 보일 때 켜고 숨길 때 끄는 것과 같은 규칙이다.
        if !prefs.isHidden {
            panel.orderFrontRegardless()
            controller.start()
            hover?.start()
        }

        statusMenu = StatusMenu(delegate: self)
        controller.view.onRightClick = { [weak self] e in
            guard let self else { return }
            self.statusMenu?.popUp(at: e, in: self.controller.view)
        }
        DistributedNotificationCenter.default().addObserver(forName: Preferences.changedNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.controller.isBubbleHidden = self.prefs.isBubbleHidden
            self.loadSelectedPet(); self.layout()
        }
        promptForHooksIfNeeded()
        if warning == nil && !hooksInstalled { warning = Self.hooksMissingWarning }
    }

    /// 첫 실행에 훅 설치를 권한다. 자동화된 실행에서는 CLAUDE_PET_SKIP_FIRST_RUN=1 로 건너뛴다.
    func promptForHooksIfNeeded() {
        guard ProcessInfo.processInfo.environment["CLAUDE_PET_SKIP_FIRST_RUN"] != "1" else { return }
        guard !hooksInstalled else { return }
        let a = NSAlert()
        a.messageText = "Claude Code 훅을 설치할까요?"
        a.informativeText = "~/.claude/settings.json 에 펫 훅을 추가합니다. 기존 설정은 백업 후 보존됩니다."
        a.addButton(withTitle: "설치"); a.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { installHooks() }
    }

    func availablePets() -> [InstalledPet] {
        PetLibrary.discover(userDirectory: Paths.petsDirectory, codexDirectory: Paths.codexPetsDirectory,
                            builtinDirectory: BundleLayout.builtinPetDirectory(executable: executable))
    }

    /// 선택된 펫 → 첫 번째 펫 → 내장 펫 순으로 로드한다. 전부 실패하면 빈 화면으로 두고 경고를 남긴다.
    func loadSelectedPet() {
        let pets = availablePets()
        let ordered = ([pets.first { $0.id == prefs.selectedPetId }] + pets.map(Optional.some) + [pets.last { $0.source == .builtin }]).compactMap { $0 }
        for pet in ordered {
            do { try controller.loadPet(pet); return } catch { NSLog("claude-pet: failed to load pet \(pet.id): \(error)") }
        }
        NSLog("claude-pet: no loadable pet found")
        warning = "펫 시트를 불러오지 못했습니다"
    }
}

extension AppDelegate: StatusMenuDelegate {
    var isPetVisible: Bool { panel.isVisible }
    var isBubbleVisible: Bool { !prefs.isBubbleHidden }
    var pets: [InstalledPet] { availablePets() }
    var currentPetId: String? { controller.pet?.id }
    var scale: Double { prefs.scale }
    var isLoginItemEnabled: Bool { SMAppService.mainApp.status == .enabled }
    var hooksInstalled: Bool { HooksInstaller.isInstalled(file: Paths.claudeSettingsFile) }

    func toggleVisible() {
        if panel.isVisible {
            panel.orderOut(nil); prefs.isHidden = true
            controller.stop(); hover?.stop()
        } else {
            panel.orderFrontRegardless(); prefs.isHidden = false
            controller.start(); hover?.start()
        }
    }

    /// 말풍선만 끈다. 펫은 그대로 두므로 패널은 계속 떠 있다.
    func toggleBubble() {
        prefs.isBubbleHidden.toggle()
        controller.isBubbleHidden = prefs.isBubbleHidden
        layout()
    }

    func selectPet(id: String) {
        guard let pet = availablePets().first(where: { $0.id == id }) else { return }
        do { try controller.loadPet(pet); prefs.selectedPetId = id; warning = nil }
        catch { warning = "펫을 불러오지 못했습니다: \(pet.manifest.displayName)" }
        statusMenu?.updateIcon()
    }

    func setScale(_ s: Double) { prefs.scale = s; layout() }

    func toggleLoginItem() {
        do {
            if isLoginItemEnabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() }
        } catch {
            alert("로그인 항목을 바꾸지 못했습니다", "\(error.localizedDescription)\n\n앱을 /Applications 에 설치한 뒤 다시 시도해 주세요.")
        }
    }

    func installHooks() {
        do {
            let backup = try HooksInstaller.installFile(at: Paths.claudeSettingsFile,
                                                        hookScript: BundleLayout.hookScript(executable: executable), now: Date())
            if warning == Self.hooksMissingWarning { warning = nil }
            alert("훅을 설치했습니다", "백업: \(backup.path)\n\n새로 시작하는 Claude 세션부터 펫이 반응합니다.")
        } catch {
            alert("훅 설치 실패", "\(error)")
        }
    }

    func downloadDefaultPet() {
        Task { @MainActor in
            do {
                let pet = try await PetInstaller.live(petsDirectory: Paths.petsDirectory).add(id: "guga")
                selectPet(id: pet.id)
            } catch {
                alert("펫을 받지 못했습니다", "\(error)")
            }
        }
    }

    /// F-13: 이미 원하는 펫이 로드되어 있으면 다시 읽지 않는다(재로드는 waving 을 재생하므로, 펫이 바뀌었거나
    /// 이전 로드가 실패했을 때만 다시 시도한다).
    func refresh() {
        watcher?.refresh(force: true)
        let pets = availablePets()
        let target = pets.first { $0.id == prefs.selectedPetId }?.id ?? pets.first?.id ?? pets.last { $0.source == .builtin }?.id
        if controller.pet?.id != target { loadSelectedPet() }
    }

    func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text
        NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}
