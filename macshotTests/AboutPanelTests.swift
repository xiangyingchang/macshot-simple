import Cocoa
import XCTest

@MainActor
final class AboutPanelTests: XCTestCase {
    func testAboutPanelUsesOpaqueLightPaperSurface() throws {
        let controller = AboutPanelController(version: "test")
        let panel = try XCTUnwrap(controller.window)

        XCTAssertEqual(panel.appearance?.name, .aqua)
        XCTAssertTrue(panel.isOpaque)
        XCTAssertTrue(panel.backgroundColor.isEqual(DesignTheme.paper))
        XCTAssertEqual(panel.contentView?.layer?.backgroundColor?.alpha, 1)
    }
}
