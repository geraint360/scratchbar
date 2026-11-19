import AppKit

/// The "…" menu in the window, also shown on right-click of the menu bar icon.
/// Settings live here instead of a preferences window.
enum SettingsMenu {
    static func build(target: AppDelegate) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let stay = item("Stay on Screen", #selector(AppDelegate.toggleStayOnScreen(_:)), target)
        stay.state = target.panelController.isPinned ? .on : .off
        menu.addItem(stay)

        target.addExtraSettings(to: menu)

        menu.addItem(.separator())
        menu.addItem(item("Quit Scratchbar", #selector(NSApplication.terminate(_:)), NSApp, key: "q"))
        return menu
    }

    static func item(_ title: String, _ action: Selector, _ target: AnyObject, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
