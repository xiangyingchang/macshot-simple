import Cocoa
import XCTest

@MainActor
final class CaptureCanvasTests: XCTestCase {
    private func canvas(windows: [NSRect] = []) -> CaptureCanvas {
        CaptureCanvas(frame: NSRect(x: 0, y: 0, width: 800, height: 600), image: Fixture.image(width: 1600, height: 1200), windowRects: windows)
    }
    private func doubleClick(_ view: CaptureCanvas, at point: NSPoint) {
        for clicks in 1...2 {
            view.mouseDown(with: Fixture.event(.leftMouseDown, x: point.x, y: point.y, clicks: clicks))
            view.mouseUp(with: Fixture.event(.leftMouseUp, x: point.x, y: point.y, clicks: clicks))
        }
    }

    private func window(containing view: CaptureCanvas) -> NSWindow {
        _ = NSApplication.shared
        let window = CaptureWindow(contentRect: view.bounds, styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        window.becomeKey()
        return window
    }

    private var eventNumber = 0

    private func click(in window: NSWindow, at point: NSPoint, count: Int = 1) {
        let time = ProcessInfo.processInfo.systemUptime
        func event(_ type: NSEvent.EventType) -> NSEvent {
            eventNumber += 1
            return NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: time,
                              windowNumber: window.windowNumber, context: nil, eventNumber: eventNumber,
                              clickCount: count, pressure: type == .leftMouseDown ? 1 : 0)!
        }
        // NSTextView tracks the mouse synchronously and consumes the queued mouse-up.
        let up = event(.leftMouseUp)
        NSApp.postEvent(up, atStart: true)
        NSApp.postEvent(event(.leftMouseDown), atStart: true)
        let down = NSApp.nextEvent(matching: .leftMouseDown, until: Date(), inMode: .default, dequeue: true)!
        NSApp.sendEvent(down)
        if let remaining = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true) {
            NSApp.sendEvent(remaining)
        }
    }

    func testWindowDispatchDoubleClickThroughNewEmptyTextEditor() throws {
        let view = canvas()
        let window = window(containing: view)
        defer { window.close() }
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.text))
        var copies = 0
        view.onCopy = { _ in copies += 1 }
        click(in: window, at: NSPoint(x: 160, y: 250))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
        // Move slightly inside the editor: an exact repeat may land on its top edge.
        let second = NSPoint(x: 162, y: 248)
        XCTAssertTrue(view.hitTest(second) === editor)
        click(in: window, at: second, count: 2)
        XCTAssertEqual(copies, 1)
        XCTAssertTrue(view.history.annotations.isEmpty)
        XCTAssertFalse(view.subviews.contains { $0 is NSTextView })
    }

    func testSecondClickHitOnNewEmptyEditorCompletesCapture() throws {
        let view = canvas()
        let window = window(containing: view)
        defer { window.close() }
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.text))
        var copies = 0
        view.onCopy = { _ in copies += 1 }
        click(in: window, at: NSPoint(x: 160, y: 250))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
        let point = NSPoint(x: 162, y: 248)
        let target = try XCTUnwrap(window.contentView?.hitTest(point))
        XCTAssertTrue(target === editor)
        // AppKit may retain the first click's target across a double-click on some OS versions.
        // Also exercise delivery to the actual second hit, without assuming canvas receives it.
        NSApp.postEvent(Fixture.event(.leftMouseUp, x: point.x, y: point.y, clicks: 2), atStart: true)
        target.mouseDown(with: Fixture.event(.leftMouseDown, x: point.x, y: point.y, clicks: 2))
        _ = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true)
        XCTAssertEqual(copies, 1)
        XCTAssertNil(editor.superview)
    }

    func testHitTestMarkedTextAndEditedEmptyEditorDoNotCopy() throws {
        for marked in [true, false] {
            let view = canvas()
            let window = window(containing: view)
            defer { window.close() }
            view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
            view.perform(.tool(.text))
            var copies = 0
            view.onCopy = { _ in copies += 1 }
            click(in: window, at: NSPoint(x: 160, y: 250))
            let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
            if marked {
                editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0),
                                     replacementRange: NSRange(location: NSNotFound, length: 0))
                XCTAssertTrue(editor.hasMarkedText())
            } else {
                editor.insertText("x", replacementRange: NSRange(location: NSNotFound, length: 0))
                editor.setSelectedRange(NSRange(location: 0, length: 1))
                editor.deleteBackward(nil)
                XCTAssertTrue(editor.string.isEmpty)
            }
            let point = view.convert(NSPoint(x: 8, y: 8), from: editor)
            let target = try XCTUnwrap(window.contentView?.hitTest(point))
            XCTAssertTrue(target === editor)
            NSApp.postEvent(Fixture.event(.leftMouseUp, x: point.x, y: point.y, clicks: 2), atStart: true)
            target.mouseDown(with: Fixture.event(.leftMouseDown, x: point.x, y: point.y, clicks: 2))
            _ = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true)
            XCTAssertEqual(copies, 0)
            XCTAssertTrue(editor.superview === view)
        }
    }

    func testWindowDispatchToolbarDoubleClickDoesNotCopy() throws {
        let view = canvas()
        let window = window(containing: view)
        defer { window.close() }
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        var copies = 0
        view.onCopy = { _ in copies += 1 }
        let button = try XCTUnwrap(view.toolbar.buttons.first { $0.tool == .rectangle })
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: view)
        XCTAssertTrue(view.hitTest(point) === button)
        click(in: window, at: point)
        click(in: window, at: point, count: 2)
        XCTAssertEqual(copies, 0)
        XCTAssertNil(view.activeTool)
    }

    func testLockedSelectionDoubleClickPreservesCrop() throws {
        let view = canvas()
        let window = window(containing: view)
        defer { window.close() }
        view.locksSelection = true
        let rect = NSRect(x: 100, y: 100, width: 300, height: 200)
        view.select(rect)
        view.perform(.tool(.text))
        var copies = 0
        view.onCopy = { image in
            copies += 1
            XCTAssertEqual(image.width, 600)
            XCTAssertEqual(image.height, 400)
        }
        click(in: window, at: NSPoint(x: 600, y: 400))
        click(in: window, at: NSPoint(x: 600, y: 400), count: 2)
        XCTAssertEqual(copies, 1)
        XCTAssertEqual(view.selection, rect)
    }

    func testPencilCompletionRestoresRedoHistoryAndSingleClickStillDraws() {
        let view = canvas()
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.pencil))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 200, y: 200))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 200, y: 200))
        XCTAssertEqual(view.history.annotations.count, 1)
        view.perform(.undo)
        XCTAssertEqual(view.history.undone.count, 1)
        doubleClick(view, at: NSPoint(x: 220, y: 220))
        XCTAssertTrue(view.history.annotations.isEmpty)
        XCTAssertEqual(view.history.undone.count, 1)
        view.perform(.redo)
        XCTAssertEqual(view.history.annotations.count, 1)
    }

    func testWindowDispatchDoubleClickSelectsExistingWord() throws {
        let view = canvas()
        let window = window(containing: view)
        defer { window.close() }
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.text))
        var copies = 0
        view.onCopy = { _ in copies += 1 }
        click(in: window, at: NSPoint(x: 160, y: 250))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
        editor.insertText("hello world", replacementRange: NSRange(location: NSNotFound, length: 0))
        let point = view.convert(NSPoint(x: 8, y: 8), from: editor)
        XCTAssertTrue(view.hitTest(point) === editor)
        click(in: window, at: point)
        click(in: window, at: point, count: 2)
        XCTAssertEqual(copies, 0)
        XCTAssertEqual((editor.string as NSString).substring(with: editor.selectedRange()), "hello")
        XCTAssertTrue(editor.superview === view)
    }

    func testDoubleClickInsideOutsideAndHandleCopiesOriginalCrop() throws {
        for point in [NSPoint(x: 200, y: 200), NSPoint(x: 600, y: 400), NSPoint(x: 100, y: 100)] {
            let view = canvas()
            let rect = NSRect(x: 100, y: 100, width: 300, height: 200)
            view.select(rect)
            var copies: [CGImage] = []
            view.onCopy = { copies.append($0) }
            doubleClick(view, at: point)
            XCTAssertEqual(copies.count, 1)
            let image = try XCTUnwrap(copies.first)
            XCTAssertEqual(image.width, 600)
            XCTAssertEqual(image.height, 400)
            XCTAssertEqual(view.selection, rect)
        }
    }

    func testDoubleClickCopiesWithEveryAnnotationToolActive() throws {
        for tool in [AnnotationTool.rectangle, .ellipse, .arrow, .pencil, .pixelate, .text] {
            for point in [NSPoint(x: 300, y: 200), NSPoint(x: 600, y: 400)] {
                let view = canvas()
                let window = window(containing: view)
                defer { window.close() }
                view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
                view.perform(.tool(.rectangle))
                view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 150))
                view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 250, y: 220))
                view.mouseUp(with: Fixture.event(.leftMouseUp, x: 250, y: 220))
                if tool != .rectangle { view.perform(.tool(tool)) }
                let before = try XCTUnwrap(view.outputImage())
                var copied: CGImage?
                view.onCopy = { copied = $0 }
                click(in: window, at: point)
                click(in: window, at: point, count: 2)
                let after = try XCTUnwrap(copied)
                XCTAssertEqual(after.width, before.width)
                XCTAssertEqual(after.height, before.height)
                // The original rectangle survives both clicks, including outside clicks.
                XCTAssertEqual(view.history.annotations.count, 1)
                XCTAssertEqual(view.history.annotations.first?.tool, .rectangle)
                XCTAssertEqual(NSBitmapImageRep(cgImage: after).representation(using: .png, properties: [:]),
                               NSBitmapImageRep(cgImage: before).representation(using: .png, properties: [:]))
                let expected = Fixture.color(before, x: 100, y: 230)
                let actual = Fixture.color(after, x: 100, y: 230)
                XCTAssertEqual(actual.redComponent, expected.redComponent, accuracy: 0.01)
                XCTAssertEqual(actual.greenComponent, expected.greenComponent, accuracy: 0.01)
            }
        }
    }

    func testOutsideDoubleClickCommitsTextBeforeCopy() throws {
        let view = canvas()
        view.select(NSRect(x: 100, y: 100, width: 300, height: 200))
        view.perform(.tool(.text))
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 150, y: 250))
        let editor = try XCTUnwrap(view.subviews.compactMap { $0 as? NSTextView }.first)
        editor.string = "中文标注"
        var copied = false
        view.onCopy = { _ in copied = true }
        doubleClick(view, at: NSPoint(x: 600, y: 400))
        XCTAssertTrue(copied)
        XCTAssertEqual(view.history.annotations.first?.text, "中文标注")
        XCTAssertFalse(view.subviews.contains { $0 is NSTextView })
    }

    func testOutsideClickPreservesSelectionButDragReselects() {
        let view = canvas()
        let original = NSRect(x: 100, y: 100, width: 300, height: 200)
        view.select(original)
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 500, y: 400))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 500, y: 400))
        XCTAssertEqual(view.selection, original)
        XCTAssertFalse(view.toolbar.isHidden)
        view.mouseDown(with: Fixture.event(.leftMouseDown, x: 500, y: 400))
        view.mouseDragged(with: Fixture.event(.leftMouseDragged, x: 700, y: 550))
        view.mouseUp(with: Fixture.event(.leftMouseUp, x: 700, y: 550))
        XCTAssertEqual(view.selection, NSRect(x: 500, y: 400, width: 200, height: 150))
    }

    func testDoubleClickWithoutSelectionDoesNotCopy() {
        let view = canvas()
        var copies = 0
        view.onCopy = { _ in copies += 1 }
        doubleClick(view, at: NSPoint(x: 200, y: 200))
        XCTAssertEqual(copies, 0)
        XCTAssertNil(view.selection)
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
    func testUndimmedPanelPixelsStayAtCapturedBrightness() throws {
        let view = CaptureCanvas(
            frame: NSRect(x: 0, y: 0, width: 200, height: 100),
            image: Fixture.image(width: 200, height: 100),
            windowRects: [],
            undimmedRects: [NSRect(x: 50, y: 25, width: 60, height: 50)]
        )
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)

        let scaleX = CGFloat(bitmap.pixelsWide) / view.bounds.width
        let scaleY = CGFloat(bitmap.pixelsHigh) / view.bounds.height
        let outside = try XCTUnwrap(bitmap.colorAt(x: Int(20 * scaleX), y: Int(50 * scaleY)))
            .usingColorSpace(.deviceRGB)
        let inside = try XCTUnwrap(bitmap.colorAt(x: Int(80 * scaleX), y: Int(50 * scaleY)))
            .usingColorSpace(.deviceRGB)
        let dimmedBrightness = try XCTUnwrap(outside).redComponent
        let preservedBrightness = try XCTUnwrap(inside).redComponent
        XCTAssertLessThan(dimmedBrightness, 0.75)
        XCTAssertGreaterThan(preservedBrightness, 0.9)
        XCTAssertGreaterThan(preservedBrightness - dimmedBrightness, 0.2)
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
