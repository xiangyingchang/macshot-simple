import Cocoa
import XCTest

final class HotkeyTests: XCTestCase {
    func testStatusPopoverCaptureButtonInvokesCaptureAction() throws {
        var captureRequested = false
        let controller = StatusPopoverController(
            hotkeyDescription: "⌃A",
            onCapture: { captureRequested = true },
            onSettings: {},
            onPermissionSettings: {},
            onAbout: {},
            onQuit: {}
        )
        XCTAssertLessThan(controller.preferredContentSize.width, 220)
        let button = try XCTUnwrap(findButton(accessibilityLabel: "截图，快捷键 ⌃A", in: controller.view))

        button.performClick(nil)

        XCTAssertTrue(captureRequested)
    }

    private func findButton(accessibilityLabel: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityLabel() == accessibilityLabel { return button }
        for subview in view.subviews {
            if let button = findButton(accessibilityLabel: accessibilityLabel, in: subview) { return button }
        }
        return nil
    }
}
