import Foundation

public enum BackupReason: Sendable {
    case beforeDelete, beforeConflict, beforeRestore, beforeSync, remoteDelete
}

public struct BackupVersion: Equatable, Sendable {
    public let url: URL
    public let date: Date
    public let text: String
}

/// Local, never-synced backups: `<folder>/<page-id>/<milliseconds>.txt`.
/// A `.deleted` file in a page's folder records when the page was deleted.
///
/// A backup is taken only just before a page's text is replaced or removed
/// (delete, emptying, restore, sync conflict, sync on/off). Each save keeps
/// the newest 5 per page and drops pages deleted over 30 days ago, so the
/// folder never grows however long Scratchbar runs.
public final class BackupStore {
    public static let keepPerPage = 5
    public static let keepDeletedFor: TimeInterval = 30 * 86_400

    public let folder: URL
    private let now: () -> Date
    private let fm = FileManager.default

    public init(folder: URL, now: @escaping () -> Date = Date.init) {
        self.folder = folder
        self.now = now
    }

    /// Backs up regardless of timing (but never duplicates the newest backup).
    public func backup(id: String, text: String, reason: BackupReason) {
        if let newest = versions(id: id, limit: 1).first, newest.text == text { return }
        let dir = pageFolder(id)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            var ms = Int64((now().timeIntervalSince1970 * 1000).rounded())
            var url = dir.appendingPathComponent("\(ms).txt")
            while fm.fileExists(atPath: url.path) {
                ms += 1
                url = dir.appendingPathComponent("\(ms).txt")
            }
            try Data(text.utf8).write(to: url, options: .atomic)
        } catch {
            NSLog("Scratchbar: backup of \(id) failed: \(error)")
        }
        prune()
    }

    public func markDeleted(id: String) {
        let dir = pageFolder(id)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try? Data(String(now().timeIntervalSince1970).utf8).write(to: deletedMarker(id), options: .atomic)
    }

    public func unmarkDeleted(id: String) {
        try? fm.removeItem(at: deletedMarker(id))
    }

    /// Backups for a page, newest first.
    public func versions(id: String) -> [BackupVersion] {
        versions(id: id, limit: nil)
    }

    /// Every page that has backups, with a title from its newest backup.
    public func pagesWithBackups() -> [(id: String, title: String, deleted: Bool, newest: Date)] {
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return dirs.compactMap { dir in
            let id = dir.lastPathComponent
            guard let newest = versions(id: id, limit: 1).first else { return nil }
            return (id, pageTitle(for: newest.text), deletedDate(id) != nil, newest.date)
        }
        .sorted { $0.newest > $1.newest }
    }

    /// Keeps the newest 5 backups per page and forgets pages deleted over 30 days ago.
    public func prune() {
        let dirs = (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        for dir in dirs {
            let id = dir.lastPathComponent
            if let deleted = deletedDate(id), now().timeIntervalSince(deleted) > Self.keepDeletedFor {
                try? fm.removeItem(at: dir)
                continue
            }
            for url in backupFiles(id: id).dropFirst(Self.keepPerPage) {
                try? fm.removeItem(at: url)
            }
        }
    }

    // MARK: - Helpers

    private func pageFolder(_ id: String) -> URL { folder.appendingPathComponent(id, isDirectory: true) }
    private func deletedMarker(_ id: String) -> URL { pageFolder(id).appendingPathComponent(".deleted") }

    private func deletedDate(_ id: String) -> Date? {
        guard let data = try? Data(contentsOf: deletedMarker(id)),
              let seconds = TimeInterval(String(decoding: data, as: UTF8.self)) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    /// Backup files, newest first (file names are millisecond timestamps).
    private func backupFiles(id: String) -> [URL] {
        let urls = (try? fm.contentsOfDirectory(at: pageFolder(id), includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
        return urls
            .filter { $0.pathExtension == "txt" && Int64($0.deletingPathExtension().lastPathComponent) != nil }
            .sorted { Int64($0.deletingPathExtension().lastPathComponent)! > Int64($1.deletingPathExtension().lastPathComponent)! }
    }

    private func date(of url: URL) -> Date {
        Date(timeIntervalSince1970: TimeInterval(Int64(url.deletingPathExtension().lastPathComponent) ?? 0) / 1000)
    }

    private func versions(id: String, limit: Int?) -> [BackupVersion] {
        var files = backupFiles(id: id)
        if let limit { files = Array(files.prefix(limit)) }
        return files.compactMap { url in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return BackupVersion(url: url, date: date(of: url), text: decodeText(data))
        }
    }
}
