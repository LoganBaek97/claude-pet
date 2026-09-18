import AppKit
import ClaudePetCore
import ServiceManagement

protocol StatusMenuDelegate: AnyObject {
    var isPetVisible: Bool { get }
    var isBubbleVisible: Bool { get }
    var pets: [InstalledPet] { get }
    var currentPetId: String? { get }
    var scale: Double { get }
    var isLoginItemEnabled: Bool { get }
    /// 시스템 "동작 줄이기" 가 켜져 있는가. 켜져 있을 때만 무시 항목을 보여 준다.
    var isReducedMotionOn: Bool { get }
    var ignoresReducedMotion: Bool { get }
    /// 이 컴퓨터에서 쓰는 에이전트마다 훅 설치 여부. 메뉴에 한 줄씩 나온다.
    var hookStatus: [(agent: Agent, installed: Bool)] { get }
    var warning: String? { get }
    func toggleVisible()
    func toggleBubble()
    func selectPet(id: String)
    func setScale(_ s: Double)
    func toggleLoginItem()
    func toggleIgnoreReducedMotion()
    func installHooks(agent: Agent)
    func downloadDefaultPet()
    func refresh()
}

final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private weak var delegate: StatusMenuDelegate?

    init(delegate: StatusMenuDelegate) {
        self.delegate = delegate
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        updateIcon()
    }

    func updateIcon() {
        let name = delegate?.warning == nil ? "pawprint.fill" : "exclamationmark.triangle.fill"
        item.button?.image = NSImage(systemSymbolName: name, accessibilityDescription: "Claude Pet")
        item.button?.image?.isTemplate = true
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let d = delegate else { return }
        updateIcon()
        if let w = d.warning {
            let i = NSMenuItem(title: w, action: nil, keyEquivalent: ""); i.isEnabled = false
            menu.addItem(i); menu.addItem(.separator())
        }
        menu.addItem(make(d.isPetVisible ? "펫 숨기기" : "펫 보이기", #selector(toggleVisible)))
        menu.addItem(make(d.isBubbleVisible ? "대화창 끄기" : "대화창 켜기", #selector(toggleBubble)))

        let petsMenu = NSMenu()
        for pet in d.pets {
            let title = pet.source == .codex ? "\(pet.manifest.displayName) (codex)" : pet.manifest.displayName
            let i = make(title, #selector(selectPet(_:))); i.representedObject = pet.id
            i.state = pet.id == d.currentPetId ? .on : .off
            petsMenu.addItem(i)
        }
        if d.pets.allSatisfy({ $0.source == .builtin }) {
            petsMenu.addItem(.separator())
            petsMenu.addItem(make("펫 받기 (guga)…", #selector(downloadDefaultPet)))
        }
        let petsItem = NSMenuItem(title: "펫 선택", action: nil, keyEquivalent: ""); petsItem.submenu = petsMenu
        menu.addItem(petsItem)

        let sizeMenu = NSMenu()
        for (title, s) in [("작게", 0.35), ("보통", 0.5), ("크게", 1.0)] {
            let i = make(title, #selector(setScale(_:))); i.representedObject = s; i.state = d.scale == s ? .on : .off
            sizeMenu.addItem(i)
        }
        let sizeItem = NSMenuItem(title: "크기", action: nil, keyEquivalent: ""); sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        menu.addItem(.separator())

        let login = make("로그인 시 실행", #selector(toggleLoginItem)); login.state = d.isLoginItemEnabled ? .on : .off
        menu.addItem(login)
        // 시스템 설정을 켜 둔 사람에게만 보여 준다. 평소에는 있을 이유가 없는 항목이다.
        if d.isReducedMotionOn {
            let i = make("동작 줄이기 무시하고 움직이기", #selector(toggleIgnoreReducedMotion))
            i.state = d.ignoresReducedMotion ? .on : .off
            menu.addItem(i)
        }
        for (agent, installed) in d.hookStatus {
            if installed {
                let i = NSMenuItem(title: "\(agent.displayName) 훅: 설치됨", action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
            } else {
                let i = make("\(agent.displayName) 훅 설치하기…", #selector(installHooks(_:))); i.representedObject = agent.rawValue
                menu.addItem(i)
            }
        }
        menu.addItem(make("상태 다시 읽기", #selector(refresh)))
        menu.addItem(.separator())
        menu.addItem(make("종료", #selector(quit), key: "q"))
    }

    private func make(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func toggleVisible() { delegate?.toggleVisible() }
    @objc private func toggleBubble() { delegate?.toggleBubble() }
    @objc private func selectPet(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { delegate?.selectPet(id: id) } }
    @objc private func setScale(_ sender: NSMenuItem) { if let s = sender.representedObject as? Double { delegate?.setScale(s) } }
    @objc private func toggleLoginItem() { delegate?.toggleLoginItem() }
    @objc private func toggleIgnoreReducedMotion() { delegate?.toggleIgnoreReducedMotion() }
    @objc private func installHooks(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let agent = Agent(rawValue: raw) { delegate?.installHooks(agent: agent) }
    }
    @objc private func downloadDefaultPet() { delegate?.downloadDefaultPet() }
    @objc private func refresh() { delegate?.refresh() }
    @objc private func quit() { NSApp.terminate(nil) }

    /// 우클릭 메뉴로도 같은 메뉴를 띄운다.
    func popUp(at event: NSEvent, in view: NSView) {
        guard let menu = item.menu else { return }
        menuNeedsUpdate(menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}
