// MacShot Simple, GPL-3.0. Bounded native live capture; no recording or persistence.
import Cocoa
import ScreenCaptureKit
import CoreImage
import CoreMedia

@available(macOS 14.0, *)
final class ScrollFrameStream: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    private let context = CIContext(options:[.cacheIntermediates:false])
    enum Event: @unchecked Sendable { case frame(CGImage), idle, failed }
    let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let queue = DispatchQueue(label:"local.macshot.simple.scroll-frames",qos:.userInitiated)
    @MainActor private var stream: SCStream?

    override init() {
        // Bound frames before delivery to the main actor as well as after it.
        let channel = AsyncStream<Event>.makeStream(bufferingPolicy:.bufferingNewest(8))
        events = channel.stream; continuation = channel.continuation
        super.init()
    }

    @MainActor func start(screen:NSScreen, selection:NSRect) async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
        let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
        guard let display = content.displays.first(where:{$0.displayID == id}) else { throw CocoaError(.fileReadUnknown) }
        let own = content.applications.filter {$0.processID == ProcessInfo.processInfo.processIdentifier}
        let filter = SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
        let config = SCStreamConfiguration()
        config.sourceRect = CGRect(x:selection.minX,y:screen.frame.height-selection.maxY,width:selection.width,height:selection.height)
        config.width = Int(selection.width*screen.backingScaleFactor)
        config.height = Int(selection.height*screen.backingScaleFactor)
        config.showsCursor = false; config.capturesAudio = false
        config.captureResolution = .best
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value:1,timescale:15)
        config.queueDepth = 3
        config.colorSpaceName = CGColorSpace.sRGB
        let stream = SCStream(filter:filter,configuration:config,delegate:self)
        try stream.addStreamOutput(self,type:.screen,sampleHandlerQueue:queue)
        self.stream = stream
        try await stream.startCapture()
    }

    @MainActor func stop() async {
        let active = stream; stream = nil
        continuation.finish()
        try? await active?.stopCapture()
    }

    func stream(_ stream:SCStream, didOutputSampleBuffer buffer:CMSampleBuffer, of type:SCStreamOutputType) {
        guard type == .screen, buffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer,createIfNecessary:false) as? [[SCStreamFrameInfo:Any]],
              let raw = attachments.first?[.status] as? Int else { return }
        if SCFrameStatus(rawValue:raw) == .idle { continuation.yield(.idle); return }
        guard SCFrameStatus(rawValue:raw) == .complete, let pixels = buffer.imageBuffer else { return }
        let image = CIImage(cvPixelBuffer:pixels)
        if let frame = context.createCGImage(image,from:image.extent) { continuation.yield(.frame(frame)) }
    }
    func stream(_ stream:SCStream,didStopWithError error:Error) { continuation.yield(.failed) }
}

/// Keep early bridge frames when processing lags, and replace only the newest
/// pending frame. Memory stays bounded without immediately discarding overlaps.
struct ScrollFrameBuffer {
    private(set) var frames:[CGImage] = []
    let capacity:Int
    init(capacity:Int = 8) { precondition(capacity > 0); self.capacity = capacity }
    mutating func push(_ image:CGImage) {
        if frames.count == capacity { frames[frames.count-1] = image }
        else { frames.append(image) }
    }
    mutating func pop() -> CGImage? { frames.isEmpty ? nil : frames.removeFirst() }
    mutating func clear() { frames.removeAll() }
}
