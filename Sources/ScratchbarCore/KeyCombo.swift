import Foundation

/// A global keyboard shortcut: a virtual key code plus Carbon modifier flags.
public struct KeyCombo: Codable, Equatable, Sendable {
    // Carbon modifier flags (Events.h), repeated here so the core needs no Carbon.
    public static let cmdKey: UInt32 = 1 << 8
    public static let shiftKey: UInt32 = 1 << 9
    public static let optionKey: UInt32 = 1 << 11
    public static let controlKey: UInt32 = 1 << 12

    /// ⌃⌥⌘N (kVK_ANSI_N = 45).
    public static let defaultCombo = KeyCombo(keyCode: 45, modifiers: controlKey | optionKey | cmdKey, key: "N")

    public var keyCode: UInt32
    public var modifiers: UInt32
    /// What to show for the key itself, e.g. "N" or "Space".
    public var key: String

    public init(keyCode: UInt32, modifiers: UInt32, key: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.key = key
    }

    /// Modifiers in the standard Mac order (⌃⌥⇧⌘) followed by the key.
    public var displayString: String {
        var s = ""
        if modifiers & Self.controlKey != 0 { s += "⌃" }
        if modifiers & Self.optionKey != 0 { s += "⌥" }
        if modifiers & Self.shiftKey != 0 { s += "⇧" }
        if modifiers & Self.cmdKey != 0 { s += "⌘" }
        return s + key
    }

    /// A global shortcut must include ⌘, ⌥ or ⌃ so it can't swallow ordinary typing.
    public var isAcceptable: Bool {
        modifiers & (Self.cmdKey | Self.optionKey | Self.controlKey) != 0
    }
}

/// Persists whether the hotkey is enabled and which combination it uses.
public enum HotKeySettings {
    static let enabledKey = "hotKeyEnabled"
    static let comboKey = "hotKeyCombo"

    /// First launch: enabled with ⌃⌥⌘N. A cleared shortcut loads as `nil`.
    public static func load(_ defaults: UserDefaults) -> (enabled: Bool, combo: KeyCombo?) {
        let enabled = defaults.object(forKey: enabledKey) as? Bool ?? true
        guard let data = defaults.data(forKey: comboKey) else { return (enabled, .defaultCombo) }
        if data.isEmpty { return (enabled, nil) }
        return (enabled, (try? JSONDecoder().decode(KeyCombo.self, from: data)) ?? .defaultCombo)
    }

    public static func save(enabled: Bool, combo: KeyCombo?, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: enabledKey)
        let data = combo.flatMap { try? JSONEncoder().encode($0) } ?? Data()
        defaults.set(data, forKey: comboKey)
    }
}
