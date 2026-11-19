import AppKit

/// Owns the menu bar icon. Left click toggles the window; right click
/// (or Control-click) shows New Page / Settings… / Quit.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    var onLeftClick: () -> Void = {}
    var menuProvider: () -> NSMenu = { NSMenu() }

    /// Shows a warning variant of the icon (e.g. not syncing).
    var showsWarning = false {
        didSet { updateImage() }
    }

    override init() {
        super.init()
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateImage()
    }

    /// The icon's frame in screen coordinates.
    var buttonScreenFrame: NSRect? {
        guard let button = statusItem.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    private func updateImage() {
        let name = showsWarning ? "exclamationmark.triangle" : "note.text"
        statusItem.button?.image = NSImage(systemSymbolName: name,
                                           accessibilityDescription: showsWarning ? "Scratchbar — not syncing" : "Scratchbar")
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = menuProvider()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            onLeftClick()
        }
    }
}
