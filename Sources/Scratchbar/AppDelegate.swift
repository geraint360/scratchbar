import AppKit
import ScratchbarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController!
    private(set) var panelController: PanelController!
    private(set) var main: MainViewController!
    private let hotKeys = HotKeyCenter()
    private var shortcutSheet: ShortcutSheet?

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scratchbar", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let store = PageStore(folder: Self.appSupport.appendingPathComponent("Pages", isDirectory: true))
        main = MainViewController(store: store)
        panelController = PanelController(content: main)
        statusItemController = StatusItemController()

        main.menuProvider = { [unowned self] in SettingsMenu.build(target: self) }
        statusItemController.menuProvider = { [unowned self] in SettingsMenu.build(target: self) }
        statusItemController.onLeftClick = { [unowned self] in panelController.toggle() }
        panelController.anchorFrame = { [unowned self] in statusItemController.buttonScreenFrame }

        NSApp.mainMenu = buildMainMenu()
        applyHotKeySettings()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        main.flushAll()
    }

    func applicationDidResignActive(_ notification: Notification) {
        main.flushAll()
    }

    @objc private func willSleep(_ notification: Notification) {
        main.flushAll()
    }

    // MARK: - Settings menu actions

    @objc func toggleStayOnScreen(_ sender: Any?) {
        panelController.isPinned.toggle()
    }

    /// Items between "Stay on Screen" and "Quit".
    func addExtraSettings(to menu: NSMenu) {
        let hotKey = HotKeySettings.load(.standard)
        let title = "Global Shortcut…" + (hotKey.enabled ? hotKey.combo.map { "  \($0.displayString)" } ?? "" : "")
        menu.addItem(SettingsMenu.item(title, #selector(showShortcutSheet(_:)), self))
    }

    // MARK: - Global hotkey

    /// Registers the saved hotkey. Returns false if macOS refused it.
    @discardableResult
    private func applyHotKeySettings() -> Bool {
        let settings = HotKeySettings.load(.standard)
        hotKeys.unregister()
        guard settings.enabled, let combo = settings.combo else { return true }
        return hotKeys.register(combo) { [weak self] in self?.hotKeyPressed() }
    }

    /// Opens a new page ready for typing; pressing it again closes the window.
    private func hotKeyPressed() {
        if panelController.isVisible && panelController.panel.isKeyWindow && panelController.panel.attachedSheet == nil {
            panelController.hide()
        } else {
            panelController.show(newPage: true)
        }
    }

    @objc func showShortcutSheet(_ sender: Any?) {
        if !panelController.isVisible { panelController.show(newPage: false) }
        let settings = HotKeySettings.load(.standard)
        let sheet = ShortcutSheet(
            enabled: settings.enabled, combo: settings.combo,
            apply: { [weak self] enabled, combo in
                HotKeySettings.save(enabled: enabled, combo: combo, to: .standard)
                return self?.applyHotKeySettings() ?? false
            },
            pause: { [weak self] recording in
                if recording { self?.hotKeys.unregister() } else { self?.applyHotKeySettings() }
            })
        shortcutSheet = sheet
        sheet.begin(on: panelController.panel)
    }

    // MARK: - Main menu (key equivalents only; an accessory app shows no menu bar)

    private func buildMainMenu() -> NSMenu {
        let mainMenu = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) {
            let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            items.forEach(menu.addItem)
            holder.submenu = menu
            mainMenu.addItem(holder)
        }
        func item(_ title: String, _ action: Selector, _ key: String,
                  _ mods: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.keyEquivalentModifierMask = mods
            item.target = target
            return item
        }

        submenu("Scratchbar", [item("Quit Scratchbar", #selector(NSApplication.terminate(_:)), "q")])
        submenu("Edit", [
            item("Undo", Selector(("undo:")), "z"),
            item("Redo", Selector(("redo:")), "z", [.command, .shift]),
            item("Cut", #selector(NSText.cut(_:)), "x"),
            item("Copy", #selector(NSText.copy(_:)), "c"),
            item("Paste", #selector(NSText.paste(_:)), "v"),
            item("Select All", #selector(NSText.selectAll(_:)), "a"),
            item("Find…", #selector(NSTextView.performFindPanelAction(_:)), "f").tagged(Int(NSFindPanelAction.showFindPanel.rawValue)),
        ])
        submenu("Page", [
            item("New Page", #selector(MainViewController.newPage(_:)), "n", target: main),
            item("Copy Page", #selector(MainViewController.copyPage(_:)), "c", [.command, .shift], target: main),
            item("Delete Page", #selector(MainViewController.deletePage(_:)), "\u{8}", target: main),
            item("Bigger", #selector(MainViewController.biggerText(_:)), "=", target: main),
            item("Bigger", #selector(MainViewController.biggerText(_:)), "+", target: main),
            item("Smaller", #selector(MainViewController.smallerText(_:)), "-", target: main),
            item("Actual Size", #selector(MainViewController.actualSizeText(_:)), "0", target: main),
            item("Close", #selector(closeWindow(_:)), "w", target: self),
        ])
        return mainMenu
    }

    @objc private func closeWindow(_ sender: Any?) {
        panelController.hide()
    }
}

private extension NSMenuItem {
    func tagged(_ tag: Int) -> NSMenuItem {
        self.tag = tag
        return self
    }
}
