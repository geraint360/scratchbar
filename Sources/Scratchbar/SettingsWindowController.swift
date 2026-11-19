import AppKit

/// The Settings window, modelled on Reminders MenuBar's: toolbar tabs, labels
/// right-aligned in a column, dividers between groups. It is created when
/// opened and released when closed, so it costs no memory the rest of the time.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    /// Called once the window has closed (the owner drops its reference).
    var onClose: () -> Void = {}

    init(app: AppDelegate) {
        let tabs = SettingsTabController()
        tabs.tabStyle = .toolbar
        for (vc, label, symbol) in [
            (GeneralSettings(app: app), "General", "gearshape"),
            (KeyboardSettings(app: app), "Keyboard", "keyboard"),
            (ICloudSettings(app: app), "iCloud", "icloud"),
            (BackupsSettings(app: app), "Backups", "clock.arrow.circlepath"),
            (AboutSettings(app: app), "About", "info.circle"),
        ] as [(NSViewController, String, String)] {
            let item = NSTabViewItem(viewController: vc)
            item.label = label
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
            tabs.addTabViewItem(item)
        }
        // A non-activating panel takes keyboard focus without needing Scratchbar
        // to become the active app (macOS can refuse that for menu bar apps).
        let window = SettingsPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
                                   styleMask: [.titled, .closable, .nonactivatingPanel],
                                   backing: .buffered, defer: true)
        window.contentViewController = tabs
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.toolbarStyle = .preference
        super.init(window: window)
        window.delegate = self
        tabs.fitWindow(animated: false)
        window.title = "General"
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func show() {
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Let the window finish closing before it is released.
        DispatchQueue.main.async { [weak self] in self?.onClose() }
    }
}

private final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { close() }
}

/// Resizes the window to fit each tab, as System Settings-style windows do.
private final class SettingsTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindow(animated: true)
        view.window?.title = tabViewItem?.label ?? "Settings"
    }

    func fitWindow(animated: Bool) {
        guard let window = view.window,
              let content = tabViewItems[safe: selectedTabViewItemIndex]?.viewController?.view else { return }
        content.layoutSubtreeIfNeeded()
        let size = NSSize(width: 600, height: max(content.fittingSize.height, 120))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

// MARK: - Form layout

/// Builds the label-column form used on every tab.
final class SettingsForm {
    let grid = NSGridView(numberOfColumns: 2, rows: 0)

    init() {
        grid.rowSpacing = 8
        grid.columnSpacing = 10
        grid.rowAlignment = .firstBaseline
        grid.column(at: 0).xPlacement = .trailing
        grid.column(at: 0).width = 180
        grid.column(at: 1).xPlacement = .leading
    }

    /// A row with an optional label ("Color scheme" → "Color scheme:").
    func row(_ label: String?, _ view: NSView) {
        let labelView: NSView = label.map { NSTextField(labelWithString: "\($0):") } ?? NSGridCell.emptyContentView
        grid.addRow(with: [labelView, view])
    }

    /// Small grey explanatory text under the control above.
    func note(_ text: String) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.preferredMaxLayoutWidth = 340
        row(nil, label)
    }

    func divider() {
        let box = NSBox()
        box.boxType = .separator
        let row = grid.addRow(with: [box])
        row.mergeCells(in: NSRange(location: 0, length: 2))
        row.rowAlignment = .none
        row.topPadding = 6
        row.bottomPadding = 6
        row.cell(at: 0).xPlacement = .fill
        row.cell(at: 0).yPlacement = .center
    }

    /// The finished tab content, padded like Reminders MenuBar's (20 pt).
    func view() -> NSView {
        let container = NSView()
        grid.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(grid)
        NSLayoutConstraint.activate([
            grid.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            grid.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            grid.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            grid.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -20),
            container.widthAnchor.constraint(equalToConstant: 600),
        ])
        return container
    }
}
