import Foundation

public enum SyncError: Error, LocalizedError {
    case iCloudUnavailable
    public var errorDescription: String? { "iCloud Drive isn't available. Check that you're signed in to iCloud and iCloud Drive is on." }
}

/// Moves pages between the local folder and iCloud Drive when sync is turned
/// on or off. Nothing is ever dropped: identical text is de-duplicated, a name
/// clash with different text keeps both, and anything overwritten is backed up.
public enum SyncMigrator {
    public static var currentMacName: String { Host.current().localizedName ?? "this Mac" }

    /// Turning sync on: back up every local page, copy them all into iCloud
    /// Drive, and only then remove the local copies (a failure part-way leaves
    /// every local page in place).
    public static func enable(locations: StorageLocations, backups: BackupStore, macName: String = currentMacName,
                              cloudStore: PageStoring? = nil) throws {
        guard locations.iCloudAvailable, let cloudFolder = locations.iCloud else { throw SyncError.iCloudUnavailable }
        let local = PageStore(folder: locations.local)
        // The iCloud root exists (checked above), so this only creates "Scratchbar".
        try FileManager.default.createDirectory(at: cloudFolder, withIntermediateDirectories: true)
        let cloud = cloudStore ?? PageStore(folder: cloudFolder)
        let pages = try local.list()
        for page in pages {
            let text = try local.read(page.id)
            backups.backup(id: page.id, text: text, reason: .beforeSync)
            try merge(text: text, id: page.id, into: cloud, suffix: "from \(macName)")
        }
        for page in pages {
            try local.remove(page.id)
        }
    }

    /// Turning sync off: copy iCloud pages back to this Mac, leaving iCloud untouched.
    public static func disable(locations: StorageLocations, backups: BackupStore) throws {
        guard let cloudFolder = locations.iCloud, locations.iCloudAvailable else { return }
        let local = PageStore(folder: locations.local)
        let cloud = PageStore(folder: cloudFolder)
        for page in try cloud.list() {
            let text = try cloud.read(page.id)
            if let existing = try? local.read(page.id), existing != text {
                // A stale copy left from before sync was on: iCloud is newer.
                backups.backup(id: page.id, text: existing, reason: .beforeSync)
            }
            try local.write(page.id, text: text)
        }
    }

    /// Adds `text` to `store` as `id`: skips it if any page already has the same
    /// text; writes it under a new name if `id` exists with different text.
    static func merge(text: String, id: String, into store: PageStoring, suffix: String) throws {
        let existing = try store.list()
        for page in existing where (try? store.read(page.id)) == text { return }
        let target = existing.contains { $0.id == id } ? uniqueID("\(id) (\(suffix))", in: store) : id
        try store.write(target, text: text)
    }

    /// `base`, or `base 2`, `base 3`… whichever doesn't exist yet in `store`.
    static func uniqueID(_ base: String, in store: PageStoring) -> String {
        let taken = Set(((try? store.list()) ?? []).map(\.id))
        var candidate = base
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(n)"
            n += 1
        }
        return candidate
    }
}
