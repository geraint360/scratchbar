import Foundation

/// Coalesces rapid edits into one save per page after `delay`, and can flush
/// everything immediately (page switch, window hide, quit, sleep).
/// Must be used from the main queue.
public final class SaveScheduler {
    private let delay: TimeInterval
    private let save: (String, String) -> Void
    private var pending: [String: String] = [:]
    private var timer: DispatchWorkItem?

    /// Pages that already have a file. Empty text for any other page is never
    /// saved, so a blank new page never creates a file.
    public var knownOnDisk: Set<String> = []

    public var hasPendingChanges: Bool { !pending.isEmpty }

    public init(delay: TimeInterval = 0.3, save: @escaping (String, String) -> Void) {
        self.delay = delay
        self.save = save
    }

    public func textChanged(id: String, text: String) {
        pending[id] = text
        timer?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        timer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Forgets a pending edit (e.g. the page was discarded).
    public func cancel(id: String) {
        pending[id] = nil
    }

    public func flush() {
        timer?.cancel()
        timer = nil
        let toSave = pending
        pending.removeAll()
        for (id, text) in toSave {
            if text.isEmpty && !knownOnDisk.contains(id) { continue }
            save(id, text)
            knownOnDisk.insert(id)
        }
    }
}
