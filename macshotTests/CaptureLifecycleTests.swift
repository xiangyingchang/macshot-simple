import Cocoa
import XCTest

@MainActor
private final class KeyRequestWindow: CaptureWindow {
    private(set) var keyRequests = 0
    override func makeKey() {
        keyRequests += 1
        super.makeKey()
    }
}

@MainActor
final class CaptureLifecycleTests: XCTestCase {
    private func event(_ type: NSEvent.EventType, in window: NSWindow, x: CGFloat, y: CGFloat) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [],
                          timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                          context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    }

    func testNonKeyWindowAcceptsFirstDrag() {
        _ = NSApplication.shared
        let window = CaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let canvas = CaptureCanvas(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                   image: Fixture.image(), windowRects: [])
        window.contentView = canvas
        window.orderFrontRegardless()
        window.resignKey()
        defer { window.contentView = nil; window.close() }
        XCTAssertFalse(window.isKeyWindow)
        let down = event(.leftMouseDown, in: window, x: 80, y: 80)
        XCTAssertTrue(canvas.acceptsFirstMouse(for: down))
        window.sendEvent(down)
        window.sendEvent(event(.leftMouseDragged, in: window, x: 260, y: 200))
        window.sendEvent(event(.leftMouseUp, in: window, x: 260, y: 200))
        XCTAssertEqual(canvas.selection, NSRect(x: 80, y: 80, width: 180, height: 120))
    }

    func testClosedWindowReleasesCanvasAndPixelsEvenWhenWindowIsRetained() {
        _ = NSApplication.shared
        let window = CaptureWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
                                   styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        weak var canvas: CaptureCanvas?
        weak var image: CGImage?
        autoreleasepool {
            let pixels = Fixture.image(width: 1600, height: 1200)
            let view = CaptureCanvas(frame: window.frame, image: pixels, windowRects: [])
            canvas = view; image = pixels
            window.contentView = view
            window.orderFrontRegardless()
        }
        autoreleasepool { window.close() }
        XCTAssertNil(canvas)
        XCTAssertNil(image)
    }

    func testEnteringRequestsKeyAndUpdatesResponderPreviewAndCursor() throws {
        _ = NSApplication.shared
        let bounds = NSRect(x: 0, y: 0, width: 600, height: 400)
        let windows = (0..<2).map { _ in
            let window = KeyRequestWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = CaptureCanvas(frame: bounds, image: Fixture.image(),
                                               windowRects: [NSRect(x: 30, y: 30, width: 300, height: 250)])
            window.orderFrontRegardless()
            return window
        }
        defer { windows.forEach { $0.close() } }
        let first = try XCTUnwrap(windows[0].contentView as? CaptureCanvas)
        let second = try XCTUnwrap(windows[1].contentView as? CaptureCanvas)
        // A headless XCTest runner cannot reliably activate a real key window.
        // Observe the AppKit request, and verify real responder/cursor state.
        let secondRequests = windows[1].keyRequests
        second.mouseEntered(with: event(.mouseMoved, in: windows[1], x: 80, y: 80))
        XCTAssertEqual(windows[1].keyRequests, secondRequests + 1)
        XCTAssertTrue(windows[1].firstResponder === second)
        XCTAssertEqual(second.preview, NSRect(x: 30, y: 30, width: 300, height: 250))
        XCTAssertEqual(NSCursor.current, .crosshair)
        let firstRequests = windows[0].keyRequests
        first.mouseEntered(with: event(.mouseMoved, in: windows[0], x: 80, y: 80))
        XCTAssertEqual(windows[0].keyRequests, firstRequests + 1)
        XCTAssertTrue(windows[0].firstResponder === first)
        XCTAssertEqual(NSCursor.current, .crosshair)
        first.select(NSRect(x: 40, y: 40, width: 300, height: 200))
        first.cursorUpdate(with: event(.mouseMoved, in: windows[0], x: 80, y: 80))
        XCTAssertEqual(NSCursor.current, .openHand)
        first.perform(.tool(.text))
        first.mouseDown(with: event(.leftMouseDown, in: windows[0], x: 80, y: 100))
        let editor = try XCTUnwrap(windows[0].firstResponder as? NSTextView)
        editor.string = "中文输入保留"
        second.mouseEntered(with: event(.mouseMoved, in: windows[1], x: 80, y: 80))
        first.mouseEntered(with: event(.mouseMoved, in: windows[0], x: 80, y: 100))
        XCTAssertTrue(windows[0].firstResponder === editor)
        XCTAssertEqual(editor.string, "中文输入保留")
        XCTAssertEqual(NSCursor.current, .iBeam)
        first.cursorUpdate(with: event(.mouseMoved, in: windows[0], x: first.toolbar.frame.midX, y: first.toolbar.frame.midY))
        XCTAssertEqual(NSCursor.current, .arrow)
    }
}

