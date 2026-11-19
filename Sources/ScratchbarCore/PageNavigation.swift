import Foundation

/// IDs of the pages whose text (or title, if the text can't be read) contains
/// `query`, ignoring case and accents. A blank query returns nil: no filter.
public func matchingPageIDs(query: String, in pages: [Page], text: (String) -> String?) -> Set<String>? {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return nil }
    let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
    var ids = Set<String>()
    for page in pages {
        let haystack = text(page.id) ?? page.title
        if haystack.range(of: needle, options: options) != nil { ids.insert(page.id) }
    }
    return ids
}

/// The page `offset` steps from `current` in `ids` (⌘] is +1, ⌘[ is −1).
/// Stops at the ends (nil). With no current page, starts at the near end.
public func adjacentPageID(in ids: [String], from current: String?, offset: Int) -> String? {
    guard !ids.isEmpty else { return nil }
    guard let current, let index = ids.firstIndex(of: current) else {
        return offset > 0 ? ids.first : ids.last
    }
    let next = index + offset
    return ids.indices.contains(next) ? ids[next] : nil
}
