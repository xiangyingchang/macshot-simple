import Cocoa
import XCTest

@MainActor
final class CaptureGeometryTests: XCTestCase {
    func testRetinaCropUsesTopLeftPixelsAndClipsBounds() {
        let image = Fixture.image(width: 400, height: 200)
        let rect = CaptureGeometry.pixelRect(NSRect(x: 20, y: 10, width: 60, height: 30), canvas: NSSize(width: 200, height: 100), image: image)
        XCTAssertEqual(rect, CGRect(x: 40, y: 120, width: 120, height: 60))
        let clipped = CaptureGeometry.pixelRect(NSRect(x: -10, y: -10, width: 30, height: 30), canvas: NSSize(width: 200, height: 100), image: image)
        XCTAssertEqual(clipped, CGRect(x: 0, y: 160, width: 40, height: 40))
    }
    func testScreensAboveBelowAndLeftUseCorrectCoordinates() {
        for frame in [NSRect(x: -1600, y: 0, width: 1600, height: 900), NSRect(x: 0, y: 900, width: 1600, height: 900), NSRect(x: 0, y: -900, width: 1600, height: 900)] {
            let cg = CGRect(x: frame.minX + 100, y: 900 - frame.maxY + 80, width: 300, height: 200)
            XCTAssertEqual(CaptureGeometry.windowRect(cg, primaryHeight: 900, screenFrame: frame), NSRect(x: 100, y: 620, width: 300, height: 200))
        }
    }
    func testMoveAndAllResizeHandlesStayInScreen() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600)
        let rect = NSRect(x: 100, y: 100, width: 200, height: 150)
        XCTAssertEqual(CaptureGeometry.move(rect, by: NSPoint(x: 900, y: -900), in: bounds), NSRect(x: 600, y: 0, width: 200, height: 150))
        for handle in 0..<8 {
            let resized = CaptureGeometry.resize(rect, handle: handle, to: NSPoint(x: -100, y: 1000), in: bounds)
            XCTAssertTrue(bounds.contains(resized)); XCTAssertGreaterThanOrEqual(resized.width, 2); XCTAssertGreaterThanOrEqual(resized.height, 2)
        }
    }
    func testToolbarFitsSmallAndEdgeSelections() {
        let bounds = NSRect(x: 0, y: 0, width: 800, height: 600), size = NSSize(width: 476, height: 82)
        for selection in [NSRect(x: 0, y: 0, width: 20, height: 20), NSRect(x: 780, y: 580, width: 20, height: 20), NSRect(x: 300, y: 200, width: 50, height: 40)] {
            let origin = CaptureGeometry.toolbarOrigin(selection: selection, size: size, bounds: bounds)
            XCTAssertTrue(bounds.contains(NSRect(origin: origin, size: size)))
        }
    }
}
