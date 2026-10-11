import Cocoa
import Carbon
import XCTest

private final class MenuKeyEquivalentTarget: NSObject {
    private(set) var didCapture = false

    @objc func capture(_ sender: Any?) {
        didCapture = true
    }
}

final class HotkeyTests: XCTestCase {
    func testMenuShortcutMatcherUsesConfiguredPhysicalKeyAndModifiers() throws {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "x",
            charactersIgnoringModifiers: "x",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_X)
        ))
        let modifiers = UInt32(cmdKey | shiftKey)

        XCTAssertTrue(SimpleSettings.matchesHotkey(event, key: UInt32(kVK_ANSI_X), modifiers: modifiers))
        XCTAssertFalse(SimpleSettings.matchesHotkey(event, key: UInt32(kVK_ANSI_A), modifiers: modifiers))
        XCTAssertFalse(SimpleSettings.matchesHotkey(event, key: UInt32(kVK_ANSI_X), modifiers: UInt32(cmdKey)))
    }

    func testStatusMenuUsesNativeKeyEquivalentForConfiguredHotkey() throws {
        let key = UInt32(kVK_ANSI_A)
        let modifiers = UInt32(controlKey)
        let character = SimpleSettings.menuKeyEquivalent(for: key)
        XCTAssertFalse(character.isEmpty)

        let target = MenuKeyEquivalentTarget()
        let item = NSMenuItem(title: "截图", action: #selector(MenuKeyEquivalentTarget.capture(_:)), keyEquivalent: "")
        item.target = target
        SimpleSettings.configureMenuShortcut(for: item, key: key, modifiers: modifiers)
        XCTAssertEqual(item.keyEquivalent, character)
        XCTAssertEqual(item.keyEquivalentModifierMask, [.control])

        let menu = NSMenu()
        menu.addItem(item)
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: false,
            keyCode: UInt16(key)
        ))

        XCTAssertTrue(menu.performKeyEquivalent(with: event))
        XCTAssertTrue(target.didCapture)
    }
}
