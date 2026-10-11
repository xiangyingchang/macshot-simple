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
        let button = try XCTUnwrap(findButton(titled: "截图", in: controller.view))

        button.performClick(nil)

        XCTAssertTrue(captureRequested)
    }

    private func findButton(titled title: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.title == title { return button }
        for subview in view.subviews {
            if let button = findButton(titled: title, in: subview) { return button }
        }
        return nil
    }
}
