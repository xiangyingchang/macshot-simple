import Cocoa
import XCTest

@MainActor
func withDefaults(_ values: [String: Any], _ body: () throws -> Void) rethrows {
    let defaults = UserDefaults.standard
    let previous = values.mapValues { _ in Optional<Any>.none }
    var saved = previous
    for key in values.keys { saved[key] = defaults.object(forKey: key) }
    for (key, value) in values { defaults.set(value, forKey: key) }
    defer {
        for key in values.keys {
            if let value = saved[key] ?? nil { defaults.set(value, forKey: key) }
            else { defaults.removeObject(forKey: key) }
        }
    }
    try body()
}

@MainActor
enum Fixture {
    static func image(width: Int = 200, height: Int = 100, stripes: Bool = false) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        if stripes {
            context.setFillColor(NSColor.black.cgColor)
            for x in stride(from: 0, to: width, by: 2) { context.fill(CGRect(x: x, y: 0, width: 1, height: height)) }
        }
        return context.makeImage()!
    }
    static func color(_ image: CGImage, x: Int, y: Int) -> NSColor {
        // Probe raw channels: colorAt uses a calibrated wrapper even for an sRGB bitmap.
        NSBitmapImageRep(cgImage: image).colorAt(x: x, y: y)!
    }
    static func event(_ type: NSEvent.EventType, x: CGFloat, y: CGFloat, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: y), modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }
}
