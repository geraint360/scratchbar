import AppKit
import ScratchbarCore

// MARK: - General

final class GeneralSettings: NSViewController {
    private unowned let app: AppDelegate
    private let launchBox: NSButton
    private let schemePopUp = NSPopUpButton()
    private let stayBox: NSButton
    private let sizeLabel = NSTextField(labelWithString: "")
    private let sizeStepper = NSStepper()

    init(app: AppDelegate) {
        self.app = app
        launchBox = NSButton(checkboxWithTitle: "Open Scratchbar when you log in", target: nil, action: nil)
        stayBox = NSButton(checkboxWithTitle: "Stay on screen when clicking elsewhere", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        launchBox.target = self
        launchBox.action = #selector(toggleLaunch)
        stayBox.target = self
        stayBox.action = #selector(toggleStay)

        schemePopUp.addItem(withTitle: "System appearance")
        schemePopUp.menu?.addItem(.separator())
        schemePopUp.addItems(withTitles: ["Light", "Dark"])
        schemePopUp.target = self
        schemePopUp.action = #selector(changeScheme)

        let reset = NSButton(title: "Reset to default size", target: self, action: #selector(resetSize))
        reset.bezelStyle = .rounded

        sizeStepper.minValue = Double(PlainTextView.fontSizeRange.lowerBound)
        sizeStepper.maxValue = Double(PlainTextView.fontSizeRange.upperBound)
        sizeStepper.increment = 1
        sizeStepper.target = self
        sizeStepper.action = #selector(changeTextSize)
        sizeStepper.setAccessibilityLabel("Text size")
        let sizeRow = NSStackView(views: [sizeLabel, sizeStepper])
        sizeRow.spacing = 6

        let form = SettingsForm()
        form.row("Launch at login", launchBox)
        form.divider()
        form.row("Color scheme", schemePopUp)
        form.row("Text size", sizeRow)
        form.note("⌘+ and ⌘− also change it while you type; ⌘0 resets it.")
        form.divider()
        form.row("Window", stayBox)
        form.note("The pin button at the top of the window does the same.")
        form.row(nil, reset)
        view = form.view()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        launchBox.state = app.launchAtLogin ? .on : .off
        stayBox.state = app.panelController.isPinned ? .on : .off
        switch ColorScheme.saved {
        case .system: schemePopUp.selectItem(at: 0)
        case .light: schemePopUp.selectItem(withTitle: "Light")
        case .dark: schemePopUp.selectItem(withTitle: "Dark")
        }
        refreshTextSize()
    }

    private func refreshTextSize() {
        let size = app.main.textView.fontSize
        sizeStepper.doubleValue = Double(size)
        sizeLabel.stringValue = "\(Int(size)) pt"
    }

    @objc private func toggleLaunch() {
        app.setLaunchAtLogin(launchBox.state == .on)
        launchBox.state = app.launchAtLogin ? .on : .off
    }

    @objc private func toggleStay() {
        app.panelController.isPinned = stayBox.state == .on
    }

    @objc private func changeScheme() {
        let scheme: ColorScheme = switch schemePopUp.titleOfSelectedItem {
        case "Light": .light
        case "Dark": .dark
        default: .system
        }
        UserDefaults.standard.set(scheme.rawValue, forKey: DefaultsKey.colorScheme)
        scheme.apply()
    }

    @objc private func resetSize() {
        app.panelController.resetSize()
    }

    @objc private func changeTextSize() {
        app.main.textView.applyFontSize(CGFloat(sizeStepper.doubleValue))
        refreshTextSize()
    }
}

// MARK: - Keyboard

final class KeyboardSettings: NSViewController {
    private unowned let app: AppDelegate
    private let enableBox: NSButton
    private let recorder = ShortcutRecorderField()
    private let restoreButton = NSButton(title: "Restore default", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private var errorRow: NSGridRow?

    init(app: AppDelegate) {
        self.app = app
        enableBox = NSButton(checkboxWithTitle: "Open a new page from anywhere", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        enableBox.target = self
        enableBox.action = #selector(changed)
        recorder.onChange = { [weak self] _ in self?.changed() }
        recorder.onRecordingChange = { [weak self] recording in self?.app.pauseHotKey(recording) }
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefault)
        restoreButton.bezelStyle = .rounded
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        let recorderRow = NSStackView(views: [recorder, restoreButton])
        recorderRow.spacing = 12

        let shortcuts: [(String, String)] = [
            ("⌘N", "New page"), ("⇧⌘C", "Copy page"), ("⌘⌫", "Delete page"),
            ("⌘[  ⌘]", "Previous / next page"), ("⇧⌘F", "Search pages"), ("⌃⌘S", "Show or hide the page list"),
            ("⌘F", "Find"), ("⌘+  ⌘−  ⌘0", "Text size"), ("⌘,", "Settings"), ("Esc  ⌘W", "Close the window"),
        ]

        let form = SettingsForm()
        form.row("Global shortcut", enableBox)
        form.row(nil, recorderRow)
        errorRow = form.grid.addRow(with: [NSGridCell.emptyContentView, errorLabel])
        form.note("Press it, start typing: the text goes straight into a new page. Press it again to close the window.")
        form.divider()
        for (index, (keys, action)) in shortcuts.enumerated() {
            let k = NSTextField(labelWithString: keys)
            k.textColor = .secondaryLabelColor
            k.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let row = NSStackView(views: [k, NSTextField(labelWithString: action)])
            row.spacing = 8
            form.row(index == 0 ? "In Scratchbar" : nil, row)
        }
        view = form.view()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        let settings = HotKeySettings.load(.standard)
        enableBox.state = settings.enabled ? .on : .off
        recorder.combo = settings.combo
        showError(nil)
        refreshEnabled()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        app.pauseHotKey(false)
    }

    private func refreshEnabled() {
        let on = enableBox.state == .on
        recorder.alphaValue = on ? 1 : 0.4
        restoreButton.isEnabled = on
    }

    @objc private func changed() {
        refreshEnabled()
        let ok = app.applyHotKey(enabled: enableBox.state == .on, combo: recorder.combo)
        showError(ok ? nil : "That shortcut is in use by another app.")
    }

    private func showError(_ message: String?) {
        errorLabel.stringValue = message ?? ""
        errorRow?.isHidden = message == nil
    }

    @objc private func restoreDefault() {
        recorder.combo = .defaultCombo
        changed()
    }
}

// MARK: - iCloud

final class ICloudSettings: NSViewController {
    private unowned let app: AppDelegate
    private let syncBox: NSButton
    private let statusLabel = NSTextField(labelWithString: "")

    init(app: AppDelegate) {
        self.app = app
        syncBox = NSButton(checkboxWithTitle: "Sync pages with iCloud Drive", target: nil, action: nil)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        syncBox.target = self
        syncBox.action = #selector(toggleSync)
        let show = NSButton(title: "Show in Finder", target: self, action: #selector(showFolder))
        show.bezelStyle = .rounded

        let form = SettingsForm()
        form.row("iCloud Drive", syncBox)
        form.note("Pages are kept in iCloud Drive › Scratchbar, for your other Macs. If iCloud isn't available, pages are still saved on this Mac and sync later.")
        form.divider()
        form.row("Status", statusLabel)
        form.row("Pages folder", show)
        view = form.view()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    private func refresh() {
        syncBox.state = app.syncEnabled ? .on : .off
        syncBox.isEnabled = app.syncEnabled || app.iCloudAvailable
        statusLabel.stringValue = switch (app.syncEnabled, app.syncDegraded) {
        case (false, _): app.iCloudAvailable ? "Off — pages are saved on this Mac" : "iCloud Drive is off on this Mac"
        case (true, true): "Not syncing — saved on this Mac until iCloud is available"
        case (true, false): "Syncing with iCloud Drive"
        }
    }

    @objc private func toggleSync() {
        app.setSync(syncBox.state == .on)
        refresh()
    }

    @objc private func showFolder() {
        app.showPagesInFinder()
    }
}

// MARK: - About

final class AboutSettings: NSViewController {
    private unowned let app: AppDelegate

    init(app: AppDelegate) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let icon = NSImageView(image: NSImage(systemSymbolName: "note.text", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 64, weight: .light))!)
        icon.contentTintColor = Theme.accent
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 96).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 96).isActive = true
        let name = NSTextField(labelWithString: "Scratchbar")
        name.font = .systemFont(ofSize: 24, weight: .semibold)
        let info = Bundle.main.infoDictionary
        let version = NSTextField(labelWithString: "Version \(info?["CFBundleShortVersionString"] as? String ?? "–")")
        version.textColor = .secondaryLabelColor
        let blurb = NSTextField(labelWithString: "Plain-text scratch pages in your menu bar.")
        let show = NSButton(title: "Show Pages in Finder", target: self, action: #selector(showFolder))
        show.bezelStyle = .rounded

        let stack = NSStackView(views: [icon, name, version, blurb, show])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(16, after: blurb)
        stack.edgeInsets = NSEdgeInsets(top: 24, left: 20, bottom: 24, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: 600).isActive = true
        view = stack
    }

    @objc private func showFolder() {
        app.showPagesInFinder()
    }
}
