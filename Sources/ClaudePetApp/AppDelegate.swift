import AppKit
import ClaudePetCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// F-12: 훅 미설치 경고 문구. 시트 로드 실패 경고와 겹치면 시트 경고가 우선한다(warning 이 이미 있으면 덮지 않음).
    /// 앞에 빠진 에이전트 이름이 붙는다. 예: "Claude Code·Codex 훅이 설치되지 않았습니다".
    static let hooksMissingSuffix = " 훅이 설치되지 않았습니다"
    static func hooksMissingWarning(_ agents: [Agent]) -> String {
        agents.map(\.displayName).joined(separator: "·") + hooksMissingSuffix
    }

    /// 이 컴퓨터에서 쓰는 에이전트 중 훅이 빠진 것.
    var missingHookAgents: [Agent] {
        Agent.installTargets().filter { !HooksInstaller.isInstalled(file: $0.settingsFile) }
    }

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

    /// 펫 위에 말풍선이 쌓인다. 패널은 지금 떠 있는 말풍선만큼만 커진다.
    /// 창 크기 자체는 애니메이션하지 않고(끊겨 보인다) 즉시 바꾼 뒤 안에서 카드만 움직인다.
    /// 창이 전부 투명이라 크기가 튀는 것은 눈에 띄지 않는다.
    static let petBubbleGap: CGFloat = 8
    /// 카드 그림자가 패널 가장자리에서 잘리지 않게 두는 여백.
    static let shadowPad: CGFloat = 12

    /// 펫이 선 자리 위로 화면에 남은 높이. 여기에 들어갈 만큼만 카드를 띄운다.
    func maxCardsThatFit() -> Int {
        let petBottom = panel.frame.minY
        let screen = NSScreen.screens.first { $0.frame.intersects(panel.frame) } ?? NSScreen.main
        guard let screen else { return BubbleStackView.expandedLimit }
        let room = screen.visibleFrame.maxY - petBottom - petSize().height - Self.petBubbleGap - Self.shadowPad
        for n in stride(from: BubbleStackView.expandedLimit, through: 1, by: -1)
        where BubbleStackView.height(forCards: n) <= room {
            return n
        }
        return 1
    }

    private var isLayingOut = false

    func layout() {
        // maxCards 를 바꾸면 스택이 다시 그려지고 그 콜백이 여기로 돌아온다. 한 번만 돈다.
        guard !isLayingOut else { return }
        isLayingOut = true
        defer { isLayingOut = false }
        let pet = petSize()
        let pad = Self.shadowPad
        let width = max(pet.width, SessionBubbleView.width + pad * 2)
        controller.stack.maxCards = maxCardsThatFit()
        // 사라지는 중인 카드까지 덮는 높이로 잡는다. 먼저 줄이면 그 카드의 블러가 잘린 자국으로 남는다.
        let stackHeight = controller.stack.occupiedHeight
        let height = pet.height + (stackHeight > 0 ? Self.petBubbleGap + stackHeight + pad : 0)
        panel.resize(to: NSSize(width: width, height: height), prefs: prefs)
        container.frame = NSRect(origin: .zero, size: NSSize(width: width, height: height))
        // 투명 패널은 크기가 줄어든 자리를 스스로 지우지 않는다. 매번 다시 그리게 한다.
        panel.viewsNeedDisplay = true
        panel.invalidateShadow()
        controller.view.frame = NSRect(x: (width - pet.width) / 2, y: 0, width: pet.width, height: pet.height)
        controller.stack.frame = NSRect(x: pad, y: pet.height + Self.petBubbleGap,
                                        width: width - pad * 2, height: max(stackHeight, 0))
    }

    /// 마우스를 받아야 하는 영역: 펫과 말풍선, 그리고 그 사이. 바깥은 클릭이 밑으로 통과한다.
    ///
    /// 펫과 말풍선을 따로 주면 둘 사이 빈 칸을 지날 때 펼친 목록이 접힌다. 커서가 위아래로
    /// 오가는 길을 끊지 않도록 둘을 감싸는 사각형 하나로 준다.
    func hitRects() -> [NSRect] {
        let pet = controller.view.convert(controller.view.bounds, to: nil)
        guard let bubbles = controller.stack.hoverBox else { return [panel.convertToScreen(pet)] }
        return [panel.convertToScreen(pet.union(bubbles))]
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.view.frame = NSRect(origin: .zero, size: petSize())
        panel.contentView = container
        container.addSubview(controller.view)
        container.addSubview(controller.stack)
        controller.onLayoutChange = { [weak self] in self?.layout() }
        controller.onOpenFailed = { [weak self] in self?.warning = "세션이 돌고 있는 앱을 찾지 못했습니다" }
        controller.view.onDragEnd = { [weak self] in
            guard let self else { return }
            self.prefs.position = self.panel.frame.origin
            // 옮긴 자리 위에 남은 화면 높이가 달라졌다. 들어갈 만큼으로 카드 수를 다시 잡는다.
            self.layout()
        }
        panel.place(using: prefs)
        layout()
        panel.place(using: prefs)
        hover = HoverTracker(panel: panel, hitRects: { [weak self] in
            self?.hitRects() ?? []
        }, onChange: { [weak self] inside in
            self?.controller.setHovered(inside)
        })

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
        let missing = missingHookAgents
        if warning == nil && !missing.isEmpty { warning = Self.hooksMissingWarning(missing) }
    }

    /// 첫 실행에 훅 설치를 권한다. 자동화된 실행에서는 CLAUDE_PET_SKIP_FIRST_RUN=1 로 건너뛴다.
    func promptForHooksIfNeeded() {
        guard ProcessInfo.processInfo.environment["CLAUDE_PET_SKIP_FIRST_RUN"] != "1" else { return }
        let missing = missingHookAgents
        guard !missing.isEmpty else { return }
        let a = NSAlert()
        a.messageText = "\(missing.map(\.displayName).joined(separator: "·")) 훅을 설치할까요?"
        let files = missing.map { "~/" + $0.settingsFile.path.replacingOccurrences(of: Paths.home.path + "/", with: "") }
        a.informativeText = "\(files.joined(separator: ", ")) 에 펫 훅을 추가합니다. 기존 설정은 백업 후 보존됩니다."
        a.addButton(withTitle: "설치"); a.addButton(withTitle: "나중에")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn { installHooks(agents: missing) }
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
    var hookStatus: [(agent: Agent, installed: Bool)] {
        Agent.installTargets().map { ($0, HooksInstaller.isInstalled(file: $0.settingsFile)) }
    }

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

    func installHooks(agent: Agent) { installHooks(agents: [agent]) }

    func installHooks(agents: [Agent]) {
        var lines: [String] = []
        for agent in agents {
            do {
                let backup = try HooksInstaller.installFile(at: agent.settingsFile, hookScript: BundleLayout.hookScript(executable: executable), agent: agent, now: Date())
                lines.append("\(agent.displayName) 백업: \(backup.path)")
                if let note = agent.postInstallNote { lines.append(note) }
            } catch {
                alert("\(agent.displayName) 훅 설치 실패", "\(error)")
                return
            }
        }
        // 빠진 에이전트가 남아 있으면 경고 문구를 그쪽으로 좁히고, 다 채워졌으면 지운다.
        if warning?.hasSuffix(Self.hooksMissingSuffix) == true {
            let still = missingHookAgents
            warning = still.isEmpty ? nil : Self.hooksMissingWarning(still)
        }
        let names = agents.map(\.displayName).joined(separator: "·")
        alert("훅을 설치했습니다", lines.joined(separator: "\n") + "\n\n새로 시작하는 \(names) 세션부터 펫이 반응합니다.")
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
