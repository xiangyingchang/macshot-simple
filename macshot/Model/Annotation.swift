// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

enum AnnotationTool: Int, CaseIterable {
    case rectangle, ellipse, arrow, pencil, pixelate, text
    var title: String { ["矩形", "椭圆", "箭头", "画笔", "马赛克", "文字"][rawValue] }
    var symbol: String { ["rectangle", "oval", "arrow.up.right", "pencil", "checkerboard.rectangle", "t.square"][rawValue] }
}

struct Annotation {
    var tool: AnnotationTool
    var points: [NSPoint]
    var color: NSColor
    var width: CGFloat
    var text = ""
    var fontSize: CGFloat = 18
    var textRect: NSRect?
    var rect: NSRect {
        guard let first = points.first, let last = points.last else { return .zero }
        return CaptureGeometry.rect(from: first, to: last)
    }
}

struct AnnotationHistory {
    private(set) var annotations: [Annotation] = []
    private(set) var undone: [Annotation] = []
    mutating func append(_ annotation: Annotation) { annotations.append(annotation); undone.removeAll() }
    mutating func undo() { if let last = annotations.popLast() { undone.append(last) } }
    mutating func redo() { if let last = undone.popLast() { annotations.append(last) } }
    mutating func clear() { annotations.removeAll(); undone.removeAll() }
}

/// Renders the same bitmap for the live canvas, PNG export and clipboard.
/// Mosaic reads already-rendered pixels, so it also conceals earlier annotations.
enum AnnotationRenderer {
    static func render(base: CGImage, canvas: NSSize, annotations: [Annotation]) -> CGImage? {
        guard canvas.width > 0, canvas.height > 0,
              let context = CGContext(data: nil, width: base.width, height: base.height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        context.scaleBy(x: CGFloat(base.width) / canvas.width, y: CGFloat(base.height) / canvas.height)
        for annotation in annotations { draw(annotation, in: context, canvas: canvas, pixelSize: NSSize(width: base.width, height: base.height)) }
        return context.makeImage()
    }

    private static func draw(_ annotation: Annotation, in context: CGContext, canvas: NSSize, pixelSize: NSSize) {
        guard let first = annotation.points.first, let last = annotation.points.last else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.setStrokeColor(annotation.color.cgColor)
        context.setFillColor(annotation.color.cgColor)
        context.setLineWidth(annotation.width)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        switch annotation.tool {
        case .rectangle: context.stroke(annotation.rect)
        case .ellipse: context.strokeEllipse(in: annotation.rect)
        case .pencil:
            context.beginPath(); context.move(to: first)
            for point in annotation.points.dropFirst() { context.addLine(to: point) }
            context.strokePath()
        case .arrow:
            context.move(to: first); context.addLine(to: last); context.strokePath()
            let angle = atan2(last.y - first.y, last.x - first.x)
            let length = max(10, annotation.width * 3)
            context.move(to: NSPoint(x: last.x - length * cos(angle - .pi / 6), y: last.y - length * sin(angle - .pi / 6)))
            context.addLine(to: last)
            context.addLine(to: NSPoint(x: last.x - length * cos(angle + .pi / 6), y: last.y - length * sin(angle + .pi / 6)))
            context.strokePath()
        case .text:
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: annotation.fontSize), .foregroundColor: annotation.color]
            if let rect = annotation.textRect {
                (annotation.text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: attributes)
            } else { (annotation.text as NSString).draw(at: first, withAttributes: attributes) }
            NSGraphicsContext.restoreGraphicsState()
        case .pixelate:
            guard annotation.rect.width >= 1, annotation.rect.height >= 1,
                  let composite = context.makeImage() else { return }
            let rect = CaptureGeometry.pixelRect(annotation.rect, canvas: canvas, image: composite)
            guard !rect.isEmpty, let crop = composite.cropping(to: rect) else { return }
            let target = NSRect(x: rect.minX * canvas.width / pixelSize.width,
                                y: canvas.height - rect.maxY * canvas.height / pixelSize.height,
                                width: rect.width * canvas.width / pixelSize.width,
                                height: rect.height * canvas.height / pixelSize.height)
            let cell = max(6, annotation.width * 2)
            let w = max(1, Int(target.width / cell)), h = max(1, Int(target.height / cell))
            guard let tiny = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
            tiny.interpolationQuality = .low
            tiny.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let blocks = tiny.makeImage() else { return }
            context.interpolationQuality = .none
            context.draw(blocks, in: target)
        }
    }
}
