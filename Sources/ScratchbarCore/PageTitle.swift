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

/// A file name for saving or sharing a page: its first non-blank line, up to
/// 80 characters, with "/" and ":" (which Finder can't use) replaced by "-"
/// and no leading dot (which would hide the file). Blank text → "Untitled".
public func exportFileName(for text: String) -> String {
    var name = ""
    text.enumerateLines { line, stop in
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        name = String(trimmed.prefix(80))
        stop = true
    }
    name = name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
    while name.hasPrefix(".") { name.removeFirst() }
    name = name.trimmingCharacters(in: .whitespaces)
    return (name.isEmpty ? "Untitled" : name) + ".txt"
}
