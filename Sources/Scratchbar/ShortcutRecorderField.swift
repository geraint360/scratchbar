import AppKit
import Carbon
import ScratchbarCore

/// A click-to-record shortcut field: click it, press a combination.
/// Esc cancels recording. The ⓧ button clears the shortcut.
final class ShortcutRecorderField: NSView {
    var combo: KeyCombo? { didSet { refresh() } }
    var onChange: (KeyCombo?) -> Void = { _ in }
    /// Called when recording starts/stops, so the live hotkey can be paused.
    var onRecordingChange: (Bool) -> Void = { _ in }

    private let label = NSTextField(labelWithString: "")
    private let clearButton = NSButton()
    private var isRecording = false { didSet { refresh(); onRecordingChange(isRecording) } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 12
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: 15)
        clearButton.image = NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: "Clear shortcut")
        clearButton.isBordered = false
        clearButton.contentTintColor = .secondaryLabelColor
        clearButton.target = self
        clearButton.action = #selector(clear)
        for v in [label, clearButton] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 32),
            widthAnchor.constraint(equalToConstant: 200),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -4),
            clearButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Shortcut")
        refresh()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    // VoiceOver / accessibility "press" starts recording too.
    override func accessibilityPerformPress() -> Bool {
        window?.makeFirstResponder(self)
        isRecording = true
        return true
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { isRecording = false }
        return true
    }

    override func updateLayer() {
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
    }

    private func refresh() {
        label.stringValue = isRecording ? "Type shortcut…" : (combo?.displayString ?? "Record Shortcut")
        label.textColor = (isRecording || combo == nil) ? .secondaryLabelColor : .labelColor
        clearButton.isHidden = combo == nil || isRecording
        setAccessibilityValue(label.stringValue)
        needsDisplay = true
        needsLayout = true
        updateLayer()
    }

    @objc private func clear() {
        combo = nil
        onChange(nil)
    }

    // ⌘-combinations arrive as key equivalents rather than keyDown.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
        record(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else { return super.keyDown(with: event) }
        record(event)
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) && event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
            isRecording = false
            return
        }
        let candidate = KeyCombo(keyCode: UInt32(event.keyCode),
                                 modifiers: Self.carbonFlags(event.modifierFlags),
                                 key: Self.keyName(event))
        guard candidate.isAcceptable else { NSSound.beep(); return }
        isRecording = false
        combo = candidate
        onChange(candidate)
    }

    static func carbonFlags(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= KeyCombo.cmdKey }
        if flags.contains(.option) { result |= KeyCombo.optionKey }
        if flags.contains(.control) { result |= KeyCombo.controlKey }
        if flags.contains(.shift) { result |= KeyCombo.shiftKey }
        return result
    }

    private static let specialKeys: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_DownArrow: "↓", kVK_UpArrow: "↑",
        kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
    ]

    static func keyName(_ event: NSEvent) -> String {
        if let special = specialKeys[Int(event.keyCode)] { return special }
        return (event.charactersIgnoringModifiers ?? "?").uppercased()
    }
}
