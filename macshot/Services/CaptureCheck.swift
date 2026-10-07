// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

/// Optional local diagnostic. Does not save screen pixels or change the clipboard.
enum CaptureCheck {
    static func run() async {
        let context = ScreenCaptureManager.makeImmediateCaptureContext()
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