@MainActor
final class CaptureCompletionTests: XCTestCase {
    private func show(_ app: AppDelegate) throws -> CaptureWindow {
        try autoreleasepool {
            let screen = try XCTUnwrap(NSScreen.screens.first)
            app.showCaptures([ScreenCapture(screen: screen, image: Fixture.image(width: 1600, height: 1200))], windowInfo: [])
            return try XCTUnwrap(NSApp.windows.compactMap { $0 as? CaptureWindow }.first { $0.contentView is CaptureCanvas })
        }
    }

    func testCancelReleasesAppOwnedCanvasAndPixels() throws {
        let app = AppDelegate()
        let window = try show(app)
        weak var canvas = window.contentView as? CaptureCanvas
        weak var image = canvas?.baseImage
        autoreleasepool { canvas?.perform(.cancel) }
        XCTAssertNil(window.contentView)
        XCTAssertNil(canvas)
        XCTAssertNil(image)
    }

    func testScrollTransitionReleasesOrdinaryCanvasPixelsAndCallbacks() throws {
        let app = AppDelegate()
        let window = try show(app)
        weak var canvas = window.contentView as? CaptureCanvas
        weak var image = canvas?.baseImage
        // Exercise the exact cleanup boundary used before ScrollCaptureSession
        // starts, without requesting screen-recording permission in XCTest.
        autoreleasepool { app.closeCaptureWindows() }
        XCTAssertNil(window.contentView)
        XCTAssertNil(canvas)
        XCTAssertNil(image)
    }

    func testCopyReleasesPixelsAndKeepsFullResolutionPNGAndTIFF() throws {
        let app = AppDelegate()
        let window = try show(app)
        weak var canvas = window.contentView as? CaptureCanvas
        weak var image = canvas?.baseImage
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try autoreleasepool {
            let view = try XCTUnwrap(canvas)
            view.select(view.bounds)
            app.copy(try XCTUnwrap(view.outputImage()), to: board)
        }
        for type in [NSPasteboard.PasteboardType.png, .tiff] {
            let bitmap = try XCTUnwrap(NSBitmapImageRep(data: XCTUnwrap(board.data(forType: type))))
            XCTAssertEqual(bitmap.pixelsWide, 1600)
            XCTAssertEqual(bitmap.pixelsHigh, 1200)
            let pixel = try XCTUnwrap(bitmap.colorAt(x: 10, y: 10))
            XCTAssertEqual(pixel.redComponent, 1, accuracy: 0.01)
        }
        XCTAssertNil(canvas)
        XCTAssertNil(image)
    }

    func testSuccessfulSaveReleasesPixels() throws {
        let app = AppDelegate()
        let window = try show(app)
        weak var canvas = window.contentView as? CaptureCanvas
        weak var image = canvas?.baseImage
        // Synthetic pixels only. Keep the fixture with the other local test artifacts.
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("build/lifecycle-fixtures", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("synthetic-save.png")
        try autoreleasepool {
            let view = try XCTUnwrap(canvas)
            view.select(view.bounds)
            let output = try XCTUnwrap(view.outputImage())
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]))
            try app.savePNG(png, to: url)
        }
        let saved = try XCTUnwrap(NSBitmapImageRep(data: Data(contentsOf: url)))
        XCTAssertEqual(saved.pixelsWide, 1600)
        XCTAssertEqual(saved.pixelsHigh, 1200)
        XCTAssertNil(canvas)
        XCTAssertNil(image)
    }

    func testFailedSaveKeepsEditablePixels() throws {
        let app = AppDelegate()
        let window = try show(app)
        defer { (window.contentView as? CaptureCanvas)?.perform(.cancel) }
        let canvas = try XCTUnwrap(window.contentView as? CaptureCanvas)
        canvas.select(canvas.bounds)
        XCTAssertThrowsError(try app.savePNG(Data(), to: URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("build/missing-save-parent/never.png")))
        XCTAssertTrue(window.contentView === canvas)
        XCTAssertNotNil(canvas.outputImage())
    }
}
