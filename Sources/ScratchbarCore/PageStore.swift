import Foundation

public enum PageStoreError: Error {
    case coordination(Error)
}

/// A folder of plain-text pages: one `<id>.txt` file per page.
/// Reads and writes go through `NSFileCoordinator`; writes are atomic.
public final class PageStore {
    public let folder: URL
    public let location: PageLocation
    private let trash: (URL) throws -> Void

    /// Bytes read from each file to build its sidebar title.
    static let titlePrefixBytes = 8 * 1024

    public init(folder: URL,
                location: PageLocation = .primary,
                trash: @escaping (URL) throws -> Void = PageStore.moveToTrash) {
        self.folder = folder
        self.location = location
        self.trash = trash
    }

    public static func moveToTrash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }

    public static func newID() -> String { UUID().uuidString }

    public func url(for id: String) -> URL {
        folder.appendingPathComponent(id).appendingPathExtension(PageKind.text.rawValue)
    }

    /// All pages in the folder, newest modification first. A missing folder is empty.
    public func list() throws -> [Page] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return [] }
        let urls = try fm.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])
        let pages: [Page] = urls.compactMap { url in
            guard url.pathExtension == PageKind.text.rawValue else { return nil }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast
            return Page(id: url.deletingPathExtension().lastPathComponent,
                        modified: modified,
                        title: pageTitle(for: readTitlePrefix(url)),
                        location: location)
        }
        return pages.sorted { $0.modified > $1.modified }
    }

    public func read(_ id: String) throws -> String {
        var result: Result<Data, Error> = .success(Data())
        try coordinate(reading: url(for: id)) { url in
            result = Result { try Data(contentsOf: url) }
        }
        return decodeText(try result.get())
    }

    /// Writes the page atomically, creating the folder if needed.
    public func write(_ id: String, text: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var result: Result<Void, Error> = .success(())
        try coordinate(writing: url(for: id), options: .forReplacing) { url in
            result = Result { try Data(text.utf8).write(to: url, options: .atomic) }
        }
        try result.get()
    }

    /// Deletes a page by handing it to `trash` (the macOS Trash by default).
    public func delete(_ id: String) throws {
        var result: Result<Void, Error> = .success(())
        try coordinate(writing: url(for: id), options: .forDeleting) { url in
            result = Result { try self.trash(url) }
        }
        try result.get()
    }

    /// Removes a page's file outright (used for discarding empty pages).
    public func remove(_ id: String) throws {
        var result: Result<Void, Error> = .success(())
        try coordinate(writing: url(for: id), options: .forDeleting) { url in
            result = Result { try FileManager.default.removeItem(at: url) }
        }
        try result.get()
    }

    // MARK: - Helpers

    private func readTitlePrefix(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: Self.titlePrefixBytes)) ?? Data()
        return decodePrefix(data, truncated: data.count == Self.titlePrefixBytes)
    }

    private func coordinate(reading url: URL, _ body: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error, byAccessor: body)
        if let error { throw PageStoreError.coordination(error) }
    }

    private func coordinate(writing url: URL, options: NSFileCoordinator.WritingOptions, _ body: (URL) -> Void) throws {
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: options, error: &error, byAccessor: body)
        if let error { throw PageStoreError.coordination(error) }
    }
}
