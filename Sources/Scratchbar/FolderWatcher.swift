import Foundation
import ScratchbarCore

/// Watches the pages folder for changes made outside the editor (iCloud,
/// Finder, other editors). A directory event source fires on any add, remove
/// or rename (iCloud and atomic saves replace files), then a snapshot diff
/// says which pages changed. Events are coalesced and delivered on main.
final class FolderWatcher {
    let folder: URL
    private let onEvents: ([RemoteEvent]) -> Void
    private var source: DispatchSourceFileSystemObject?
    private var snapshot: FolderSnapshot
    private var pendingScan: DispatchWorkItem?

    init(folder: URL, onEvents: @escaping ([RemoteEvent]) -> Void) {
        self.folder = folder
        self.onEvents = onEvents
        snapshot = FolderSnapshot(folder: folder)
        start()
    }

    deinit { stop() }

    private func start() {
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else {
            NSLog("Scratchbar: can't watch \(folder.path)")
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
        source.setEventHandler { [weak self] in self?.scheduleScan() }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    func stop() {
        source?.cancel()
        source = nil
        pendingScan?.cancel()
    }

    /// Rescans soon (also used when the window opens, to catch in-place edits).
    func scheduleScan() {
        pendingScan?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.scan() }
        pendingScan = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    private func scan() {
        let new = FolderSnapshot(folder: folder)
        let events = new.changes(since: snapshot)
        snapshot = new
        if !events.isEmpty { onEvents(events) }
    }
}
