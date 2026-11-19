import Foundation

/// The sidebar title for a page: its first non-blank line, trimmed, and
/// truncated to `maxLength` characters (ending in "…"). Blank text → "Empty".
/// Stops at the first non-blank line, so it stays cheap on very large pages.
public func pageTitle(for text: String, maxLength: Int = 40) -> String {
    var title = "Empty"
    text.enumerateLines { line, stop in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        title = trimmed.count <= maxLength ? trimmed : String(trimmed.prefix(maxLength - 1)) + "…"
        stop = true
    }
    return title
}
