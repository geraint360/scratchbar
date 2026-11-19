import Foundation

/// Something that happened to a page file outside this app's editor.
public enum RemoteEvent: Equatable, Hashable, Sendable {
    case modified(id: String)
    case deleted(id: String)
    case conflict(id: String)

    public var id: String {
        switch self {
        case .modified(let id), .deleted(let id), .conflict(let id): return id
        }
    }
}

public enum RemoteAction: Equatable, Sendable {
    case reloadList, reloadOpenPage, showEditedBanner, showDeletedBanner, none
}

/// What the UI should do about a remote event. The open page reloads silently
/// unless you have edits it hasn't caught up with; then you choose.
public func decide(_ event: RemoteEvent, openPageID: String?, editorDirty: Bool) -> [RemoteAction] {
    guard event.id == openPageID else { return [.reloadList] }
    switch event {
    case .modified: return [.reloadList, editorDirty ? .showEditedBanner : .reloadOpenPage]
    case .deleted: return [.reloadList, .showDeletedBanner]
    case .conflict: return [.reloadList, .showEditedBanner]
    }
}

public enum ConflictChoice: Sendable {
    case keepThisMac, keepOther, keepBoth
}

public func resolveConflict(current: String, other: String, choice: ConflictChoice) -> String {
    switch choice {
    case .keepThisMac: return current
    case .keepOther: return other
    case .keepBoth: return current + "\n\n——— from another Mac ———\n\n" + other
    }
}

/// The page id for an iCloud placeholder name (".abc.txt.icloud" → "abc").
func placeholderID(fileName name: String) -> String? {
    let suffix = "." + PageKind.text.rawValue + ".icloud"
    guard name.hasPrefix("."), name.hasSuffix(suffix), name.count > suffix.count + 1 else { return nil }
    return String(name.dropFirst().dropLast(suffix.count))
}

/// Modification dates and sizes of the pages in a folder, compared over time
/// to spot changes made by iCloud, Finder or another editor.
public struct FolderSnapshot: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let modified: Date
        public let size: Int
        public init(modified: Date, size: Int) {
            self.modified = modified
            self.size = size
        }
    }

    public let entries: [String: Entry]

    public init(entries: [String: Entry]) {
        self.entries = entries
    }

    /// Reads `<id>.txt` files and `.<id>.txt.icloud` placeholders.
    public init(folder: URL) {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        var entries: [String: Entry] = [:]
        for url in urls {
            let name = url.lastPathComponent
            let id: String
            if let placeholder = placeholderID(fileName: name) {
                id = placeholder
            } else if !name.hasPrefix("."), url.pathExtension == PageKind.text.rawValue {
                id = url.deletingPathExtension().lastPathComponent
            } else {
                continue
            }
            let values = try? url.resourceValues(forKeys: Set(keys))
            entries[id] = Entry(modified: values?.contentModificationDate ?? .distantPast, size: values?.fileSize ?? 0)
        }
        self.entries = entries
    }

    /// Pages added or changed (`.modified`) and removed (`.deleted`) since `old`.
    public func changes(since old: FolderSnapshot) -> [RemoteEvent] {
        var events: [RemoteEvent] = []
        for (id, entry) in entries where old.entries[id] != entry {
            events.append(.modified(id: id))
        }
        for id in old.entries.keys where entries[id] == nil {
            events.append(.deleted(id: id))
        }
        return events
    }
}

/// True when writing `newText` would silently replace a change someone else
/// made to the file since we last read or wrote it.
public func saveWouldOverwriteRemoteChange(diskText: String?, lastSavedText: String, newText: String) -> Bool {
    guard let diskText else { return false }
    return diskText != lastSavedText && diskText != newText
}
