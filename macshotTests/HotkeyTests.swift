import Cocoa
import Carbon
import XCTest

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
}
