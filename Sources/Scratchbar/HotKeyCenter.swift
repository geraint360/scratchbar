import Carbon
import ScratchbarCore

/// Registers one system-wide hotkey with Carbon's RegisterEventHotKey, which
/// needs no Accessibility permission.
final class HotKeyCenter {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private var handler: (() -> Void)?

    /// Registers `combo`, replacing any previous one. Returns false if macOS
    /// refuses it (e.g. another app already registered the same combination).
    @discardableResult
    func register(_ combo: KeyCombo, handler: @escaping () -> Void) -> Bool {
        unregister()
        installEventHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x5343_5242), id: 1)  // 'SCRB'
        let status = RegisterEventHotKey(combo.keyCode, combo.modifiers, id, GetEventDispatcherTarget(), 0, &hotKeyRef)
        guard status == noErr else {
            hotKeyRef = nil
            return false
        }
        self.handler = handler
        return true
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        handler = nil
    }

    private func installEventHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData in
            guard let userData else { return noErr }
            let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { center.handler?() }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }
}
