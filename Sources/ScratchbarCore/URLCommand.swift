import Foundation

/// Commands sent with the `scratchbar://` URL scheme (for PopClip, Keyboard
/// Maestro, `open`…). `scratchbar://new?text=<url-encoded>[&hide]`
public enum URLCommand: Equatable, Sendable {
    case newPage(text: String, hide: Bool)

    public static let maxTextBytes = 1_048_576

    public static func parse(_ url: URL) -> URLCommand? {
        guard url.scheme?.lowercased() == "scratchbar", url.host?.lowercased() == "new",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let text = items.first(where: { $0.name == "text" })?.value, !text.isEmpty,
              text.utf8.count <= maxTextBytes else { return nil }
        return .newPage(text: text, hide: items.contains { $0.name == "hide" })
    }
}
