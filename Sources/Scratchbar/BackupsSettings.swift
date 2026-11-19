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
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.style = .inset
        documentView = table
        hasVerticalScroller = true
        autohidesScrollers = true
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

/// Settings › Backups: pick a page (including deleted ones), pick a version, preview it, Restore.
final class BackupsSettings: NSViewController {
    private unowned let app: AppDelegate

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

    init(app: AppDelegate) {
        self.app = app
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let previewScroll = NSScrollView()
        previewScroll.documentView = preview
        previewScroll.hasVerticalScroller = true
        previewScroll.autohidesScrollers = true
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
        let content = NSView()
        for v in [pageList, versionList, previewScroll, restoreButton] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(v)
        }
        NSLayoutConstraint.activate([
            pageList.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            pageList.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            pageList.widthAnchor.constraint(equalToConstant: 180),
            pageList.heightAnchor.constraint(equalToConstant: 280),
            pageList.bottomAnchor.constraint(equalTo: restoreButton.topAnchor, constant: -12),
            versionList.leadingAnchor.constraint(equalTo: pageList.trailingAnchor, constant: 10),
            versionList.topAnchor.constraint(equalTo: pageList.topAnchor),
            versionList.widthAnchor.constraint(equalToConstant: 140),
            versionList.bottomAnchor.constraint(equalTo: pageList.bottomAnchor),
            previewScroll.leadingAnchor.constraint(equalTo: versionList.trailingAnchor, constant: 10),
            previewScroll.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            previewScroll.topAnchor.constraint(equalTo: pageList.topAnchor),
            previewScroll.bottomAnchor.constraint(equalTo: pageList.bottomAnchor),
            restoreButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            restoreButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),
            content.widthAnchor.constraint(equalToConstant: 600),
        ])
        view = content

        pageList.onSelect = { [weak self] row in self?.showVersions(row) }
        versionList.onSelect = { [weak self] row in self?.showPreview(row) }
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        reloadPages()
    }

    private func reloadPages() {
        pages = app.backups.pagesWithBackups()
        pageList.items = pages.map { $0.deleted ? "\($0.title) — Deleted" : $0.title }
        pageList.secondary = Set(pages.indices.filter { pages[$0].deleted })
        versions = []
        versionList.items = []
        preview.string = pages.isEmpty ? "No backups yet." : ""
        restoreButton.isEnabled = false
    }

    private func showVersions(_ row: Int) {
        versions = app.backups.versions(id: pages[row].id)
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
        app.restoreBackup(id: pages[pageRow].id, text: versions[versionRow].text)
        reloadPages()
    }
}
