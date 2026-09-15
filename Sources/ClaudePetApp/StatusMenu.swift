import AppKit
import ClaudePetCore
import ServiceManagement

protocol StatusMenuDelegate: AnyObject {
    var isPetVisible: Bool { get }
    var pets: [InstalledPet] { get }
    var currentPetId: String? { get }
    var scale: Double { get }
    var isLoginItemEnabled: Bool { get }
    var hooksInstalled: Bool { get }
    var warning: String? { get }
    func toggleVisible()
    func selectPet(id: String)
    func setScale(_ s: Double)
    func toggleLoginItem()
    func installHooks()
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
        if d.hooksInstalled {
            let i = NSMenuItem(title: "훅: 설치됨", action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
        } else {
            menu.addItem(make("훅 설치하기…", #selector(installHooks)))
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
    @objc private func selectPet(_ sender: NSMenuItem) { if let id = sender.representedObject as? String { delegate?.selectPet(id: id) } }
    @objc private func setScale(_ sender: NSMenuItem) { if let s = sender.representedObject as? Double { delegate?.setScale(s) } }
    @objc private func toggleLoginItem() { delegate?.toggleLoginItem() }
    @objc private func installHooks() { delegate?.installHooks() }
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
