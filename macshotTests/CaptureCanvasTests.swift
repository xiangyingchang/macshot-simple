import Cocoa
import XCTest

@MainActor
final class CaptureCanvasTests: XCTestCase {
    private func canvas(windows: [NSRect] = []) -> CaptureCanvas {
        CaptureCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600), image: Fixture.image(width: 1600, height: 1200), windowRects: windows)
    }
    func testInitialWindowPreviewAndClickSelect() {
        let rect = NSRect(x: 100, y: 100, width: 300, height: 200)
        let view = canvas(windows: [rect])
        view.refreshPreview(at: NSPoint(x: 150, y: 150))
        XCTAssertEqual(view.preview, rect); XCTAssertNil(view.selection)
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 150))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 150, y: 150))
        XCTAssertEqual(view.selection, rect); XCTAssertFalse(view.toolbar.isHidden)
    }
    func testEmptyDesktopClickDoesNotSelectFullScreen() {
        let view = canvas()
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 150))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 150, y: 150))
        XCTAssertNil(view.selection); XCTAssertTrue(view.toolbar.isHidden)
    }
    func testDragSelectionThenMoveAndResize() {
        let view = canvas()
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 100, y: 100))
        view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 300, y: 250))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 300, y: 250))
        XCTAssertEqual(view.selection, NSRect(x: 100, y: 100, width: 200, height: 150))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 150))
        view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 250, y: 200))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 250, y: 200))
        XCTAssertEqual(view.selection, NSRect(x: 200, y: 150, width: 200, height: 150))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 400, y: 300))
        view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 500, y: 350))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 500, y: 350))
        XCTAssertEqual(view.selection, NSRect(x: 200, y: 150, width: 300, height: 200))
    }
    func testDrawingUndoRedoAndCompletionReturnsCrop() throws {
        let view = canvas()
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.rectangle))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 150))
        view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 250, y: 220))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 250, y: 220))
        XCTAssertEqual(view.history.annotations.count, 1)
        view.perform(.undo); XCTAssertTrue(view.history.annotations.isEmpty)
        view.perform(.redo); XCTAssertEqual(view.history.annotations.count, 1)
        var received: CGImage?
        view.onCopy = { received = $0 }
        view.perform(.copy)
        let image = try XCTUnwrap(received)
        XCTAssertEqual(image.width, 600); XCTAssertEqual(image.height, 400)
    }
    func testTextInputCommitsIntoSameVisibleRegion() throws {
        let view = canvas()
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.text))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 250))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
        editor.string = "你好 Simple\n第二行"
        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        view.perform(.copy)
        let output = try XCTUnwrap(view.outputImage())
        let outputRep = NSBitmapImageRep(cgImage: output)
        let data = try XCTUnwrap(outputRep.representation(using: .png, properties: [:]))
        try data.write(to: URL(fileURLWithPath: "/tmp/macshot-simple-trim-text.png"))
        let beforeScale = CGFloat(rep.pixelsHigh) / view.bounds.height
        func firstRedY(_ bitmap: NSBitmapImageRep, region: CGRect) -> Int? {
            for y in Int(region.minY)..<Int(region.maxY) {
                for x in Int(region.minX)..<Int(region.maxX) {
                    guard let color = bitmap.colorAt(x: x, y: y) else { continue }
                    if color.redComponent > 0.7 && color.greenComponent < 0.4 && color.blueComponent < 0.5 { return y }
                }
            }
            return nil
        }
        let beforeY = try XCTUnwrap(firstRedY(rep, region: CGRect(x: 140 * beforeScale, y: 340 * beforeScale, width: 200 * beforeScale, height: 80 * beforeScale)))
        let afterY = try XCTUnwrap(firstRedY(outputRep, region: CGRect(x: 80, y: 80, width: 400, height: 160)))
        // The crop begins at canvas top-coordinate 300; output is 2x scale.
        XCTAssertEqual(CGFloat(beforeY) / beforeScale - 300, CGFloat(afterY) / 2, accuracy: 3)
        XCTAssertEqual(view.history.annotations.first?.text, "你好 Simple\n第二行")
        XCTAssertFalse(view.subviews.contains { $0 is NSTextView })
    }

    func testWindowPreviewIsAbsentOutsideThisScreen() {
        let view = canvas(windows: [NSRect(x: -200, y: 100, width: 500, height: 200)])
        view.refreshPreview(at: NSPoint(x: -100, y: 150))
        XCTAssertNil(view.preview)
    }

    func testRightClickReselectThenCancel() {
        let view = canvas()
        var cancelled = false; view.onCancel = { cancelled = true }
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.rightMouseDown(with: Fixture.event(.rightMouseDown, x: 150, y: 150))
        XCTAssertNil(view.selection); XCTAssertFalse(cancelled)
        view.rightMouseDown(with: Fixture.event(.rightMouseDown, x: 150, y: 150))
        XCTAssertTrue(cancelled)
    }
}
