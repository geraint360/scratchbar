import AppKit
import ScratchbarCore

/// The window's content: page list, editor, bottom bar and top-right controls.
/// Owns the page lifecycle: loading, saving, discarding empty pages, copy, delete.
final class MainViewController: NSViewController, NSTextViewDelegate {
    var store: PageStoring
    let scheduler: SaveScheduler

    private let list = PageListView()
    private var scrollView: NSScrollView!
    private(set) var textView: PlainTextView!
    private let countLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let deleteButton = NSButton(title: "Delete", target: nil, action: nil)
    private let pinButton = NSButton()
    private let menuButton = NSButton()
    /// Banners (sync conflicts etc.) are added here above the editor.
    let bannerStack = NSStackView()

    private(set) var pages: [Page] = []
    private(set) var currentID: String?
    private var countWork: DispatchWorkItem?

    /// Hooks provided by the app.
    var isPinned: () -> Bool = { false }
    var onTogglePin: () -> Void = {}
    var menuProvider: () -> NSMenu = { NSMenu() }
    /// Called after a page's text has been written (for backups etc.).
    var onSaved: (String, String) -> Void = { _, _ in }
    /// Called just before a page is deleted, with its id and text.
    var willDelete: (String, String) -> Void = { _, _ in }
    /// Takes a backup (used around sync conflicts and remote deletes).
    var backup: (String, String, BackupReason) -> Void = { _, _, _ in }
    /// Marks iCloud conflict versions of a page as resolved.
    var resolveVersionConflicts: (String) -> Void = { _ in }

    /// The text last read from or written to disk for the current page.
    private var lastSavedText = ""
    private var bannerKind: BannerKind?
    private enum BannerKind { case edited(other: String), deleted }

