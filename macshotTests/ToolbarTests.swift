import Cocoa
import XCTest

@MainActor
final class ToolbarTests: XCTestCase {
    func testThreeDiscreteWidthsPersistAndPaletteHasNoSlider() {
        withDefaults(["simpleStrokeWidth_0": 4]) {
            let toolbar = CaptureToolbar(frame: .zero)
            toolbar.onWidth = { value in SimpleSettings.saveWidth(value, for: .rectangle) }
            toolbar.update(tool: .rectangle, width: 4, colorIndex: 5, fontSize: 18, canUndo: false, canRedo: false)
            XCTAssertEqual(toolbar.buttons.count, 11); XCTAssertEqual(toolbar.widthButtons.count, 3)
            for (index, width) in SimpleSettings.widths.enumerated() {
                toolbar.widthButtons[index].performClick(nil)
                XCTAssertEqual(SimpleSettings.strokeWidth(for: .rectangle), width)
            }
            func hasSlider(_ view: NSView) -> Bool { view is NSSlider || view.subviews.contains(where: hasSlider) }
            XCTAssertFalse(hasSlider(toolbar))
        }
    }
    func testToolbarRendersBothSystemAppearances() throws {
        let toolbar = CaptureToolbar(frame: .zero)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            toolbar.appearance = NSAppearance(named: appearance)
            toolbar.update(tool: .rectangle, width: 4, colorIndex: 5, fontSize: 18, canUndo: true, canRedo: true)
            let rep = try XCTUnwrap(toolbar.bitmapImageRepForCachingDisplay(in: toolbar.bounds))
            toolbar.cacheDisplay(in: toolbar.bounds, to: rep)
            let png = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
            try png.write(to: URL(fileURLWithPath: "/tmp/macshot-simple-trim-toolbar-\(appearance.rawValue).png"))
            XCTAssertGreaterThan(png.count, 1000)
        }
    }
    func testMainRowStaysAnchoredWhenOptionsOpenAtScreenEdges() {
        for selection in [NSRect(x: 20, y: 20, width: 300, height: 50),
                          NSRect(x: 200, y: 300, width: 400, height: 200),
                          NSRect(x: 0, y: 0, width: 800, height: 600)] {
            let canvas = CaptureCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600), image: Fixture.image(width: 800, height: 600), windowRects: [])
            canvas.select(selection)
            let before = canvas.toolbar.convert(canvas.toolbar.mainRowFrame, to: canvas)
            canvas.perform(.tool(.rectangle))
            let after = canvas.toolbar.convert(canvas.toolbar.mainRowFrame, to: canvas)
            XCTAssertEqual(before, after)
            XCTAssertTrue(canvas.bounds.contains(canvas.toolbar.frame))
            canvas.perform(.tool(.rectangle))
            XCTAssertEqual(before, canvas.toolbar.convert(canvas.toolbar.mainRowFrame, to: canvas))
        }
    }

    func testVectorIconsAreUpright() throws {
        func pixel(_ button: ToolbarButton, _ point: NSPoint) throws -> NSColor {
            let bitmap = try XCTUnwrap(button.bitmapImageRepForCachingDisplay(in: button.bounds))
            button.cacheDisplay(in: button.bounds, to: bitmap)
            let scale = CGFloat(bitmap.pixelsWide) / button.bounds.width
            return try XCTUnwrap(bitmap.colorAt(x: Int(point.x * scale), y: Int((button.bounds.height - point.y) * scale)))
        }
        let check = ToolbarButton(frame: NSRect(x: 0, y: 0, width: 36, height: 36))
        check.symbol = "checkmark"; check.tint = DesignTheme.green
        let checkTip = try pixel(check, NSPoint(x: 26, y: 25))
        // Edge coverage varies with backing scale and rasterization on CI.
        XCTAssertGreaterThan(checkTip.alphaComponent, 0.5)
        XCTAssertLessThan(try pixel(check, NSPoint(x: 26, y: 11)).alphaComponent, 0.2)
        XCTAssertLessThan(checkTip.redComponent, 0.2)
        let text = ToolbarButton(frame: check.frame); text.tool = .text
        let textCap = try pixel(text, NSPoint(x: 15, y: 22))
        XCTAssertGreaterThan(textCap.alphaComponent, 0.5)
        XCTAssertLessThan(try pixel(text, NSPoint(x: 15, y: 14)).alphaComponent, 0.2)
        XCTAssertLessThan(textCap.redComponent, 0.5)
    }

    func testPreferencesRenderBothAppearancesAndRecordingCanCancel() throws {
        let view = PreferencesContentView { _, _ in XCTFail("No shortcut should be saved by rendering") }
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            view.appearance = NSAppearance(named: appearance)
            view.shortcutField.updateRecordingStyle()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: "/tmp/macshot-simple-design-settings-\(appearance.rawValue).png"))
            XCTAssertGreaterThan(data.count, 1000)
        }
        XCTAssertTrue(view.shortcutField.becomeFirstResponder())
        XCTAssertTrue(view.shortcutField.recording)
        XCTAssertTrue(view.shortcutField.resignFirstResponder())
        XCTAssertFalse(view.shortcutField.recording)
        XCTAssertEqual(view.shortcutField.stringValue, SimpleSettings.hotkeyDescription)
    }

    func testInvalidSettingsAreBounded() {
        withDefaults(["simpleStrokeWidth_0": 999, "simpleColorIndex": -100, "simpleFontSize": 999]) {
            XCTAssertEqual(SimpleSettings.strokeWidth(for: .rectangle), 8)
            XCTAssertEqual(SimpleSettings.colorIndex, 0); XCTAssertEqual(SimpleSettings.fontSize, 72)
        }
    }
}
