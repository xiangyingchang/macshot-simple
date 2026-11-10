import Cocoa
import XCTest

/// Controlled synthetic workload. Never captures or persists real screen pixels.
@MainActor
final class CaptureMemoryDiagnostics: XCTestCase {
    private func pixels() -> CGImage {
        let width = 3200, height = 1800
        // Nonuniform synthetic pixels avoid mistaking solid-color compression
        // for a meaningful screenshot-memory measurement.
        var words = [UInt32](repeating: 0, count: width * height)
        var seed: UInt32 = 7
        for index in words.indices {
            seed = seed &* 1664525 &+ 1013904223
            words[index] = seed | 0xff000000
        }
        let data = words.withUnsafeBytes { Data($0) } as CFData
        return CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                       bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                       bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider: CGDataProvider(data: data)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
    }
    private func rssMiB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.resident_size) / 1_048_576 : -1
    }

    func testSyntheticWindowLifecycleRSS() {
        _ = NSApplication.shared
        var windows: [CaptureWindow] = []
        var weakCanvases: [WeakCanvas] = []
        func sample(_ stage: String) {
            print(String(format: "MACSHOT_MEMORY stage=%@ rssMiB=%.2f liveCanvases=%d retainedWindows=%d", stage,
                         rssMiB(), weakCanvases.filter { $0.value != nil }.count, windows.count))
        }
        sample("baseline")
        for index in 1...5 {
            autoreleasepool {
                let rect = NSRect(x: 0, y: 0, width: 800, height: 450)
                let window = CaptureWindow(contentRect: rect, styleMask: .borderless, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                let view = CaptureCanvas(frame: rect, image: pixels(), windowRects: [])
                weakCanvases.append(WeakCanvas(view))
                window.contentView = view
                windows.append(window)
                window.orderFrontRegardless()
                window.displayIfNeeded()
            }
            sample("open-\(index)")
            autoreleasepool { windows.last?.close() }
            sample("closed-\(index)")
        }
        // Retaining NSWindow intentionally models AppKit retaining a closed key window.
        // The measured objects, unlike allocator RSS, must release deterministically.
        XCTAssertTrue(weakCanvases.allSatisfy { $0.value == nil })
        autoreleasepool { windows.removeAll() }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        sample("all-windows-dropped")
    }
}

@MainActor
private final class WeakCanvas {
    weak var value: CaptureCanvas?
    init(_ value: CaptureCanvas) { self.value = value }
}
