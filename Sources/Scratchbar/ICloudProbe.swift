import Foundation

/// Spike for Task 1: checks that this signed, unsandboxed app can use a plain
/// iCloud Drive folder the way sync will (coordinated write/read, a file
/// presenter, conflict-version lookup, removal).
enum ICloudProbe {
    final class Presenter: NSObject, NSFilePresenter {
        let presentedItemURL: URL?
        let presentedItemOperationQueue = OperationQueue()
        init(url: URL) { presentedItemURL = url }
    }

    static func run() -> Int32 {
        let root = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let folder = root.appendingPathComponent("Scratchbar", isDirectory: true)
        let file = folder.appendingPathComponent("probe-\(UUID().uuidString).txt")
        let payload = "Scratchbar iCloud probe \(Date())"
        var step = "locate iCloud Drive"

        func fail(_ error: Error?) -> Int32 {
            print("ICLOUD FAIL: \(step): \(error.map { "\($0)" } ?? "unexpected result")")
            return 1
        }

        guard FileManager.default.fileExists(atPath: root.path) else { return fail(nil) }

        do {
            step = "create folder"
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            step = "register file presenter"
            let presenter = Presenter(url: folder)
            NSFileCoordinator.addFilePresenter(presenter)
            defer { NSFileCoordinator.removeFilePresenter(presenter) }

            let coordinator = NSFileCoordinator(filePresenter: presenter)
            var coordError: NSError?
            var innerError: Error?

            step = "coordinated write"
            coordinator.coordinate(writingItemAt: file, options: .forReplacing, error: &coordError) { url in
                do { try Data(payload.utf8).write(to: url, options: .atomic) } catch { innerError = error }
            }
            if let e = coordError ?? innerError { return fail(e) }

            step = "coordinated read"
            var readBack = ""
            coordinator.coordinate(readingItemAt: file, options: [], error: &coordError) { url in
                do { readBack = try String(contentsOf: url, encoding: .utf8) } catch { innerError = error }
            }
            if let e = coordError ?? innerError { return fail(e) }
            guard readBack == payload else { return fail(nil) }

            step = "conflict version lookup"
            let conflicts = NSFileVersion.unresolvedConflictVersionsOfItem(at: file) ?? []
            guard conflicts.isEmpty else { return fail(nil) }

            step = "coordinated remove"
            coordinator.coordinate(writingItemAt: file, options: .forDeleting, error: &coordError) { url in
                do { try FileManager.default.removeItem(at: url) } catch { innerError = error }
            }
            if let e = coordError ?? innerError { return fail(e) }
        } catch {
            return fail(error)
        }

        print("ICLOUD OK: \(folder.path)")
        return 0
    }
}
