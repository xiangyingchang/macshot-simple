// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

/// Optional local diagnostic. Does not save screen pixels or change the clipboard.
enum CaptureCheck {
    /// Opt-in five-cycle capture/cancel diagnostic. Only numeric metadata is
    /// printed; real pixels remain in memory and never reach a file/pasteboard.
    @MainActor static func runLifecycle(app: AppDelegate) async {
        guard CGPreflightScreenCaptureAccess() else {
            print("LIFECYCLE permissionPreflight=false")
            return
        }
        print("LIFECYCLE screens=\(NSScreen.screens.count) cycles=5")
        reportMemory("baseline")
        for cycle in 1...5 {
            var captures: [ScreenCapture]?
            if #available(macOS 14.0, *) { captures = await ScreenCaptureManager.captureAllScreensImmediatelySCK() }
            if captures == nil {
                captures = ScreenCaptureManager.captureAllScreensImmediately(context: ScreenCaptureManager.makeImmediateCaptureContext())
            }
            guard let count = captures?.count, count == NSScreen.screens.count, count > 0 else {
                print("LIFECYCLE cycle=\(cycle) captureFailed=true")
                return
            }
            let probes: [CaptureProbe] = autoreleasepool {
                app.showCaptures(captures!, windowInfo: [])
                return NSApp.windows.compactMap { window in
                    guard let canvas = window.contentView as? CaptureCanvas else { return nil }
                    window.displayIfNeeded()
                    return CaptureProbe(window: window, canvas: canvas)
                }
            }
            captures = nil
            reportMemory("open-\(cycle)")
            if cycle == 1, CommandLine.arguments.contains("--check-window-events") {
                // Activation requested by showCaptures completes on a later
                // run-loop turn, before a user's physical mouse event arrives.
                try? await Task.sleep(nanoseconds: 200_000_000)
                print("WINDOW_EVENTS applicationActive=\(NSApp.isActive)")
                autoreleasepool {
                    for (index, probe) in probes.enumerated() {
                        guard let window = probe.window, let canvas = probe.canvas else { continue }
                        func event(_ type: NSEvent.EventType, _ point: NSPoint) -> NSEvent {
                            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                                               timestamp: ProcessInfo.processInfo.systemUptime,
                                               windowNumber: window.windowNumber, context: nil,
                                               eventNumber: 1, clickCount: 1, pressure: 1)!
                        }
                        let start = NSPoint(x: 30, y: 30), end = NSPoint(x: 130, y: 130)
                        canvas.mouseEntered(with: event(.mouseMoved, start))
                        let enteredKey = window.isKeyWindow
                        let crosshair = NSCursor.current == .crosshair
                        window.resignKey()
                        let initiallyNonKey = !window.isKeyWindow
                        window.sendEvent(event(.leftMouseDown, start))
                        window.sendEvent(event(.leftMouseDragged, end))
                        window.sendEvent(event(.leftMouseUp, end))
                        let selected = canvas.selection == NSRect(x: 30, y: 30, width: 100, height: 100)
                        print("WINDOW_EVENTS screen=\(index) enteredKey=\(enteredKey) crosshair=\(crosshair) initiallyNonKey=\(initiallyNonKey) firstDrag=\(selected) responder=\(window.firstResponder === canvas)")
                    }
                }
            }
            // Use the production cancel callback, shared with Escape/right-click.
            autoreleasepool { probes.first?.canvas?.perform(.cancel) }
            try? await Task.sleep(nanoseconds: 200_000_000)
            reportMemory("cancelled-\(cycle)")
            print("LIFECYCLE cycle=\(cycle) liveWindows=\(probes.filter { $0.window != nil }.count) liveCanvases=\(probes.filter { $0.canvas != nil }.count) liveImages=\(probes.filter { $0.image != nil }.count)")
        }
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        reportMemory("settled")
    }

    private static func reportMemory(_ stage: String) {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        let mib = status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
        print(String(format: "LIFECYCLE stage=%@ rssMiB=%.2f", stage, mib))
    }

    static func run() async {
        let context = ScreenCaptureManager.makeImmediateCaptureContext()
        guard CGPreflightScreenCaptureAccess() else {
            // Diagnostics never request consent on the user's behalf.
            print("{\"permissionPreflight\":false,\"expectedScreens\":\(context.screens.count),\"success\":false,\"capturedScreens\":0}")
            return
        }
        var captures: [ScreenCapture]?
        if #available(macOS 14.0, *) { captures = await ScreenCaptureManager.captureAllScreensImmediatelySCK() }
        if captures == nil, CGPreflightScreenCaptureAccess() {
            captures = ScreenCaptureManager.captureAllScreensImmediately(context: context)
        }
        var result: [String: Any] = ["permissionPreflight": CGPreflightScreenCaptureAccess(), "expectedScreens": context.screens.count]
        if let captures, captures.count == context.screens.count, let first = captures.first {
            let size = first.screen.frame.size
            let rect = NSRect(x: size.width / 4, y: size.height / 4, width: size.width / 2, height: size.height / 2)
            let annotations = AnnotationTool.allCases.map {
                Annotation(tool: $0, points: [rect.origin, NSPoint(x: rect.midX, y: rect.midY)], color: .red, width: 4, text: "测试 Simple")
            }
            let composite = AnnotationRenderer.render(base: first.image, canvas: size, annotations: annotations)
            let crop = composite.flatMap { $0.cropping(to: CaptureGeometry.pixelRect(rect, canvas: size, image: $0)) }
            let png = crop.flatMap { NSBitmapImageRep(cgImage: $0).representation(using: .png, properties: [:]) }
            let tiff = crop.flatMap { NSBitmapImageRep(cgImage: $0).tiffRepresentation }
            result["success"] = png != nil && tiff != nil
            result["capturedScreens"] = captures.count
            result["pngBytes"] = png?.count ?? 0
            result["cropPixels"] = crop.map { [$0.width, $0.height] } ?? []
        } else { result["success"] = false; result["capturedScreens"] = captures?.count ?? 0 }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), let string = String(data: data, encoding: .utf8) { print(string) }
    }
}

@MainActor private final class CaptureProbe {
    weak var window: NSWindow?
    weak var canvas: CaptureCanvas?
    weak var image: CGImage?
    init(window: NSWindow, canvas: CaptureCanvas) {
        self.window = window; self.canvas = canvas; self.image = canvas.baseImage
    }
}
