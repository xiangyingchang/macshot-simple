// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa
import Carbon

enum SimpleSettings {
    static let widths: [CGFloat] = [2, 4, 8]
    static let palette = [0x10AEFF, 0x91D300, 0xFFC300, 0x4F4F4F, 0xFFFFFF, 0xFF4D4F].map { DesignTheme.color(UInt32($0)) }
    static let green = DesignTheme.green
    static func strokeWidth(for tool: AnnotationTool) -> CGFloat {
        let stored = UserDefaults.standard.double(forKey: "simpleStrokeWidth_\(tool.rawValue)")
        let legacy = UserDefaults.standard.double(forKey: "currentStrokeWidth")
        let value = CGFloat(stored > 0 ? stored : legacy > 0 ? legacy : 4)
        return widths.min(by: { abs($0 - value) < abs($1 - value) }) ?? 4
    }
    static func saveWidth(_ value: CGFloat, for tool: AnnotationTool) {
        guard widths.contains(value) else { return }
        UserDefaults.standard.set(Double(value), forKey: "simpleStrokeWidth_\(tool.rawValue)")
    }
    static var colorIndex: Int {
        get { min(palette.count - 1, max(0, UserDefaults.standard.object(forKey: "simpleColorIndex") as? Int ?? 5)) }
        set { UserDefaults.standard.set(min(palette.count - 1, max(0, newValue)), forKey: "simpleColorIndex") }
    }
    static var fontSize: CGFloat {
        get {
            let value = UserDefaults.standard.double(forKey: "simpleFontSize")
            return value.isFinite && value > 0 ? min(72, max(12, CGFloat(value))) : 18
        }
        set { UserDefaults.standard.set(Double(min(72, max(12, newValue))), forKey: "simpleFontSize") }
    }
    static var hotkey: (key: UInt32, modifiers: UInt32) {
        let defaults = UserDefaults.standard
        let key = defaults.object(forKey: "hotkeyKeyCode") as? Int ?? Int(kVK_ANSI_X)
        let mods = defaults.object(forKey: "hotkeyModifiers") as? Int ?? (cmdKey | shiftKey)
        return (UInt32(clamping: key), UInt32(clamping: mods))
    }
    static var hotkeyDescription: String {
        let key = hotkey
        var result = ""
        if key.modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if key.modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if key.modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if key.modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result + (KeyboardShortcutMatcher.currentLayoutCharacter(for: key.key)?.uppercased() ?? "Key \(key.key)")
    }
    static func saveHotkey(key: UInt32, modifiers: UInt32) {
        UserDefaults.standard.set(Int(key), forKey: "hotkeyKeyCode")
        UserDefaults.standard.set(Int(modifiers), forKey: "hotkeyModifiers")
    }
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var value: UInt32 = 0
        if flags.contains(.command) { value |= UInt32(cmdKey) }
        if flags.contains(.shift) { value |= UInt32(shiftKey) }
        if flags.contains(.option) { value |= UInt32(optionKey) }
        if flags.contains(.control) { value |= UInt32(controlKey) }
        return value
    }
}
