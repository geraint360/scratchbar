import AppKit
import ScratchbarCore

/// The window's content: page list, editor, bottom bar and top-right controls.
/// Owns the page lifecycle: loading, saving, discarding empty pages, copy, delete.
final class MainViewController: NSViewController, NSTextViewDelegate, NSSearchFieldDelegate {
    var store: PageStoring
    let scheduler: SaveScheduler

    private let list = PageListView()
    private var scrollView: NSScrollView!
    private(set) var textView: PlainTextView!
    private let countLabel = NSTextField(labelWithString: "")
    private let copyButton = NSButton()
    private let shareButton = NSButton()
    private let pinButton = NSButton()
    private let settingsButton = NSButton()
    private let sidebarButton = NSButton()
    private let newButton = NSButton()
    private let searchField = NSSearchField()
    private var sidebarWidth: NSLayoutConstraint!
    private let divider = ColorView(color: Theme.border)
    private let dragHandle = DragHandle()
    /// Pages matching the search field, or nil when not searching.
    private var searchIDs: Set<String>?

    static let sidebarWidthRange: ClosedRange<CGFloat> = 120...360
    static let defaultSidebarWidth: CGFloat = 170
    /// Banners (sync conflicts etc.) are added here above the editor.
    let bannerStack = NSStackView()

    private(set) var pages: [Page] = []
    private(set) var currentID: String?
    private var countWork: DispatchWorkItem?

    /// Hooks provided by the app.
    var isPinned: () -> Bool = { false }
    var onTogglePin: () -> Void = {}
    var onShowSettings: () -> Void = {}
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
    /// False while the editor shows a message (downloading, read error) instead
    /// of the page's real text: such text must never be saved or "kept".
    private var editorHoldsPageText = false
    /// Called when an emptied page's file is discarded (so backups can mark it deleted).
    var didDiscard: (String) -> Void = { _ in }
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

