import AppKit
import ScratchbarCore

/// The sidebar list of page titles.
final class PageListView: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    private let table = NSTableView()
    private(set) var pages: [Page] = []
    private var suppressSelectionCallback = false

    /// Called when the user picks a different page.
    var onSelect: ((String) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        let column = NSTableColumn(identifier: .init("title"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .sourceList
        table.rowSizeStyle = .default
        table.backgroundColor = .clear
        table.focusRingType = .none
        table.allowsEmptySelection = true
        table.dataSource = self
        table.delegate = self
        documentView = table
        hasVerticalScroller = true
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

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let cell = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView ?? {
            let cell = NSTableCellView()
            cell.identifier = id
            let label = NSTextField(labelWithString: "")
            label.lineBreakMode = .byTruncatingTail
            label.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            ])
            return cell
        }()
        let page = pages[row]
        cell.textField?.stringValue = page.title
        cell.textField?.textColor = page.title == "Empty" ? .secondaryLabelColor : .labelColor
        cell.toolTip = page.location == .pending ? "Not synced yet — saved on this Mac" : nil
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressSelectionCallback, table.selectedRow >= 0, table.selectedRow < pages.count else { return }
        onSelect?(pages[table.selectedRow].id)
    }
}
