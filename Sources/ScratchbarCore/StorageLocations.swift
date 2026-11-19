import Foundation

/// Where Scratchbar keeps things on disk.
public struct StorageLocations: Sendable {
    /// Pages when sync is off.
    public let local: URL
    /// Fallback for pages that couldn't be written to iCloud Drive.
    public let pending: URL
    public let backups: URL
    /// The iCloud Drive root (`com~apple~CloudDocs`), if iCloud Drive exists.
    public let iCloudRoot: URL?
    /// Pages when sync is on: `iCloud Drive/Scratchbar`.
    public var iCloud: URL? { iCloudRoot?.appendingPathComponent("Scratchbar", isDirectory: true) }

    public init(appSupport: URL, iCloudRoot: URL?) {
        local = appSupport.appendingPathComponent("Pages", isDirectory: true)
        pending = appSupport.appendingPathComponent("Pending", isDirectory: true)
        backups = appSupport.appendingPathComponent("Backups", isDirectory: true)
        self.iCloudRoot = iCloudRoot
    }

    /// `~/Library/Mobile Documents/com~apple~CloudDocs`, whether or not it exists right now.
    public static var defaultICloudRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    /// True when the iCloud Drive root exists (signed in, iCloud Drive on).
    public var iCloudAvailable: Bool {
        guard let iCloudRoot else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: iCloudRoot.path, isDirectory: &isDir) && isDir.boolValue
    }
}

/// The pages the app sees: the active folder (local, or iCloud Drive when sync
/// is on) plus the local Pending fallback. An iCloud problem never stops a save:
/// the page is written to Pending and moved into iCloud later.
public final class PageRepository: PageStoring {
    public let locations: StorageLocations
    public let syncEnabled: Bool
    private let macName: String
    private let primary: PageStore
    private let pending: PageStore

    /// Called with (id, text) before flushPending overwrites a different version.
    public var backup: ((String, String) -> Void)?

    /// True while some pages are saved only on this Mac because iCloud failed.
    public private(set) var isDegraded = false

    public init(locations: StorageLocations, syncEnabled: Bool, macName: String = SyncMigrator.currentMacName) {
        self.locations = locations
        self.syncEnabled = syncEnabled
        self.macName = macName
        let folder = syncEnabled ? (locations.iCloud ?? locations.pending) : locations.local
        primary = PageStore(folder: folder)
        pending = PageStore(folder: locations.pending, location: .pending)
        isDegraded = syncEnabled && (!pendingIDs().isEmpty || !locations.iCloudAvailable)
    }

    /// The active pages folder (for watching).
    public var primaryFolder: URL { primary.folder }

    private var canWritePrimary: Bool { !syncEnabled || locations.iCloudAvailable }

    private func pendingIDs() -> Set<String> {
        Set(((try? pending.list()) ?? []).map(\.id))
    }

    public func list() throws -> [Page] {
        let waiting = (try? pending.list()) ?? []
        let waitingIDs = Set(waiting.map(\.id))
        let main = canWritePrimary ? try primary.list() : []
        return (main.filter { !waitingIDs.contains($0.id) } + waiting).sorted { $0.modified > $1.modified }
    }

    public func read(_ id: String) throws -> String {
        if pendingIDs().contains(id) { return try pending.read(id) }
        return try primary.read(id)
    }

    public func write(_ id: String, text: String) throws {
        guard syncEnabled else {
            try primary.write(id, text: text)
            // A copy left in Pending from when sync was on is now stale.
            if pendingIDs().contains(id) { try? pending.remove(id) }
            return
        }
        if locations.iCloudAvailable {
            do {
                try primary.write(id, text: text)
                if pendingIDs().contains(id) { try? pending.remove(id) }
                isDegraded = !pendingIDs().isEmpty
                return
            } catch {
                NSLog("Scratchbar: iCloud write failed for \(id), saving locally: \(error)")
            }
        }
        try pending.write(id, text: text)
        isDegraded = true
    }

    public func delete(_ id: String) throws {
        if pendingIDs().contains(id) { try pending.delete(id) }
        if canWritePrimary, FileManager.default.fileExists(atPath: primary.url(for: id).path) { try primary.delete(id) }
    }

    public func remove(_ id: String) throws {
        if pendingIDs().contains(id) { try pending.remove(id) }
        if canWritePrimary, FileManager.default.fileExists(atPath: primary.url(for: id).path) { try primary.remove(id) }
    }

    /// Moves pages from Pending into iCloud Drive when it is writable again.
    /// Returns how many were moved.
    @discardableResult
    public func flushPending() -> Int {
        guard canWritePrimary else { return 0 }
        var moved = 0
        for id in pendingIDs() {
            guard let text = try? pending.read(id) else { continue }
            do {
                // Never silently replace a different version already there:
                // keep both if it's newer or unreadable, otherwise back it up.
                var target = id
                let existingURL = primary.url(for: id)
                if FileManager.default.fileExists(atPath: existingURL.path) {
                    if let existing = try? primary.read(id) {
                        if existing != text {
                            if let theirs = modificationDate(existingURL), let ours = modificationDate(pending.url(for: id)),
                               theirs > ours {
                                target = SyncMigrator.uniqueID("\(id) (from \(macName))", in: primary)
                            } else {
                                backup?(id, existing)
                            }
                        }
                    } else {
                        target = SyncMigrator.uniqueID("\(id) (from \(macName))", in: primary)
                    }
                }
                try primary.write(target, text: text)
                try pending.remove(id)
                moved += 1
            } catch {
                NSLog("Scratchbar: couldn't move pending page \(id) to iCloud: \(error)")
            }
        }
        isDegraded = !pendingIDs().isEmpty
        return moved
    }

    private func modificationDate(_ url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
