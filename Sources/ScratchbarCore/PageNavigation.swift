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

/// "today at 11:23", "yesterday at 09:05" or "2 Nov 2026 at 16:40", for the
/// status line ("Edited today at 11:23"). Lowercase, so it reads mid-sentence.
public func editedDescription(_ date: Date, now: Date = Date(),
                              calendar: Calendar = .current, locale: Locale = .current) -> String {
    let time = DateFormatter()
    time.locale = locale
    time.timeZone = calendar.timeZone
    time.dateStyle = .none
    time.timeStyle = .short
    let day: String
    if calendar.isDate(date, inSameDayAs: now) {
        day = "today"
    } else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
              calendar.isDate(date, inSameDayAs: yesterday) {
        day = "yesterday"
    } else {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = calendar.timeZone
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .none
        day = dateFormatter.string(from: date)
    }
    return "\(day) at \(time.string(from: date))"
}

/// Every place `query` occurs in `text`, ignoring case and accents, as
/// UTF-16 ranges for highlighting. Stops after `limit` matches.
public func matchRanges(of query: String, in text: String, limit: Int = 1000) -> [NSRange] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !needle.isEmpty else { return [] }
    let ns = text as NSString
    var ranges: [NSRange] = []
    var searchRange = NSRange(location: 0, length: ns.length)
    while ranges.count < limit {
        let found = ns.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
        guard found.location != NSNotFound, found.length > 0 else { break }
        ranges.append(found)
        let next = NSMaxRange(found)
        searchRange = NSRange(location: next, length: ns.length - next)
    }
    return ranges
}