    init(store: PageStoring) {
        self.store = store
        var saveHandler: ((String, String) -> Void)?
        scheduler = SaveScheduler { id, text in saveHandler?(id, text) }
        super.init(nibName: nil, bundle: nil)
        saveHandler = { [weak self] id, text in self?.save(id: id, text: text) }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: - View

    /// Behind everything; visible only with Translucent Background on.
    private let translucentBackground = NSVisualEffectView()

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 360))
        translucentBackground.material = .popover
        translucentBackground.blendingMode = .behindWindow
        translucentBackground.state = .active
        translucentBackground.autoresizingMask = [.width, .height]
        translucentBackground.frame = root.bounds
        root.addSubview(translucentBackground)

        let sidebar = NSVisualEffectView()
        sidebar.material = .sidebar
        sidebar.blendingMode = .behindWindow
        let newButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "New page")!,
                                 target: self, action: #selector(newPage(_:)))
        newButton.title = "New"
        newButton.imagePosition = .imageLeading
        newButton.bezelStyle = .accessoryBarAction
        newButton.toolTip = "New page (⌘N)"

        list.onSelect = { [weak self] id in self?.selectPage(id: id) }

        let (scroll, tv) = PlainTextView.makeScrollable()
        scrollView = scroll
        textView = tv
        tv.delegate = self

        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = .secondaryLabelColor

        for (button, action, tip) in [(copyButton, #selector(copyPage(_:)), "Copy page (⇧⌘C)"),
                                      (deleteButton, #selector(deletePage(_:)), "Delete page (⌘⌫)")] {
            button.target = self
            button.action = action
            button.bezelStyle = .push
            button.controlSize = .small
            button.toolTip = tip
        }

        pinButton.bezelStyle = .accessoryBarAction
        pinButton.isBordered = false
        pinButton.target = self
        pinButton.action = #selector(togglePin(_:))
        menuButton.bezelStyle = .accessoryBarAction
        menuButton.isBordered = false
        menuButton.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Menu")
        menuButton.target = self
        menuButton.action = #selector(showMenu(_:))
        menuButton.toolTip = "Settings"

        bannerStack.orientation = .vertical
        bannerStack.spacing = 0

        let divider = NSBox()
        divider.boxType = .separator

        for v in [sidebar, newButton, list, divider, bannerStack, scroll, countLabel, copyButton, deleteButton, pinButton, menuButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        root.addSubview(sidebar)
        sidebar.addSubview(newButton)
        sidebar.addSubview(list)
        [divider, bannerStack, scroll, countLabel, copyButton, deleteButton, pinButton, menuButton].forEach(root.addSubview)

        let titleBar: CGFloat = 28
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebar.widthAnchor.constraint(equalToConstant: 170),

            newButton.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: titleBar),
            newButton.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 8),

            list.topAnchor.constraint(equalTo: newButton.bottomAnchor, constant: 6),
            list.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),

            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            menuButton.topAnchor.constraint(equalTo: root.topAnchor, constant: 5),
            menuButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -8),
            pinButton.centerYAnchor.constraint(equalTo: menuButton.centerYAnchor),
            pinButton.trailingAnchor.constraint(equalTo: menuButton.leadingAnchor, constant: -6),

            bannerStack.topAnchor.constraint(equalTo: root.topAnchor, constant: titleBar),
            bannerStack.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            bannerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: bannerStack.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: deleteButton.topAnchor, constant: -6),

            deleteButton.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            deleteButton.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
            copyButton.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -6),
            copyButton.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
            countLabel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 10),
            countLabel.centerYAnchor.constraint(equalTo: deleteButton.centerYAnchor),
        ])
        view = root
        refreshPinButton()
    }

    /// Translucent: the desktop shows through the editor area.
    func applyTranslucency(_ on: Bool) {
        _ = view
        translucentBackground.isHidden = !on
        view.window?.isOpaque = !on
        view.window?.backgroundColor = on ? .clear : .windowBackgroundColor
    }

    /// Adds a page with `text` (from the URL scheme) and optionally opens it.
    func addPage(text: String, select: Bool) {
        _ = view
        let id = PageStore.newID()
        do {
            try store.write(id, text: text)
        } catch {
            NSLog("Scratchbar: couldn't add page from URL: \(error)")
            return
        }
        if select {
            leaveCurrentPage()
            currentID = nil
            reloadList()
            load(id: id)
        } else {
            reloadList()
        }
    }

    func refreshPinButton() {
        let pinned = isPinned()
        pinButton.image = NSImage(systemSymbolName: pinned ? "pin.fill" : "pin",
                                  accessibilityDescription: pinned ? "Unpin" : "Pin")
        pinButton.contentTintColor = pinned ? .controlAccentColor : .secondaryLabelColor
        pinButton.toolTip = pinned ? "Stays on screen — click to close when clicking elsewhere"
                                   : "Closes when you click elsewhere — click to keep on screen"
    }

    // MARK: - Loading

    /// Re-reads the page list from storage, keeping the current page selected.
    func reloadList() {
        var loaded = (try? store.list()) ?? []
        scheduler.knownOnDisk = Set(loaded.map(\.id))
        // A new, unsaved page only exists in memory: keep it in the list.
        if let currentID, !loaded.contains(where: { $0.id == currentID }),
           let unsaved = pages.first(where: { $0.id == currentID }) {
            loaded.insert(unsaved, at: 0)
        }
        pages = loaded
        list.show(pages, selectedID: currentID)
    }

    /// Called whenever the window is about to show.
    func prepareForShow(newPage: Bool) {
        _ = view
        if pages.isEmpty || currentID == nil { reloadList() }
        if newPage {
            createNewPage()
        } else if currentID == nil {
            let last = UserDefaults.standard.string(forKey: DefaultsKey.lastPageID)
            if let first = pages.first(where: { $0.id == last }) ?? pages.first {
                load(id: first.id)
            } else {
                createNewPage()
            }
        }
        refreshPinButton()
    }

    func focusEditor() {
        view.window?.makeFirstResponder(textView)
    }

    var currentText: String { textView?.string ?? "" }

    // MARK: - Page lifecycle

    func selectPage(id: String) {
        guard id != currentID else { return }
        leaveCurrentPage()
        load(id: id)
        focusEditor()
    }

    private func load(id: String) {
        clearBanner()
        currentID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.lastPageID)
        if scheduler.knownOnDisk.contains(id) {
            do {
                let text = try store.read(id)
                lastSavedText = text
                setEditorText(text, editable: !(pages.first { $0.id == id }?.isDownloading ?? false))
            } catch where pages.first(where: { $0.id == id })?.isDownloading == true {
                setEditorText("Downloading from iCloud…", editable: false)
            } catch {
                // Never show an editable blank page for a file we failed to read:
                // typing would overwrite it.
                setEditorText("Couldn't open this page:\n\(error.localizedDescription)", editable: false)
            }
        } else {
            lastSavedText = ""
            setEditorText("", editable: true)  // new page, not on disk yet
        }
        list.show(pages, selectedID: id)
    }

    private func setEditorText(_ text: String, editable: Bool) {
        textView.isEditable = editable
        textView.string = text
        // Put the cursor at the end, ready to add to the page.
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.undoManager?.removeAllActions()
        updateCounts(now: true)
    }

    /// Makes a new in-memory page and shows it. If the current page is already
    /// empty it is reused rather than making another.
    func createNewPage() {
        if currentID != nil, currentText.isEmpty, textView.isEditable {
            if let id = currentID, let idx = pages.firstIndex(where: { $0.id == id }), idx != 0 {
                pages.insert(pages.remove(at: idx), at: 0)
                list.show(pages, selectedID: id)
            }
            return
        }
        leaveCurrentPage()
        let id = PageStore.newID()
        pages.insert(Page(id: id, modified: Date(), title: "Empty"), at: 0)
        currentID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.lastPageID)
        setEditorText("", editable: true)
        list.show(pages, selectedID: id)
    }

    /// Flushes saves and discards the current page if it is empty.
    func leaveCurrentPage() {
        scheduler.flush()
        guard let id = currentID, currentText.isEmpty, textView.isEditable else { return }
        scheduler.cancel(id: id)
        if scheduler.knownOnDisk.contains(id) {
            try? store.remove(id)
            scheduler.knownOnDisk.remove(id)
        }
        pages.removeAll { $0.id == id }
        currentID = nil
        list.show(pages, selectedID: nil)
    }

    /// Writes `text` as page `id` (restoring a backup) and shows it.
    func restorePage(id: String, text: String) {
        scheduler.flush()
        do {
            try store.write(id, text: text)
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Couldn't restore this page."
            if let window = view.window { alert.beginSheetModal(for: window) }
            return
        }
        if currentID != id { leaveCurrentPage() }
        currentID = nil
        reloadList()
        load(id: id)
        focusEditor()
    }

    /// After the storage folder changes (sync on/off): forget the current page
    /// and reload from the new store.
    func resetForStorageChange() {
        scheduler.flush()
        currentID = nil
        pages = []
        scheduler.knownOnDisk = []
        if view.window?.isVisible == true {
            prepareForShow(newPage: false)
        }
    }

    /// Called when the window hides: save, and drop an empty page.
    func willHide() {
        leaveCurrentPage()
    }

    func flushAll() {
        scheduler.flush()
    }

    private func save(id: String, text: String) {
        if id == currentID, bannerKind == nil, scheduler.knownOnDisk.contains(id) {
            let disk = try? store.read(id)
            if saveWouldOverwriteRemoteChange(diskText: disk, lastSavedText: lastSavedText, newText: text), let disk {
                showEditedBanner(id: id, other: disk)
                return
            }
        }
        do {
            try store.write(id, text: text)
            if id == currentID { lastSavedText = text }
            onSaved(id, text)
        } catch {
            NSLog("Scratchbar: failed to save page \(id): \(error)")
        }
    }

    // MARK: - Changes from elsewhere (iCloud, Finder, other editors)

    /// `conflictTexts` holds the other Mac's text for pages with iCloud conflicts.
    func handleRemote(_ events: [RemoteEvent], conflictTexts: [String: String]) {
        var actions: [RemoteAction] = []
        var otherText: String?
        for event in events {
            if event.id == currentID, case .modified = event {
                // Our own saves show up here too: ignore anything we already have.
                let disk = (try? store.read(event.id)) ?? ""
                if disk == textView.string || disk == lastSavedText { continue }
                otherText = disk
            }
            if case .conflict(let id) = event, id == currentID { otherText = conflictTexts[id] }
            let dirty = scheduler.hasPendingChanges || textView.string != lastSavedText
            actions += decide(event, openPageID: currentID, editorDirty: dirty)
        }
        guard !actions.isEmpty else { return }
        if actions.contains(.reloadList) { reloadList() }
        guard let id = currentID else { return }
        if actions.contains(.showDeletedBanner) {
            showDeletedBanner(id: id)
        } else if actions.contains(.showEditedBanner), let otherText {
            showEditedBanner(id: id, other: otherText)
        } else if actions.contains(.reloadOpenPage), bannerKind == nil {
            let selection = textView.selectedRange()
            load(id: id)
            if NSMaxRange(selection) <= (textView.string as NSString).length { textView.setSelectedRange(selection) }
        }
    }

    private func clearBanner() {
        bannerStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        bannerKind = nil
    }

    private func showBanner(_ banner: BannerView, kind: BannerKind) {
        clearBanner()
        bannerKind = kind
        bannerStack.addArrangedSubview(banner)
        banner.widthAnchor.constraint(equalTo: bannerStack.widthAnchor).isActive = true
        // Freeze the editor until you choose, so nothing overwrites either version.
        textView.isEditable = false
    }

    private func showEditedBanner(id: String, other: String) {
        scheduler.cancel(id: id)
        let banner = BannerView(message: "Edited on another Mac", buttons: [
            ("Keep This Mac's", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepThisMac) }),
            ("Keep Other", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepOther) }),
            ("Keep Both", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepBoth) }),
        ])
        showBanner(banner, kind: .edited(other: other))
    }

    private func resolveEdited(id: String, other: String, choice: ConflictChoice) {
        guard id == currentID else { return clearBanner() }
        let current = textView.string
        backup(id, current, .beforeConflict)
        backup(id, other, .beforeConflict)
        let result = resolveConflict(current: current, other: other, choice: choice)
        do {
            try store.write(id, text: result)
        } catch {
            NSLog("Scratchbar: couldn't save resolved page \(id): \(error)")
            return
        }
        resolveVersionConflicts(id)
        lastSavedText = result
        clearBanner()
        if textView.string != result { setEditorText(result, editable: true) } else { textView.isEditable = true }
        reloadList()
        focusEditor()
    }

    private func showDeletedBanner(id: String) {
        scheduler.cancel(id: id)
        let text = textView.string
        backup(id, text, .remoteDelete)
        scheduler.knownOnDisk.remove(id)
        let banner = BannerView(message: "Deleted on another Mac", buttons: [
            ("Restore", { [weak self] in self?.restoreRemotelyDeleted(id: id, text: text) }),
            ("Close", { [weak self] in self?.closeRemotelyDeleted(id: id) }),
        ])
        showBanner(banner, kind: .deleted)
    }

    private func restoreRemotelyDeleted(id: String, text: String) {
        do {
            try store.write(id, text: text)
        } catch {
            NSLog("Scratchbar: couldn't restore page \(id): \(error)")
            return
        }
        scheduler.knownOnDisk.insert(id)
        lastSavedText = text
        clearBanner()
        textView.isEditable = true
        reloadList()
        focusEditor()
    }

    private func closeRemotelyDeleted(id: String) {
        clearBanner()
        pages.removeAll { $0.id == id }
        currentID = nil
        showAfterRemoval()
    }

    // MARK: - Editing

    func textDidChange(_ notification: Notification) {
        guard let id = currentID else { return }
        let text = textView.string
        scheduler.textChanged(id: id, text: text)
        let title = pageTitle(for: text)
        if let idx = pages.firstIndex(where: { $0.id == id }) {
            pages[idx].title = title
            pages[idx].modified = Date()
            if idx != 0 {
                pages.insert(pages.remove(at: idx), at: 0)
                list.show(pages, selectedID: id)
            } else {
                list.updateTitle(of: id, to: title)
            }
        }
        updateCounts(now: false)
    }

    private func updateCounts(now: Bool) {
        countWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let text = self.textView.string
            var words = 0
            var inWord = false
            for scalar in text.unicodeScalars {
                let isSpace = CharacterSet.whitespacesAndNewlines.contains(scalar)
                if !isSpace && !inWord { words += 1 }
                inWord = !isSpace
            }
            let chars = text.count
            self.countLabel.stringValue = "\(words) \(words == 1 ? "word" : "words") · \(chars) \(chars == 1 ? "character" : "characters")"
        }
        countWork = work
        if now { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work) }
    }

    // MARK: - Actions

    @objc func newPage(_ sender: Any?) {
        createNewPage()
        focusEditor()
    }

    @objc func copyPage(_ sender: Any?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(currentText, forType: .string)
        copyButton.title = "Copied"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.copyButton.title = "Copy" }
    }

    @objc func deletePage(_ sender: Any?) {
        guard let id = currentID else { return }
        // An empty page has nothing to lose: discard it without asking.
        if currentText.isEmpty {
            leaveCurrentPage()
            showAfterRemoval()
            return
        }
        guard let window = view.window else { return }
        let title = pages.first(where: { $0.id == id })?.title ?? pageTitle(for: currentText)
        let alert = NSAlert()
        alert.messageText = "Delete “\(title)”?"
        alert.informativeText = "It will be moved to the Trash."
        let delete = alert.addButton(withTitle: "Delete")
        delete.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.performDelete(id: id)
        }
    }

    private func performDelete(id: String) {
        let text = currentText
        scheduler.flush()
        willDelete(id, text)
        if scheduler.knownOnDisk.contains(id) {
            do {
                try store.delete(id)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn't delete this page."
                if let window = view.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
                return
            }
            scheduler.knownOnDisk.remove(id)
        }
        pages.removeAll { $0.id == id }
        currentID = nil
        showAfterRemoval()
    }

    private func showAfterRemoval() {
        if let next = pages.first {
            load(id: next.id)
        } else {
            createNewPage()
        }
        focusEditor()
    }

    @objc func togglePin(_ sender: Any?) {
        onTogglePin()
        refreshPinButton()
    }

    @objc private func showMenu(_ sender: NSButton) {
        let menu = menuProvider()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 4), in: sender)
    }

    @objc func biggerText(_ sender: Any?) { textView.applyFontSize(textView.fontSize + 1) }
    @objc func smallerText(_ sender: Any?) { textView.applyFontSize(textView.fontSize - 1) }
    @objc func actualSizeText(_ sender: Any?) { textView.applyFontSize(PlainTextView.defaultFontSize) }
}
