import AppKit
import ScratchbarCore

/// "Global Shortcut…" sheet, modelled on Reminders MenuBar's setting:
/// an enable checkbox, a recorder field with a clear button, and Restore default.
final class ShortcutSheet: NSWindowController {
    private let checkbox = NSButton(checkboxWithTitle: "Enable keyboard shortcut to open a new Scratchbar page",
                                    target: nil, action: nil)
    private let recorder = ShortcutRecorderField()
    private let restoreButton = NSButton(title: "Restore default", target: nil, action: nil)
    private let errorLabel = NSTextField(labelWithString: "")
    private let doneButton = NSButton(title: "Done", target: nil, action: nil)

    /// Applies settings; returns false if the shortcut couldn't be registered.
    private let apply: (Bool, KeyCombo?) -> Bool
    private let pause: (Bool) -> Void

    init(enabled: Bool, combo: KeyCombo?, apply: @escaping (Bool, KeyCombo?) -> Bool, pause: @escaping (Bool) -> Void) {
        self.apply = apply
        self.pause = pause
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 170),
                              styleMask: [.titled], backing: .buffered, defer: true)
        super.init(window: window)

        checkbox.state = enabled ? .on : .off
        checkbox.target = self
        checkbox.action = #selector(changed)
        recorder.combo = combo
        recorder.onChange = { [weak self] _ in self?.changed() }
        recorder.onRecordingChange = { [weak self] recording in self?.pause(recording) }
        restoreButton.target = self
        restoreButton.action = #selector(restoreDefault)
        restoreButton.bezelStyle = .rounded
        errorLabel.textColor = .systemRed
        errorLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        doneButton.target = self
        doneButton.action = #selector(done)
        doneButton.keyEquivalent = "\r"
        doneButton.bezelStyle = .rounded

        let row = NSStackView(views: [recorder, restoreButton])
        row.spacing = 12
        let stack = NSStackView(views: [checkbox, row, errorLabel, doneButton])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.setCustomSpacing(6, after: row)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        window.contentView = stack
        NSLayoutConstraint.activate([
            doneButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -20),
        ])
        refreshEnabled()
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func begin(on parent: NSWindow) {
        guard let window else { return }
        parent.beginSheet(window)
    }

    private func refreshEnabled() {
        let on = checkbox.state == .on
        recorder.alphaValue = on ? 1 : 0.4
        restoreButton.isEnabled = on
    }

    @objc private func changed() {
        refreshEnabled()
        let ok = apply(checkbox.state == .on, recorder.combo)
        errorLabel.stringValue = ok ? "" : "That shortcut is in use by another app."
    }

    @objc private func restoreDefault() {
        recorder.combo = .defaultCombo
        changed()
    }

    @objc private func done() {
        pause(false)
        guard let window, let parent = window.sheetParent else { return }
        parent.endSheet(window)
    }
}
