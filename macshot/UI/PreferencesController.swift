// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

final class ShortcutField: NSTextField {
    var onShortcut: ((UInt32, UInt32) -> Void)?
    var onRecording: ((Bool) -> Void)?
    private(set) var recording = false
    override var acceptsFirstResponder: Bool { true }
    override func becomeFirstResponder() -> Bool {
        recording = true; stringValue = "按下快捷键…"; updateRecordingStyle(); onRecording?(true)
        return true
    }
    override func resignFirstResponder() -> Bool {
        recording = false; stringValue = SimpleSettings.hotkeyDescription; updateRecordingStyle(); onRecording?(false)
        return true
    }
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); updateRecordingStyle() }
    func updateRecordingStyle() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
            layer?.borderColor = (recording ? SimpleSettings.green : NSColor.separatorColor).cgColor
        }
        layer?.borderWidth = recording ? 2 : 1; needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font ?? NSFont.systemFont(ofSize: 16, weight: .medium), .foregroundColor: NSColor.labelColor]
        let size = (stringValue as NSString).size(withAttributes: attributes)
        (stringValue as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { _ = resignFirstResponder(); window?.makeFirstResponder(nil); return }
        let modifiers = SimpleSettings.carbonModifiers(event.modifierFlags)
        guard modifiers != 0, ![36, 48, 51, 53].contains(event.keyCode) else { NSSound.beep(); return }
        onShortcut?(UInt32(event.keyCode), modifiers)
        _ = resignFirstResponder(); window?.makeFirstResponder(nil)
    }
}

/// Separate native content view makes light/dark rendering testable without
/// opening a real window or requesting screen-recording permission.
final class PreferencesContentView: NSView {
    let shortcutField: ShortcutField
    init(onShortcut: @escaping (UInt32, UInt32) -> Void) {
        shortcutField = ShortcutField(frame: NSRect(x: 170, y: 94, width: 182, height: 40))
        super.init(frame: NSRect(x: 0, y: 0, width: 380, height: 238))
        wantsLayer = true
        let title = NSTextField(labelWithString: "随手截一张")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        title.frame = NSRect(x: 28, y: 174, width: 324, height: 30); addSubview(title)
        let subtitle = NSTextField(labelWithString: "框选、标注，复制到你正在用的应用。")
        subtitle.font = .systemFont(ofSize: 12); subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 28, y: 147, width: 324, height: 20); addSubview(subtitle)
        let label = NSTextField(labelWithString: "截图快捷键")
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.frame = NSRect(x: 28, y: 104, width: 112, height: 20); addSubview(label)
        let field = shortcutField
        field.isEditable = false; field.isSelectable = false; field.isBordered = false; field.drawsBackground = false
        field.alignment = .center; field.font = .systemFont(ofSize: 16, weight: .medium)
        field.stringValue = SimpleSettings.hotkeyDescription
        field.wantsLayer = true; field.layer?.cornerRadius = 8
        field.focusRingType = .none; field.onShortcut = onShortcut
        field.setAccessibilityLabel("录入截图快捷键"); addSubview(field); field.updateRecordingStyle()
        let help = NSTextField(wrappingLabelWithString: "点击快捷键修改。截图时按 Esc 退出。")
        help.textColor = .secondaryLabelColor; help.font = .systemFont(ofSize: 11)
        help.frame = NSRect(x: 28, y: 40, width: 324, height: 30)
        field.onRecording = { [weak help] recording in
            help?.stringValue = recording ? "按下带 ⌘、⌃、⌥ 或 ⇧ 的组合键。Esc 放弃修改。" : "点击快捷键修改。截图时按 Esc 退出。"
        }
        addSubview(help)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) { NSColor.windowBackgroundColor.setFill(); bounds.fill() }
}

final class PreferencesController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?
    init(onShortcut: @escaping (UInt32, UInt32) -> Void) {
        let content = PreferencesContentView(onShortcut: onShortcut)
        let window = NSWindow(contentRect: content.bounds, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "截图设置"; window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self; window.contentView = content
        window.center(); window.makeFirstResponder(nil)
    }
    required init?(coder: NSCoder) { fatalError() }
    func windowWillClose(_ notification: Notification) { onClose?() }
}
