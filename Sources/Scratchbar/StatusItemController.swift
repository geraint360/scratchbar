import AppKit

/// Owns the menu bar icon. Left click will toggle the window (Task 4);
/// right click shows the app menu.
final class StatusItemController: NSObject {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let menu = NSMenu()

    override init() {
        super.init()
        menu.addItem(withTitle: "Quit Scratchbar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "note.text", accessibilityDescription: "Scratchbar")
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        // Until the window exists (Task 4), both clicks show the menu.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
}
