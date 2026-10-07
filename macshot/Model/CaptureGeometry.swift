// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

enum CaptureGeometry {
    static func rect(from a: NSPoint, to b: NSPoint) -> NSRect {
        NSRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    static func clamp(_ point: NSPoint, to bounds: NSRect) -> NSPoint {
        NSPoint(x: min(bounds.maxX, max(bounds.minX, point.x)), y: min(bounds.maxY, max(bounds.minY, point.y)))
    }

    static func move(_ rect: NSRect, by delta: NSPoint, in bounds: NSRect) -> NSRect {
        NSRect(x: min(bounds.maxX - rect.width, max(bounds.minX, rect.minX + delta.x)),
               y: min(bounds.maxY - rect.height, max(bounds.minY, rect.minY + delta.y)),
               width: rect.width, height: rect.height)
    }

    static func handles(for rect: NSRect) -> [NSPoint] {
        [NSPoint(x: rect.minX, y: rect.minY), NSPoint(x: rect.midX, y: rect.minY),
         NSPoint(x: rect.maxX, y: rect.minY), NSPoint(x: rect.minX, y: rect.midY),
         NSPoint(x: rect.maxX, y: rect.midY), NSPoint(x: rect.minX, y: rect.maxY),
         NSPoint(x: rect.midX, y: rect.maxY), NSPoint(x: rect.maxX, y: rect.maxY)]
    }

    static func resize(_ rect: NSRect, handle: Int, to point: NSPoint, in bounds: NSRect) -> NSRect {
        let p = clamp(point, to: bounds)
        var lo = rect.origin, hi = NSPoint(x: rect.maxX, y: rect.maxY)
        if [0, 3, 5].contains(handle) { lo.x = min(p.x, hi.x - 2) }
        if [2, 4, 7].contains(handle) { hi.x = max(p.x, lo.x + 2) }
        if [0, 1, 2].contains(handle) { lo.y = min(p.y, hi.y - 2) }
        if [5, 6, 7].contains(handle) { hi.y = max(p.y, lo.y + 2) }
        return self.rect(from: lo, to: hi).intersection(bounds)
    }

    /// NSView uses bottom-left coordinates; CGImage crop uses top-left pixels.
    static func pixelRect(_ selection: NSRect, canvas: NSSize, image: CGImage) -> CGRect {
        let sx = CGFloat(image.width) / canvas.width, sy = CGFloat(image.height) / canvas.height
        let pixels = CGRect(x: selection.minX * sx, y: (canvas.height - selection.maxY) * sy,
                            width: selection.width * sx, height: selection.height * sy).integral
        return pixels.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
    }

    static func windowRect(_ cgRect: CGRect, primaryHeight: CGFloat, screenFrame: NSRect) -> NSRect {
        NSRect(x: cgRect.minX - screenFrame.minX,
               y: primaryHeight - cgRect.maxY - screenFrame.minY,
               width: cgRect.width, height: cgRect.height)
    }

    static func toolbarOrigin(selection: NSRect, size: NSSize, bounds: NSRect) -> NSPoint {
        toolbarPlacement(selection: selection, size: size, reservedHeight: size.height, bounds: bounds).origin
    }

    /// Reserve the options row before opening it, so the main buttons stay at
    /// the same screen position when a tool is chosen near the screen edge.
    static func toolbarPlacement(selection: NSRect, size: NSSize, reservedHeight: CGFloat, bounds: NSRect) -> (origin: NSPoint, optionsAbove: Bool) {
        let x = min(max(0, bounds.width - size.width - 8), max(8, selection.maxX - size.width))
        let above = selection.minY - reservedHeight - 10 < 8
        let y = above ? min(bounds.maxY - reservedHeight - 8, selection.maxY + 10) : selection.minY - size.height - 10
        return (NSPoint(x: x, y: max(0, y)), above)
    }
}
