import AppKit
import ScratchbarCore
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var statusItemController: StatusItemController!
    private(set) var panelController: PanelController!
    private(set) var main: MainViewController!
    private let hotKeys = HotKeyCenter()
    private var shortcutSheet: ShortcutSheet?
    private var backupsSheet: BackupsSheet?
    private(set) var backups: BackupStore!
    private let locations = StorageLocations(appSupport: AppDelegate.appSupport, iCloudRoot: StorageLocations.defaultICloudRoot)
    private(set) var repository: PageRepository!
    private var retryTimer: Timer?
    private var watcher: FolderWatcher?

    static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Scratchbar", isDirectory: true)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        repository = PageRepository(locations: locations, syncEnabled: UserDefaults.standard.bool(forKey: DefaultsKey.syncEnabled))
        main = MainViewController(store: repository)
        backups = BackupStore(folder: locations.backups)
        backups.prune()
        main.onSaved = { [unowned self] id, text in
            backups.backupIfDue(id: id, text: text)
            refreshSyncStatus()
        }
        main.backup = { [unowned self] id, text, reason in backups.backup(id: id, text: text, reason: reason) }
        main.resolveVersionConflicts = { [unowned self] id in resolveVersionConflicts(id: id) }
        main.willDelete = { [unowned self] id, text in
            backups.backup(id: id, text: text, reason: .beforeDelete)
            backups.markDeleted(id: id)
        }
        panelController = PanelController(content: main)
        statusItemController = StatusItemController()

        main.menuProvider = { [unowned self] in SettingsMenu.build(target: self) }
        statusItemController.menuProvider = { [unowned self] in SettingsMenu.build(target: self) }
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
        main.applyTranslucency(UserDefaults.standard.bool(forKey: DefaultsKey.translucent))
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

    // MARK: - Launch at Login and translucency

    /// Turn Launch at Login on the first time the app runs from /Applications
    /// (not from a build folder, which would register the wrong copy).
    private func setUpLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: DefaultsKey.loginItemSetUp),
              Bundle.main.bundlePath.hasPrefix("/Applications/") else { return }
        try? SMAppService.mainApp.register()
        UserDefaults.standard.set(true, forKey: DefaultsKey.loginItemSetUp)
    }

    @objc func toggleLaunchAtLogin(_ sender: Any?) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            UserDefaults.standard.set(true, forKey: DefaultsKey.loginItemSetUp)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't change Launch at Login."
            alert.informativeText = "Move Scratchbar to the Applications folder and try again, or add it in System Settings › General › Login Items."
            if panelController.isVisible { alert.beginSheetModal(for: panelController.panel) } else { alert.runModal() }
        }
    }

    @objc func toggleTranslucency(_ sender: Any?) {
        let on = !UserDefaults.standard.bool(forKey: DefaultsKey.translucent)
        UserDefaults.standard.set(on, forKey: DefaultsKey.translucent)
        main.applyTranslucency(on)
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

    @objc func toggleSync(_ sender: Any?) {
        main.flushAll()
        main.leaveCurrentPage()
        let turningOn = !repository.syncEnabled
        do {
            if turningOn {
                try SyncMigrator.enable(locations: locations, backups: backups)
            } else {
                try SyncMigrator.disable(locations: locations, backups: backups)
            }
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = turningOn ? "Couldn't turn on iCloud sync." : "Couldn't turn off iCloud sync."
            if panelController.isVisible { alert.beginSheetModal(for: panelController.panel) } else { alert.runModal() }
            return
        }
        UserDefaults.standard.set(turningOn, forKey: DefaultsKey.syncEnabled)
        repository = PageRepository(locations: locations, syncEnabled: turningOn)
        main.store = repository
        main.resetForStorageChange()
        retryPendingSync()
        startWatching()
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

    // MARK: - Settings menu actions

    @objc func toggleStayOnScreen(_ sender: Any?) {
        panelController.isPinned.toggle()
    }

    /// Items between "Stay on Screen" and "Quit".
    func addExtraSettings(to menu: NSMenu) {
        let hotKey = HotKeySettings.load(.standard)
        let title = "Global Shortcut…" + (hotKey.enabled ? hotKey.combo.map { "  \($0.displayString)" } ?? "" : "")
        menu.addItem(SettingsMenu.item(title, #selector(showShortcutSheet(_:)), self))
        let sync = SettingsMenu.item("Sync with iCloud Drive", #selector(toggleSync(_:)), self)
        sync.state = repository.syncEnabled ? .on : .off
        if !repository.syncEnabled && !locations.iCloudAvailable {
            sync.isEnabled = false
            sync.title = "Sync with iCloud Drive (iCloud Drive is off)"
        }
        menu.addItem(sync)
        if repository.isDegraded {
            let status = NSMenuItem(title: "Not syncing — saved on this Mac", action: nil, keyEquivalent: "")
            status.isEnabled = false
            status.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
            menu.addItem(status)
        }
        menu.addItem(SettingsMenu.item("Backups…", #selector(showBackups(_:)), self))
        menu.addItem(.separator())
        let translucent = SettingsMenu.item("Translucent Background", #selector(toggleTranslucency(_:)), self)
        translucent.state = UserDefaults.standard.bool(forKey: DefaultsKey.translucent) ? .on : .off
        menu.addItem(translucent)
        let login = SettingsMenu.item("Launch at Login", #selector(toggleLaunchAtLogin(_:)), self)
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
    }

    // MARK: - Backups

    /// Taken whenever the window hides (after saving).
    private func backupCurrentPage() {
        guard let id = main.currentID, main.scheduler.knownOnDisk.contains(id) else { return }
        backups.backup(id: id, text: main.currentText, reason: .periodic)
    }

    @objc func showBackups(_ sender: Any?) {
        if !panelController.isVisible { panelController.show(newPage: false) }
        let sheet = BackupsSheet(backups: backups) { [unowned self] id, text in
            if let current = try? main.store.read(id) {
                backups.backup(id: id, text: current, reason: .beforeRestore)
            }
            backups.unmarkDeleted(id: id)
            main.restorePage(id: id, text: text)
        }
        backupsSheet = sheet
        sheet.begin(on: panelController.panel)
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
