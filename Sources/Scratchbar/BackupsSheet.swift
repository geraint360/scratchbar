import AppKit
import ScratchbarCore

/// A one-column list of strings, used twice in the Backups sheet.
private final class SimpleList: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var items: [String] = [] { didSet { table.reloadData() } }
    var secondary: Set<Int> = []
    var onSelect: (Int) -> Void = { _ in }

    init(label: String) {
        super.init(frame: .zero)
        let column = NSTableColumn(identifier: .init("c"))
        column.title = label
        table.addTableColumn(column)
        table.dataSource = self
        table.delegate = self
        table.style = .inset
        documentView = table
        hasVerticalScroller = true
        borderType = .bezelBorder
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let label = NSTextField(labelWithString: items[row])
        label.lineBreakMode = .byTruncatingTail
        label.textColor = secondary.contains(row) ? .secondaryLabelColor : .labelColor
        return label
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if table.selectedRow >= 0 { onSelect(table.selectedRow) }
    }
}

/// "Backups…": pick a page (including deleted ones), pick a version, preview it, Restore.
final class BackupsSheet: NSWindowController {
    private let backups: BackupStore
    private let restore: (String, String) -> Void

    private let pageList = SimpleList(label: "Page")
    private let versionList = SimpleList(label: "Saved")
    private let preview = NSTextView()
    private let restoreButton = NSButton(title: "Restore", target: nil, action: nil)

    private var pages: [(id: String, title: String, deleted: Bool, newest: Date)] = []
    private var versions: [BackupVersion] = []

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    /// `restore(id, text)` writes the text back as that page.
    init(backups: BackupStore, restore: @escaping (String, String) -> Void) {
        self.backups = backups
        self.restore = restore
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 680, height: 400),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: true)
        super.init(window: window)

        let previewScroll = NSScrollView()
        previewScroll.documentView = preview
        previewScroll.hasVerticalScroller = true
        previewScroll.borderType = .bezelBorder
        preview.isEditable = false
        preview.isRichText = false
        preview.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        preview.autoresizingMask = [.width]
        preview.isVerticallyResizable = true
        preview.textContainer?.widthTracksTextView = true

        restoreButton.target = self
        restoreButton.action = #selector(restoreSelected)
        restoreButton.isEnabled = false
        restoreButton.bezelStyle = .rounded
        let close = NSButton(title: "Close", target: self, action: #selector(closeSheet))
        close.keyEquivalent = "\u{1b}"
        close.bezelStyle = .rounded

        let content = NSView()
        for v in [pageList, versionList, previewScroll, restoreButton, close] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            pageList.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            pageList.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            pageList.widthAnchor.constraint(equalToConstant: 190),
            pageList.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -12),
            versionList.leadingAnchor.constraint(equalTo: pageList.trailingAnchor, constant: 10),
            versionList.topAnchor.constraint(equalTo: pageList.topAnchor),
            versionList.widthAnchor.constraint(equalToConstant: 150),
            versionList.bottomAnchor.constraint(equalTo: pageList.bottomAnchor),
            previewScroll.leadingAnchor.constraint(equalTo: versionList.trailingAnchor, constant: 10),
            previewScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            previewScroll.topAnchor.constraint(equalTo: pageList.topAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: pageList.bottomAnchor),
            close.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            close.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            restoreButton.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            restoreButton.centerYAnchor.constraint(equalTo: close.centerYAnchor),
        ])
        window.contentView = content
        window.contentMinSize = NSSize(width: 560, height: 300)

        pageList.onSelect = { [weak self] row in self?.showVersions(row) }
        versionList.onSelect = { [weak self] row in self?.showPreview(row) }
        reloadPages()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func begin(on parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func reloadPages() {
        pages = backups.pagesWithBackups()
        pageList.items = pages.map { $0.deleted ? "\($0.title) — Deleted" : $0.title }
        pageList.secondary = Set(pages.indices.filter { pages[$0].deleted })
        versions = []
        versionList.items = []
        preview.string = pages.isEmpty ? "No backups yet." : ""
        restoreButton.isEnabled = false
    }

    private func showVersions(_ row: Int) {
        versions = backups.versions(id: pages[row].id)
        versionList.items = versions.map { Self.dateFormatter.string(from: $0.date) }
        preview.string = ""
        restoreButton.isEnabled = false
        if !versions.isEmpty {
            versionList.table.selectRowIndexes([0], byExtendingSelection: false)
        }
    }

    private func showPreview(_ row: Int) {
        preview.string = versions[row].text
        restoreButton.isEnabled = true
    }

    @objc private func restoreSelected() {
        let pageRow = pageList.table.selectedRow, versionRow = versionList.table.selectedRow
        guard pages.indices.contains(pageRow), versions.indices.contains(versionRow) else { return }
        restore(pages[pageRow].id, versions[versionRow].text)
        closeSheet()
    }

    @objc private func closeSheet() {
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window)
    }
}
