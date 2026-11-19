import AppKit
import ScratchbarCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController!
    private(set) var panelController: PanelController!
    private(set) var main: MainViewController!
    private let hotKeys = HotKeyCenter()
    private var settings: SettingsWindowController?
    private(set) var backups: BackupStore!
    let locations = StorageLocations(appSupport: AppDelegate.appSupport, iCloudRoot: StorageLocations.defaultICloudRoot)
    private(set) var repository: PageRepository!
    private var retryTimer: Timer?
    private var watcher: FolderWatcher?

    /// `open Scratchbar.app --args -dataFolder /some/folder` uses another folder
    /// (for demos and testing) without touching your real pages.
    static var appSupport: URL {
        if let override = UserDefaults.standard.string(forKey: "dataFolder"), !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scratchbar", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        backups = BackupStore(folder: locations.backups)
        repository = makeRepository(syncEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.syncEnabled))
        main = MainViewController(store: repository)
        backups.prune()
        main.onSaved = { [unowned self] id, text in
            backups.backupIfDue(id: id, text: text)
            refreshSyncStatus()
        }
        main.backup = { [unowned self] id, text, reason in backups.backup(id: id, text: text, reason: reason) }
        main.didDiscard = { [unowned self] id in backups.markDeleted(id: id) }
        main.resolveVersionConflicts = { [unowned self] id in resolveVersionConflicts(id: id) }
        main.willDelete = { [unowned self] id, text in
            backups.backup(id: id, text: text, reason: .beforeDelete)
            backups.markDeleted(id: id)
        }
        panelController = PanelController(content: main)
        statusItemController = StatusItemController()

        main.onShowSettings = { [unowned self] in showSettings(nil) }
        statusItemController.menuProvider = { [unowned self] in statusMenu() }
        panelController.keepsOpen = { [unowned self] in settings?.window?.isVisible == true }
        statusItemController.onLeftClick = { [unowned self] in panelController.toggle() }
        panelController.didHide = { [unowned self] in backupCurrentPage() }
        panelController.willShow = { [unowned self] in watcher?.scheduleScan() }
        panelController.anchorFrame = { [unowned self] in statusItemController.buttonScreenFrame }

        NSApp.mainMenu = buildMainMenu()
        applyHotKeySettings()

        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(willSleep(_:)), name: NSWorkspace.willSleepNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(didWake(_:)), name: NSWorkspace.didWakeNotification, object: nil)
        retryPendingSync()
        startWatching()
        UserDefaults.standard.removeObject(forKey: "translucent")  // v0.1 setting, now gone
        ColorScheme.saved.apply()
        setUpLoginItemOnFirstLaunch()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            guard case .newPage(let text, let hide)? = URLCommand.parse(url) else { continue }
            if hide {
                main.addPage(text: text, select: false)
            } else {
                if !panelController.isVisible { panelController.show(newPage: false) }
                main.addPage(text: text, select: true)
                main.focusEditor()
            }
        }
    }

    // MARK: - Launch at Login

    /// Turn Launch at Login on the first time the app runs from /Applications
    /// (not from a build folder, which would register the wrong copy).
    private func setUpLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.loginItemSetUp),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: DefaultsKey.loginItemSetUp)
    }

    var launchAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            UserDefaults.standard.set(true, forKey: DefaultsKey.loginItemSetUp)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login."
            alert.informativeText = "Move Scratchbar to the Applications folder and try again, or add it in System Settings › General › Login Items."
            present(alert)
        }
    }

    /// Shows an alert on the Settings window if it is open, else on the main window.
    private func present(_ alert: NSAlert) {
        if let window = settings?.window, window.isVisible {
            alert.beginSheetModal(for: window)
        } else if panelController.isVisible {
            alert.beginSheetModal(for: panelController.panel)
        } else {
            alert.runModal()
        }
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

    @objc private func didWake(_ notification: Notification) {
        retryPendingSync()
    }

    // MARK: - iCloud sync

    var syncEnabled: Bool { repository.syncEnabled }
    var syncDegraded: Bool { repository.isDegraded }
    var iCloudAvailable: Bool { locations.iCloudAvailable }

    func showPagesInFinder() {
        let folder = repository.primaryFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([folder])
    }

    func setSync(_ turningOn: Bool) {
        guard turningOn != repository.syncEnabled else { return }
        main.flushAll()
        main.leaveCurrentPage()
        do {
            if turningOn {
                try SyncMigrator.enable(locations: locations, backups: backups)
            } else {
                try SyncMigrator.disable(locations: locations, backups: backups)
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = turningOn ? "Couldn't turn on iCloud sync." : "Couldn't turn off iCloud sync."
            present(alert)
            return
        }
        UserDefaults.standard.set(turningOn, forKey: DefaultsKey.syncEnabled)
        repository = makeRepository(syncEnabled: turningOn)
        main.store = repository
        main.resetForStorageChange()
        retryPendingSync()
        startWatching()
    }

    private func makeRepository(syncEnabled: Bool) -> PageRepository {
        let repo = PageRepository(locations: locations, syncEnabled: syncEnabled)
        repo.backup = { [unowned self] id, text in backups.backup(id: id, text: text, reason: .beforeSync) }
        return repo
    }

    /// Watches the active pages folder for changes from iCloud, Finder or other editors.
    private func startWatching() {
        watcher?.stop()
        watcher = nil
        let folder = repository.primaryFolder
        if repository.syncEnabled && !locations.iCloudAvailable { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: !repository.syncEnabled)
        watcher = FolderWatcher(folder: folder) { [weak self] events in self?.handleFolderEvents(events) }
    }

    private func handleFolderEvents(_ events: [RemoteEvent]) {
        guard let folder = watcher?.folder else { return }
        var conflictTexts: [String: String] = [:]
        let checked: [RemoteEvent] = events.map { event in
            guard case .modified(let id) = event else { return event }
            let url = folder.appendingPathComponent(id).appendingPathExtension("txt")
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? []
            guard let newest = conflicts.max(by: { ($0.modificationDate ?? .distantPast) < ($1.modificationDate ?? .distantPast) }),
                  let data = try? Data(contentsOf: newest.url) else { return event }
            conflictTexts[id] = decodeText(data)
            return .conflict(id: id)
        }
        main.handleRemote(checked, conflictTexts: conflictTexts)
    }

    private func resolveVersionConflicts(id: String) {
        let url = repository.primaryFolder.appendingPathComponent(id).appendingPathExtension("txt")
        for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: url) ?? [] {
            version.isResolved = true
        }
        try? NSFileVersion.removeOtherVersionsOfItem(at: url)
    }

    /// Moves pages saved locally (because iCloud failed) into iCloud Drive.
    private func retryPendingSync() {
        if repository.flushPending() > 0 { main.reloadList() }
        refreshSyncStatus()
    }

    private func refreshSyncStatus() {
        statusItemController?.showsWarning = repository.isDegraded
        if repository.isDegraded, retryTimer == nil {
            retryTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
                self?.retryPendingSync()
            }
        } else if !repository.isDegraded {
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }

    // MARK: - Settings window and menus

    @objc func showSettings(_ sender: Any?) {
        if settings == nil {
            let controller = SettingsWindowController(app: self)
            controller.onClose = { [weak self] in
                self?.settings = nil
                // Give the main window focus back, so clicking elsewhere hides it again.
                if let panel = self?.panelController, panel.isVisible { panel.panel.makeKey() }
            }
            settings = controller
        }
        settings?.show()
    }

    @objc private func newPageFromMenu(_ sender: Any?) {
        panelController.show(newPage: true)
    }

    /// Right-click on the menu bar icon.
    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ target: AnyObject) {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = target
            menu.addItem(item)
        }
        add("New Page", #selector(newPageFromMenu(_:)), self)
        add("Settings…", #selector(showSettings(_:)), self)
        menu.addItem(.separator())
        add("Quit Scratchbar", #selector(NSApplication.terminate(_:)), NSApp)
        return menu
    }

    // MARK: - Backups

    /// Taken whenever the window hides (after saving).
    private func backupCurrentPage() {
        guard let id = main.currentID, main.scheduler.knownOnDisk.contains(id) else { return }
        backups.backup(id: id, text: main.currentText, reason: .periodic)
    }

    /// Settings › Backups › Restore.
    func restoreBackup(id: String, text: String) {
        if let current = try? main.store.read(id) {
            backups.backup(id: id, text: current, reason: .beforeRestore)
        }
        backups.unmarkDeleted(id: id)
        if !panelController.isVisible { panelController.show(newPage: false) }
        main.restorePage(id: id, text: text)
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

    /// Saves and registers the shortcut; false if macOS refused it.
    func applyHotKey(enabled: Bool, combo: KeyCombo?) -> Bool {
        HotKeySettings.save(enabled: enabled, combo: combo, to: .standard)
        return applyHotKeySettings()
    }

    /// Pauses the global shortcut while a new one is being recorded.
    func pauseHotKey(_ paused: Bool) {
        if paused { hotKeys.unregister() } else { applyHotKeySettings() }
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

        submenu("Scratchbar", [
            item("Settings…", #selector(showSettings(_:)), ",", target: self),
            item("Quit Scratchbar", #selector(NSApplication.terminate(_:)), "q"),
        ])
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
            item("Previous Page", #selector(MainViewController.previousPage(_:)), "[", target: main),
            item("Next Page", #selector(MainViewController.nextPage(_:)), "]", target: main),
            item("Search Pages", #selector(MainViewController.focusSearch(_:)), "f", [.command, .shift], target: main),
            item("Show/Hide Page List", #selector(MainViewController.toggleSidebar(_:)), "s", [.command, .control], target: main),
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
