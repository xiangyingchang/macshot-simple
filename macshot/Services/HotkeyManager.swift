// Derived from MacShot v4.3.0 (sw33tLie), GPL-3.0.
// Modified 2026-10-07: one screenshot hotkey, report registration errors.
import Cocoa
import Carbon

final class HotkeyManager {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var onCapture: (() -> Void)?

    @discardableResult
    func register(key: UInt32, modifiers: UInt32) -> OSStatus {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, _, data in
            guard let data else { return OSStatus(eventNotHandledErr) }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(data).takeUnretainedValue()
            MainActor.assumeIsolated { manager.onCapture?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else { return status }
        let id = EventHotKeyID(signature: OSType(0x4D534854), id: 1)
        let registration = RegisterEventHotKey(key, modifiers, id, GetApplicationEventTarget(), 0, &reference)
        if registration != noErr { unregister() }
        return registration
    }

    func unregister() {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
        reference = nil; handler = nil
    }
}
