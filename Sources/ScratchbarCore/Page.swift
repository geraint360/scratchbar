import Foundation

/// The kind of snippet a page holds. The raw value is the file extension.
public enum PageKind: String, Sendable {
    case text = "txt"
}

/// Where a page's file currently lives.
public enum PageLocation: Sendable, Equatable {
    /// The active pages folder (local, or iCloud Drive when sync is on).
    case primary
    /// The local fallback folder used when iCloud can't be written.
    case pending
}

/// A single scratch page, as listed in the sidebar.
public struct Page: Equatable, Sendable {
    /// File name without extension.
    public let id: String
    public var kind: PageKind
    public var modified: Date
    public var title: String
    public var location: PageLocation
    /// An iCloud placeholder whose contents haven't downloaded yet.
    public var isDownloading: Bool

    public init(id: String, kind: PageKind = .text, modified: Date, title: String,
                location: PageLocation = .primary, isDownloading: Bool = false) {
        self.id = id
        self.kind = kind
        self.modified = modified
        self.title = title
        self.location = location
        self.isDownloading = isDownloading
    }
}