    private static func symbol(_ name: String, _ description: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: description)?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
    }

    override func loadView() {
        let root = ColorView(color: Theme.editorBackground)
        root.frame = NSRect(x: 0, y: 0, width: 560, height: 360)

        let sidebar = ColorView(color: Theme.sidebarBackground)
        sidebar.clipsToBounds = true

        list.onSelect = { [weak self] id in self?.selectPage(id: id) }
        list.onDelete = { [weak self] id in self?.deletePage(id: id) }
        list.menuItems = { [weak self] id in self?.contextMenuItems(for: id) ?? [] }

        searchField.placeholderString = "Search pages"
        searchField.controlSize = .small
        searchField.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        searchField.sendsSearchStringImmediately = true
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self
        searchField.toolTip = "Search the text of every page (⇧⌘F)"

        let (scroll, tv) = PlainTextView.makeScrollable()
        scrollView = scroll
        textView = tv
        tv.delegate = self

        countLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        countLabel.textColor = Theme.secondaryText
        countLabel.lineBreakMode = .byTruncatingTail

        for (button, symbol, label, action, tip) in [
            (sidebarButton, "sidebar.left", "Hide page list", #selector(toggleSidebar(_:)), "Show or hide the page list (⌃⌘S)"),
            (newButton, "plus", "New page", #selector(newPage(_:)), "New page (⌘N)"),
            (copyButton, "doc.on.doc", "Copy page", #selector(copyPage(_:)), "Copy page (⇧⌘C)"),
            (shareButton, "square.and.arrow.up", "Share page", #selector(sharePage(_:)), "Share page (to DEVONthink, Mail…)"),
            (pinButton, "pin", "Pin", #selector(togglePin(_:)), ""),
            (settingsButton, "gearshape", "Settings", #selector(showSettings(_:)), "Settings (⌘,)"),
        ] {
            button.image = Self.symbol(symbol, label)
            button.isBordered = false
            button.contentTintColor = Theme.secondaryText
            button.target = self
            button.action = action
            button.toolTip = tip
            button.setAccessibilityLabel(label)
        }
        // Everything for the list and the window on the left; the page's own
        // controls on the right. All on one row in the title bar.
        let leftControls = NSStackView(views: [sidebarButton, newButton])
        leftControls.spacing = 14
        let controls = NSStackView(views: [copyButton, shareButton, pinButton, settingsButton])
        controls.spacing = 14

        bannerStack.orientation = .vertical
        bannerStack.spacing = 0

        dragHandle.onDrag = { [weak self] width in self?.setSidebarWidth(width, save: false) }
        dragHandle.currentWidth = { [weak self] in self?.sidebarWidth.constant ?? 0 }
        dragHandle.onEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Double(sidebarWidth.constant), forKey: DefaultsKey.sidebarWidth)
        }

        for v in [sidebar, list, searchField, divider, dragHandle, bannerStack, scroll, countLabel, controls, leftControls] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        root.addSubview(sidebar)
        sidebar.addSubview(list)
        sidebar.addSubview(searchField)
        [divider, bannerStack, scroll, countLabel, controls, leftControls, dragHandle].forEach(root.addSubview)

        let saved = UserDefaults.standard.double(forKey: DefaultsKey.sidebarWidth)
        let width = saved > 0 ? CGFloat(saved) : Self.defaultSidebarWidth
        let collapsed = UserDefaults.standard.bool(forKey: DefaultsKey.sidebarCollapsed)
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: collapsed ? 0 : width)

        let titleBar: CGFloat = 32
        NSLayoutConstraint.activate([
            sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            sidebarWidth,

            leftControls.centerYAnchor.constraint(equalTo: root.topAnchor, constant: titleBar / 2),
            leftControls.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),

            list.topAnchor.constraint(equalTo: sidebar.topAnchor, constant: titleBar + 2),
            list.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            list.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            list.bottomAnchor.constraint(equalTo: searchField.topAnchor, constant: -8),

            searchField.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -10),
            searchField.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor, constant: -8),

            divider.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            divider.topAnchor.constraint(equalTo: root.topAnchor),
            divider.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),

            dragHandle.centerXAnchor.constraint(equalTo: divider.centerXAnchor),
            dragHandle.topAnchor.constraint(equalTo: root.topAnchor, constant: titleBar),
            dragHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            dragHandle.widthAnchor.constraint(equalToConstant: 8),

            controls.centerYAnchor.constraint(equalTo: root.topAnchor, constant: titleBar / 2),
            controls.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),

            bannerStack.topAnchor.constraint(equalTo: root.topAnchor, constant: titleBar),
            bannerStack.leadingAnchor.constraint(equalTo: divider.trailingAnchor),
            bannerStack.trailingAnchor.constraint(equalTo: root.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: bannerStack.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: countLabel.topAnchor, constant: -6),

            countLabel.leadingAnchor.constraint(equalTo: divider.trailingAnchor, constant: 12),
            countLabel.trailingAnchor.constraint(lessThanOrEqualTo: root.trailingAnchor, constant: -12),
            countLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8),
        ])
        view = root
        refreshSidebarState()
        refreshPinButton()
    }

    // MARK: - Sidebar

    private var isSidebarCollapsed: Bool { sidebarWidth.constant == 0 }

    /// Keeps at least 200 pt for the editor.
    private func setSidebarWidth(_ width: CGFloat, save: Bool) {
        let maxWidth = min(Self.sidebarWidthRange.upperBound, view.bounds.width - 200)
        sidebarWidth.constant = min(max(width, Self.sidebarWidthRange.lowerBound), max(maxWidth, Self.sidebarWidthRange.lowerBound))
        if save { UserDefaults.standard.set(Double(sidebarWidth.constant), forKey: DefaultsKey.sidebarWidth) }
    }

    @objc func toggleSidebar(_ sender: Any?) {
        let collapsing = !isSidebarCollapsed
        if collapsing, view.window?.firstResponder === searchField.currentEditor() { focusEditor() }
        let saved = UserDefaults.standard.double(forKey: DefaultsKey.sidebarWidth)
        let target: CGFloat = collapsing ? 0 : (saved > 0 ? CGFloat(saved) : Self.defaultSidebarWidth)
        UserDefaults.standard.set(collapsing, forKey: DefaultsKey.sidebarCollapsed)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.allowsImplicitAnimation = true
            sidebarWidth.animator().constant = target
            view.layoutSubtreeIfNeeded()
        } completionHandler: { [weak self] in
            self?.refreshSidebarState()
        }
        if !collapsing { refreshSidebarState() }
    }

    private func refreshSidebarState() {
        let collapsed = isSidebarCollapsed
        divider.isHidden = collapsed
        dragHandle.isHidden = collapsed
        sidebarButton.setAccessibilityLabel(collapsed ? "Show page list" : "Hide page list")
    }

    // MARK: - Search

    @objc func focusSearch(_ sender: Any?) {
        if isSidebarCollapsed { toggleSidebar(nil) }
        view.window?.makeFirstResponder(searchField)
    }

    @objc private func searchChanged(_ sender: Any?) {
        updateSearch()
        showList(selectedID: currentID)
        refreshHighlights(scrollToFirst: true)
    }

    /// While searching, shades every match in the open page (and can scroll
    /// to the first one); otherwise clears the shading.
    private func refreshHighlights(scrollToFirst: Bool) {
        guard let textView else { return }
        let ranges = searchIDs == nil || !editorHoldsPageText ? [] : matchRanges(of: searchField.stringValue, in: textView.string)
        textView.highlight(ranges)
        if scrollToFirst, let first = ranges.first { textView.scrollRangeToVisible(first) }
    }

    /// Re-runs the search against every page's text (only while searching).
    private func updateSearch() {
        searchIDs = matchingPageIDs(query: searchField.stringValue, in: pages) { [unowned self] id in
            id == currentID && editorHoldsPageText ? textView.string : try? store.read(id)
        }
    }

    /// Shows the page list, narrowed to the search results if searching.
    private func showList(selectedID: String?) {
        list.show(searchIDs.map { ids in pages.filter { ids.contains($0.id) } } ?? pages, selectedID: selectedID)
    }

    // MARK: - ⌘[ / ⌘]

    @objc func previousPage(_ sender: Any?) { stepPage(-1) }
    @objc func nextPage(_ sender: Any?) { stepPage(1) }

    /// Moves through the pages in the order the list shows them.
    private func stepPage(_ offset: Int) {
        guard let id = adjacentPageID(in: list.pages.map(\.id), from: currentID, offset: offset) else {
            NSSound.beep()
            return
        }
        selectPage(id: id)
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
        pinButton.image = Self.symbol(pinned ? "pin.fill" : "pin", pinned ? "Unpin" : "Pin")
        pinButton.setAccessibilityLabel(pinned ? "Unpin" : "Pin")
        pinButton.contentTintColor = pinned ? Theme.accent : Theme.secondaryText
        pinButton.toolTip = pinned ? "Stays on screen — click to close when clicking elsewhere"
                                   : "Closes when you click elsewhere — click to keep on screen"
    }

    // MARK: - Loading

    /// Re-reads the page list from storage, keeping the current page selected.
    func reloadList() {
        // If listing fails, keep what we have rather than forgetting which pages exist.
        guard var loaded = try? store.list() else { return }
        scheduler.knownOnDisk = Set(loaded.map(\.id))
        // A new, unsaved page only exists in memory: keep it in the list.
        if let currentID, !loaded.contains(where: { $0.id == currentID }),
           let unsaved = pages.first(where: { $0.id == currentID }) {
            loaded.insert(unsaved, at: 0)
        }
        pages = loaded
        if searchIDs != nil { updateSearch() }
        showList(selectedID: currentID)
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
        // Decide from the read itself, not from the cached list of pages on disk.
        do {
            let text = try store.read(id)
            scheduler.knownOnDisk.insert(id)
            showPageText(text)
        } catch PageStoreError.notDownloaded {
            editorHoldsPageText = false
            setEditorText("Downloading from iCloud…", editable: false)
        } catch where Self.isMissingFile(error) && !scheduler.knownOnDisk.contains(id) {
            showPageText("")  // new page, not on disk yet
        } catch {
            // Never show an editable blank page for a file we failed to read:
            // typing would overwrite it.
            editorHoldsPageText = false
            setEditorText("Couldn't open this page:\n\(error.localizedDescription)", editable: false)
        }
        refreshHighlights(scrollToFirst: true)
        showList(selectedID: id)
    }

    private func showPageText(_ text: String) {
        lastSavedText = text
        editorHoldsPageText = true
        setEditorText(text, editable: true)
    }

    private static func isMissingFile(_ error: Error) -> Bool {
        var e: NSError? = error as NSError
        if case PageStoreError.coordination(let inner) = error { e = inner }
        while let current = e {
            if current.domain == NSCocoaErrorDomain && current.code == NSFileReadNoSuchFileError { return true }
            if current.domain == NSPOSIXErrorDomain && current.code == Int(ENOENT) { return true }
            e = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
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
                showList(selectedID: id)
            }
            return
        }
        leaveCurrentPage()
        // A new page wouldn't match the search: clear it so the page shows.
        if searchIDs != nil {
            searchField.stringValue = ""
            searchIDs = nil
        }
        let id = PageStore.newID()
        pages.insert(Page(id: id, modified: Date(), title: "Empty"), at: 0)
        currentID = id
        UserDefaults.standard.set(id, forKey: DefaultsKey.lastPageID)
        clearBanner()
        showPageText("")
        showList(selectedID: id)
    }

    /// Flushes saves and discards the current page if it is empty.
    func leaveCurrentPage() {
        scheduler.flush()
        guard let id = currentID, currentText.isEmpty, textView.isEditable, editorHoldsPageText else { return }
        scheduler.cancel(id: id)
        if scheduler.knownOnDisk.contains(id) {
            // Its last text was backed up when it was emptied (see save).
            try? store.remove(id)
            scheduler.knownOnDisk.remove(id)
            didDiscard(id)
        }
        pages.removeAll { $0.id == id }
        currentID = nil
        showList(selectedID: nil)
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
        if id == currentID, !editorHoldsPageText { return }
        if id == currentID, bannerKind == nil, scheduler.knownOnDisk.contains(id) {
            let disk = try? store.read(id)
            if saveWouldOverwriteRemoteChange(diskText: disk, lastSavedText: lastSavedText, newText: text), let disk {
                showEditedBanner(id: id, other: disk)
                return
            }
        }
        // Emptying a page is how it gets discarded: keep its last text first.
        if id == currentID, text.isEmpty, !lastSavedText.isEmpty {
            backup(id, lastSavedText, .beforeDelete)
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
            // A message in the editor (downloading, read error) is never "your edits".
            let dirty = editorHoldsPageText && (scheduler.hasPendingChanges || textView.string != lastSavedText)
            actions += decide(event, openPageID: currentID, editorDirty: dirty)
        }
        guard !actions.isEmpty else { return }
        if actions.contains(.reloadList) { reloadList() }
        guard let id = currentID else { return }
        if actions.contains(.showDeletedBanner) {
            showDeletedBanner(id: id)
        } else if actions.contains(.showEditedBanner), let otherText, editorHoldsPageText {
            showEditedBanner(id: id, other: otherText)
        } else if actions.contains(.showEditedBanner), !editorHoldsPageText {
            load(id: id)
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
        // Back up both versions now: the editor holds the only copy of this
        // Mac's unsaved edits until you choose.
        backup(id, textView.string, .beforeConflict)
        backup(id, other, .beforeConflict)
        let banner = BannerView(message: "Edited on another Mac", buttons: [
            ("Keep This Mac's", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepThisMac) }),
            ("Keep Other", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepOther) }),
            ("Keep Both", { [weak self] in self?.resolveEdited(id: id, other: other, choice: .keepBoth) }),
        ])
        showBanner(banner, kind: .edited(other: other))
    }

    private func resolveEdited(id: String, other: String, choice: ConflictChoice) {
        guard id == currentID, editorHoldsPageText else { return clearBanner() }
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
                showList(selectedID: id)
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
            var parts = ["\(words) \(words == 1 ? "word" : "words")", "\(chars) \(chars == 1 ? "character" : "characters")"]
            if let id = self.currentID, self.scheduler.knownOnDisk.contains(id) || !text.isEmpty,
               let modified = self.pages.first(where: { $0.id == id })?.modified {
                parts.insert("Edited \(editedDescription(modified))", at: 0)
            }
            self.countLabel.stringValue = parts.joined(separator: " · ")
            self.refreshHighlights(scrollToFirst: false)
        }
        countWork = work
        if now { work.perform() } else { DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work) }
    }

    // MARK: - Duplicate, save a copy, share

    /// The page a command applies to: the right-clicked row's page when it
    /// comes from the list's menu, otherwise the open page.
    private func pageID(from sender: Any?) -> String? {
        (sender as? NSMenuItem)?.representedObject as? String ?? currentID
    }

    /// The text of page `id`: the editor's text if it's open, else from disk.
    private func text(of id: String) -> String? {
        if id == currentID { return editorHoldsPageText ? textView.string : nil }
        return try? store.read(id)
    }

    private func contextMenuItems(for id: String) -> [NSMenuItem] {
        [("Duplicate", #selector(duplicatePage(_:))), ("Save a Copy…", #selector(saveCopy(_:))),
         ("Share…", #selector(sharePage(_:))), (nil, nil), ("Delete…", #selector(deleteFromMenu(_:)))]
            .map { title, action in
                guard let title, let action else { return .separator() }
                let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
                item.target = self
                item.representedObject = id
                return item
            }
    }

    /// ⌘D: a copy of the page, opened at the top of the list.
    @objc func duplicatePage(_ sender: Any?) {
        guard let id = pageID(from: sender), let text = text(of: id), !text.isEmpty else {
            NSSound.beep()
            return
        }
        if searchIDs != nil {
            searchField.stringValue = ""
            searchIDs = nil
        }
        addPage(text: text, select: true)
        focusEditor()
    }

    /// ⌘S: writes a copy of the page to a .txt file you choose. The page
    /// itself stays in Scratchbar.
    @objc func saveCopy(_ sender: Any?) {
        guard let id = pageID(from: sender), let text = text(of: id), let window = view.window else {
            NSSound.beep()
            return
        }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportFileName(for: text)
        panel.allowedContentTypes = [.plainText]
        panel.isExtensionHidden = false
        if let folder = UserDefaults.standard.url(forKey: DefaultsKey.lastSaveFolder) { panel.directoryURL = folder }
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try Data(text.utf8).write(to: url, options: .atomic)
                UserDefaults.standard.set(url.deletingLastPathComponent(), forKey: DefaultsKey.lastSaveFolder)
            } catch {
                let alert = NSAlert(error: error)
                alert.messageText = "Couldn't save a copy of this page."
                alert.beginSheetModal(for: window)
            }
        }
    }

    /// Shares the page as a .txt file named after it, so apps like
    /// DEVONthink and Mail keep its title.
    @objc func sharePage(_ sender: Any?) {
        guard let id = pageID(from: sender), let text = text(of: id) else {
            NSSound.beep()
            return
        }
        let anchor: NSView = sender is NSMenuItem ? (list.rowView(for: id) ?? shareButton) : shareButton
        // One reused folder, so shared copies don't pile up in the temp folder.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Scratchbar Share", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        let url = folder.appendingPathComponent(exportFileName(for: text))
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("Scratchbar: couldn't prepare page for sharing: \(error)")
            NSSound.beep()
            return
        }
        NSSharingServicePicker(items: [url]).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    @objc private func deleteFromMenu(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? String else { return }
        deletePage(id: id)
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
        copyButton.image = Self.symbol("checkmark", "Copied")
        copyButton.contentTintColor = Theme.accent
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.copyButton.image = Self.symbol("doc.on.doc", "Copy page")
            self?.copyButton.contentTintColor = Theme.secondaryText
        }
    }

    /// The ✕ on a sidebar row: open that page, then ask as ⌘⌫ does.
    func deletePage(id: String) {
        if id != currentID { selectPage(id: id) }
        guard id == currentID else { return }
        deletePage(nil)
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
        // ⌘D chooses Delete, as in other Mac apps (Return still does too).
        let alertWindow = alert.window
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak alertWindow, weak window] event in
            guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
                  event.charactersIgnoringModifiers?.lowercased() == "d",
                  let alertWindow, alertWindow.isVisible, let window else { return event }
            window.endSheet(alertWindow, returnCode: .alertFirstButtonReturn)
            return nil
        }
        alert.beginSheetModal(for: window) { [weak self] response in
            if let monitor { NSEvent.removeMonitor(monitor) }
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

    @objc func showSettings(_ sender: Any?) {
        onShowSettings()
    }

    @objc func biggerText(_ sender: Any?) { textView.applyFontSize(textView.fontSize + 1) }
    @objc func smallerText(_ sender: Any?) { textView.applyFontSize(textView.fontSize - 1) }
    @objc func actualSizeText(_ sender: Any?) { textView.applyFontSize(PlainTextView.defaultFontSize) }
}

extension MainViewController {
    /// Return in the search field opens the first match; ↓ moves into the list.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard control === searchField, selector == #selector(NSResponder.insertNewline(_:)) else { return false }
        if let first = list.pages.first, !list.pages.contains(where: { $0.id == currentID }) {
            selectPage(id: first.id)
        }
        focusEditor()
        return true
    }
}

/// The invisible strip over the sidebar's edge that you drag to resize it.
final class DragHandle: NSView {
    var onDrag: (CGFloat) -> Void = { _ in }
    var onEnd: () -> Void = {}
    var currentWidth: () -> CGFloat = { 0 }
    private var start: (x: CGFloat, width: CGFloat)?

    override var mouseDownCanMoveWindow: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDown(with event: NSEvent) {
        start = (event.locationInWindow.x, currentWidth())
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        onDrag(start.width + event.locationInWindow.x - start.x)
    }

    override func mouseUp(with event: NSEvent) {
        start = nil
        onEnd()
    }
}
