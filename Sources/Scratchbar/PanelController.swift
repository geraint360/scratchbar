import AppKit

/// The single Scratchbar window. A titled panel with its title bar hidden gives
/// rounded corners, a shadow and resizing. It is non-activating, like Spotlight:
/// it becomes key (so typing works) without activating the app.
final class ScratchPanel: NSPanel {
    var onEscape: (() -> Void)?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}

/// Shows and hides the panel in two modes:
/// unpinned (popover-like: under the menu bar icon, hides when you click elsewhere)
/// and pinned (stays on screen, movable, position remembered).
final class PanelController: NSObject, NSWindowDelegate {
    static let defaultSize = NSSize(width: 560, height: 360)
    static let minSize = NSSize(width: 360, height: 220)

    let panel: ScratchPanel
    let content: MainViewController
    /// The status item button's frame in screen coordinates, for positioning.
    var anchorFrame: () -> NSRect? = { nil }
    /// Called whenever the window hides.
    var didHide: () -> Void = {}
    /// Called just before the window shows.
    var willShow: () -> Void = {}

    private var lastAutoHide = Date.distantPast
    private var isPositioning = false

    var isPinned: Bool {
        didSet {
            UserDefaults.standard.set(isPinned, forKey: DefaultsKey.pinned)
            applyMode()
            if isPinned { saveFrame() }
            content.refreshPinButton()
        }
    }

    init(content: MainViewController) {
        self.content = content
        isPinned = UserDefaults.standard.bool(forKey: DefaultsKey.pinned)
        panel = ScratchPanel(
            contentRect: NSRect(origin: .zero, size: Self.defaultSize),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true)
        super.init()
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            panel.standardWindowButton(button)?.isHidden = true
        }
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentMinSize = Self.minSize
        panel.contentViewController = content
        panel.setContentSize(savedSize())
        panel.delegate = self
        panel.onEscape = { [weak self] in
            guard let self, !self.isPinned else { return }
            self.hide()
        }
        content.isPinned = { [weak self] in self?.isPinned ?? false }
        content.onTogglePin = { [weak self] in self?.isPinned.toggle() }
        applyMode()
    }

    var isVisible: Bool { panel.isVisible }

    func toggle() {
        if panel.isVisible {
            hide()
        } else if Date().timeIntervalSince(lastAutoHide) > 0.3 {
            // A click on the menu bar icon first makes the panel lose focus and
            // auto-hide; don't immediately reopen it.
            show(newPage: false)
        }
    }

    func show(newPage: Bool) {
        willShow()
        content.prepareForShow(newPage: newPage)
        position()
        // A non-activating panel takes keyboard focus without making Scratchbar
        // the active app (macOS may refuse activation requests), so typing works
        // straight away and clicking back into the previous app just hides it.
        panel.makeKeyAndOrderFront(nil)
        content.focusEditor()
        startWatchingForOutsideActivity()
    }

    func hide() {
        guard panel.isVisible else { return }
        stopWatchingForOutsideActivity()
        content.willHide()
        panel.orderOut(nil)
        didHide()
    }

    // MARK: - Hiding when you go elsewhere (unpinned)

    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?

    /// A non-activating panel isn't reliably told when you move to another app,
    /// so watch for clicks outside Scratchbar and for other apps activating.
    /// (A global mouse monitor needs no Accessibility permission.)
    private func startWatchingForOutsideActivity() {
        stopWatchingForOutsideActivity()
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            self?.hideIfUnpinnedAndIdle()
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                self?.hideIfUnpinnedAndIdle()
            }
        }
    }

    private func stopWatchingForOutsideActivity() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        clickMonitor = nil
        activationObserver = nil
    }

    private func hideIfUnpinnedAndIdle() {
        guard !isPinned, panel.isVisible, panel.attachedSheet == nil else { return }
        lastAutoHide = Date()
        hide()
    }

    // MARK: - Mode and position

    private func applyMode() {
        panel.level = isPinned ? .normal : .floating
        panel.isMovableByWindowBackground = isPinned
        panel.isMovable = isPinned
    }

    private func position() {
        isPositioning = true
        defer { isPositioning = false }
        if isPinned, let saved = UserDefaults.standard.string(forKey: DefaultsKey.pinnedFrame) {
            panel.setFrame(Self.clampedToScreens(NSRectFromString(saved)), display: false)
            return
        }
        var frame = panel.frame
        frame.size = panel.frameRect(forContentRect: NSRect(origin: .zero, size: savedSize())).size
        if let anchor = anchorFrame() {
            frame.origin.x = anchor.midX - frame.width / 2
            frame.origin.y = anchor.minY - frame.height - 4
        } else if let screen = NSScreen.main {
            frame.origin.x = screen.visibleFrame.midX - frame.width / 2
            frame.origin.y = screen.visibleFrame.maxY - frame.height - 4
        }
        panel.setFrame(Self.clampedToScreens(frame), display: false)
    }

    /// Moves a frame so it lies within the visible area of the screen it most
    /// overlaps (or the main screen if it is off every screen).
    static func clampedToScreens(_ frame: NSRect) -> NSRect {
        let screens = NSScreen.screens
        let best = screens.max { a, b in
            a.visibleFrame.intersection(frame).area < b.visibleFrame.intersection(frame).area
        }
        let target = (best.map { $0.visibleFrame.intersection(frame).area > 0 } == true ? best : NSScreen.main ?? screens.first)?
            .visibleFrame ?? frame
        var f = frame
        f.size.width = min(f.width, target.width)
        f.size.height = min(f.height, target.height)
        f.origin.x = min(max(f.minX, target.minX), target.maxX - f.width)
        f.origin.y = min(max(f.minY, target.minY), target.maxY - f.height)
        return f
    }

    private func savedSize() -> NSSize {
        if let s = UserDefaults.standard.string(forKey: DefaultsKey.panelSize) {
            let size = NSSizeFromString(s)
            if size.width >= Self.minSize.width, size.height >= Self.minSize.height { return size }
        }
        return Self.defaultSize
    }

    private func saveFrame() {
        guard !isPositioning, panel.isVisible || isPinned else { return }
        let contentSize = panel.contentRect(forFrameRect: panel.frame).size
        UserDefaults.standard.set(NSStringFromSize(contentSize), forKey: DefaultsKey.panelSize)
        if isPinned {
            UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: DefaultsKey.pinnedFrame)
        }
    }

    // MARK: - NSWindowDelegate

    func windowDidResize(_ notification: Notification) { saveFrame() }
    func windowDidMove(_ notification: Notification) { saveFrame() }

    func windowDidResignKey(_ notification: Notification) {
        guard !isPinned else { return }
        // Let the key window settle: our own sheets and alerts don't count.
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isPinned, self.panel.isVisible,
                  self.panel.attachedSheet == nil, !self.panel.isKeyWindow,
                  NSApp.modalWindow == nil else { return }
            if let key = NSApp.keyWindow, key.sheetParent === self.panel { return }
            self.lastAutoHide = Date()
            self.hide()
        }
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
