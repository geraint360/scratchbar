import AppKit
import ScratchbarCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController!
    private(set) var panelController: PanelController!
    private(set) var main: MainViewController!

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

    /// Later tasks add their settings items here.
    func addExtraSettings(to menu: NSMenu) {}

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
