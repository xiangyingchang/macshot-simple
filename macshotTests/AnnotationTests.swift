import Cocoa
import XCTest

@MainActor
final class AnnotationTests: XCTestCase {
    func testUndoRedoAndNewBranchDiscardOldRedo() {
        var history = AnnotationHistory()
        let annotation = Annotation(tool: .rectangle, points: [.zero, NSPoint(x: 20, y: 20)], color: .red, width: 4)
        history.append(annotation); history.undo()
        XCTAssertTrue(history.annotations.isEmpty); XCTAssertEqual(history.undone.count, 1)
        history.redo(); XCTAssertEqual(history.annotations.count, 1)
        history.undo(); history.append(annotation)
        XCTAssertTrue(history.undone.isEmpty)
        history.clear(); XCTAssertTrue(history.annotations.isEmpty)
    }
    func testRectangleAndRetinaRenderAtCanvasCoordinates() throws {
        let base = Fixture.image(width: 400, height: 200)
        let annotation = Annotation(tool: .rectangle, points: [NSPoint(x: 20, y: 10), NSPoint(x: 80, y: 40)], color: .red, width: 4)
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, canvas: NSSize(width: 200, height: 100), annotations: [annotation]))
        let stroke = Fixture.color(image, x: 40, y: 150)
        let expected = NSColor.red.usingColorSpace(.sRGB)!
        XCTAssertEqual(stroke.redComponent, expected.redComponent, accuracy: 0.02)
        XCTAssertEqual(stroke.greenComponent, expected.greenComponent, accuracy: 0.02)
        XCTAssertGreaterThan(Fixture.color(image, x: 100, y: 150).greenComponent, 0.9)
        XCTAssertEqual(image.width, 400); XCTAssertEqual(image.height, 200)
    }
    func testAllSixToolsProduceExportablePixels() throws {
        for tool in AnnotationTool.allCases {
            let base = Fixture.image(stripes: tool == .pixelate)
            let annotation = Annotation(tool: tool, points: [NSPoint(x: 20, y: 20), NSPoint(x: 80, y: 70)], color: .red, width: 4, text: "测试 Hello")
            let image = try XCTUnwrap(AnnotationRenderer.render(base: base, canvas: NSSize(width: 200, height: 100), annotations: [annotation]))
            let data = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(data.count, 100)
            XCTAssertNotEqual(data, NSBitmapImageRep(cgImage: base).representation(using: .png, properties: [:]))
        }
    }
    func testMosaicChangesStripesOnlyInsideItsRegion() throws {
        let base = Fixture.image(stripes: true)
        let annotation = Annotation(tool: .pixelate, points: [NSPoint(x: 20, y: 20), NSPoint(x: 80, y: 80)], color: .red, width: 8)
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, canvas: NSSize(width: 200, height: 100), annotations: [annotation]))
        let a = Fixture.color(image, x: 40, y: 50).redComponent
        let b = Fixture.color(image, x: 41, y: 50).redComponent
        XCTAssertEqual(a, b, accuracy: 0.02)
        XCTAssertGreaterThan(abs(Fixture.color(base, x: 40, y: 50).redComponent - Fixture.color(base, x: 41, y: 50).redComponent), 0.9)
        XCTAssertEqual(Fixture.color(image, x: 0, y: 0).redComponent, Fixture.color(base, x: 0, y: 0).redComponent, accuracy: 0.01)
    }
    func testMosaicIncludesEarlierAnnotationPixels() throws {
        let base = Fixture.image()
        let mark = Annotation(tool: .rectangle, points: [NSPoint(x: 30, y: 20), NSPoint(x: 60, y: 80)], color: .red, width: 12)
        let mosaic = Annotation(tool: .pixelate, points: [NSPoint(x: 20, y: 10), NSPoint(x: 80, y: 90)], color: .red, width: 8)
        let image = try XCTUnwrap(AnnotationRenderer.render(base: base, canvas: NSSize(width: 200, height: 100), annotations: [mark, mosaic]))
        // If mosaic accidentally uses the raw screenshot, every pixel is white.
        let colors = (20..<80).map { Fixture.color(image, x: $0, y: 50).greenComponent }
        XCTAssertTrue(colors.contains { $0 < 0.8 })
        XCTAssertTrue(colors.contains { $0 > 0.95 })
    }
}
