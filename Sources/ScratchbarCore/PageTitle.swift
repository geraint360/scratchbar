import Foundation

/// The sidebar title for a page: its first non-blank line, trimmed, and
/// truncated to `maxLength` characters (ending in "…"). Blank text → "Empty".
public func pageTitle(for text: String, maxLength: Int = 40) -> String {
    for line in text.split(whereSeparator: \.isNewline) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { continue }
        if trimmed.count <= maxLength { return trimmed }
        return String(trimmed.prefix(maxLength - 1)) + "…"
    }
    return "Empty"
}
