import AppKit

/// Warm beige colours from Geraint's claude-like.css, with dark equivalents.
enum Theme {
    static let editorBackground = color(light: 0xfaf9f5, dark: 0x262421)
    static let sidebarBackground = color(light: 0xf5f2ec, dark: 0x1e1c19)
    static let text = color(light: 0x2b2621, dark: 0xe6e1d8)
    static let secondaryText = color(light: 0x72695e, dark: 0x9c9387)
    static let selection = color(light: 0xe8ddd0, dark: 0x4b4137)
    static let border = color(light: 0xddd5ca, dark: 0x3b3730)
    static let accent = color(light: 0xbc6a3a, dark: 0xd4885a)
    /// Search matches in the page: the accent colour, lightly.
    static let match = NSColor(name: nil) { appearance in
        NSColor(srgbRed: 188 / 255, green: 106 / 255, blue: 58 / 255, alpha: isDark(appearance) ? 0.45 : 0.28)
    }
    /// rgba(194, 113, 62, 0.08) in the stylesheet.
    static let hover = NSColor(name: nil) { appearance in
        NSColor(srgbRed: 194 / 255, green: 113 / 255, blue: 62 / 255, alpha: isDark(appearance) ? 0.16 : 0.08)
    }

    private static func color(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in rgb(isDark(appearance) ? dark : light) }
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255,
                green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: 1)
    }
}

/// Light, Dark, or follow the system.
enum ColorScheme: String, CaseIterable {
    case system, light, dark

    static var saved: ColorScheme {
        UserDefaults.standard.string(forKey: DefaultsKey.colorScheme).flatMap(ColorScheme.init) ?? .system
    }

    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// A plain view filled with a (dynamic) colour that follows light/dark changes.
final class ColorView: NSView {
    var color: NSColor { didSet { needsDisplay = true } }

    init(color: NSColor) {
        self.color = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = color.cgColor
    }
}
