import AppKit
import ScratchbarCore

/// The sidebar list of page titles. Each row shows an ✕ (delete) when it is
/// selected or under the pointer, like BBEdit's open-documents list.
final class PageListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private(set) var pages: [Page] = []
    private var suppressSelectionCallback = false

    /// Called when the user picks a different page.
    var onSelect: ((String) -> Void)?
    /// Called when the user clicks a row's ✕.
    var onDelete: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: .init("title"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 0, height: 2)
        table.backgroundColor = .clear
        table.gridStyleMask = []
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        documentView = table
        hasVerticalScroller = true
        autohidesScrollers = true
        drawsBackground = false
        borderType = .noBorder
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    /// Replaces the list and selects `selectedID` without calling `onSelect`.
    func show(_ pages: [Page], selectedID: String?) {
        self.pages = pages
        suppressSelectionCallback = true
        table.reloadData()
        if let selectedID, let row = pages.firstIndex(where: { $0.id == selectedID }) {
            table.selectRowIndexes([row], byExtendingSelection: false)
            table.scrollRowToVisible(row)
        } else {
            table.deselectAll(nil)
        }
        suppressSelectionCallback = false
    }

    /// Updates one row's title in place (cheap; used while typing).
    func updateTitle(of id: String, to title: String) {
        guard let row = pages.firstIndex(where: { $0.id == id }), pages[row].title != title else { return }
        pages[row].title = title
        table.reloadData(forRowIndexes: [row], columnIndexes: [0])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let id = NSUserInterfaceItemIdentifier("row")
        let rowView = tableView.makeView(withIdentifier: id, owner: nil) as? PageRowView ?? PageRowView()
        rowView.identifier = id
        rowView.isHovered = false
        return rowView
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? PageCell ?? PageCell()
        cell.identifier = id
        let page = pages[row]
        cell.label.stringValue = page.title
        cell.label.textColor = page.title == "Empty" ? Theme.secondaryText : Theme.text
        cell.toolTip = page.location == .pending ? "Not synced yet — saved on this Mac" : nil
        cell.deleteButton.setAccessibilityLabel("Delete “\(page.title)”")
        cell.onDelete = { [weak self] in self?.onDelete?(page.id) }
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback, table.selectedRow >= 0, table.selectedRow < pages.count else { return }
        onSelect?(pages[table.selectedRow].id)
    }
}

/// Draws the beige selection and hover highlight, and shows the cell's ✕.
private final class PageRowView: NSTableRowView {
    var isHovered = false { didSet { refresh() } }
    override var isSelected: Bool { didSet { refresh() } }
    // Keep label colours as they are on the light beige selection.
    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                       owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }

    private var highlightPath: NSBezierPath {
        NSBezierPath(roundedRect: bounds.insetBy(dx: 6, dy: 0), xRadius: 5, yRadius: 5)
    }

    override func drawSelection(in dirtyRect: NSRect) {
        Theme.selection.setFill()
        highlightPath.fill()
    }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, !isSelected else { return }
        Theme.hover.setFill()
        highlightPath.fill()
    }

    override func didAddSubview(_ subview: NSView) {
        super.didAddSubview(subview)
        refresh()
    }

    private func refresh() {
        for case let cell as PageCell in subviews { cell.deleteButton.isHidden = !(isHovered || isSelected) }
        needsDisplay = true
    }
}

private final class PageCell: NSTableCellView {
    let label = NSTextField(labelWithString: "")
    let deleteButton = NSButton()
    var onDelete: () -> Void = {}

    init() {
        super.init(frame: .zero)
        label.lineBreakMode = .byTruncatingTail
        textField = label
        let config = NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        deleteButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Delete page")?
            .withSymbolConfiguration(config)
        deleteButton.isBordered = false
        deleteButton.contentTintColor = Theme.secondaryText
        deleteButton.toolTip = "Delete page"
        deleteButton.target = self
        deleteButton.action = #selector(deleteClicked)
        deleteButton.isHidden = true
        for v in [label, deleteButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            label.trailingAnchor.constraint(equalTo: deleteButton.leadingAnchor, constant: -4),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            deleteButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            deleteButton.widthAnchor.constraint(equalToConstant: 16),
            deleteButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func deleteClicked() { onDelete() }
}
