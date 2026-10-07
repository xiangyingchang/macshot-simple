// MacShot Simple, GPL-3.0. No event injection or accessibility permission.
import Cocoa
import ScreenCaptureKit

actor ScrollProcessing {
    private var stitcher: ScrollStitcher?
    func consume(_ image: CGImage) -> ScrollStitcher.Result {
        if stitcher == nil {
            guard image.width >= 32, image.height >= 64 else { return .invalid }
            guard ScrollStitcher.fitsLimits(width:image.width,height:image.height) else { return .limit }
            stitcher = ScrollStitcher(image); return .appended(0)
        }
        return stitcher!.append(image)
    }
    func output() -> CGImage? { stitcher?.image }
}

/// Surface persistent loss of overlap, not a single transitional frame.
struct ScrollOverlapFeedback {
    private var missingSince:TimeInterval?
    mutating func update(_ result:ScrollStitcher.Result,at time:TimeInterval) -> Bool {
        guard result == .unmatched else { missingSince = nil; return false }
        if missingSince == nil { missingSince = time }
        return shouldWarn(at:time)
    }
    func shouldWarn(at time:TimeInterval) -> Bool {
        missingSince.map { time-$0 >= 0.8 } ?? false
    }
}

@available(macOS 14.0, *)
@MainActor final class ScrollCaptureSession {
    var onFinish: ((CGImage?, String?) -> Void)?
    private var resultNote: String?
    private var overlapFeedback = ScrollOverlapFeedback()
    private let screen: NSScreen
    private let selection: NSRect
    private let worker = ScrollProcessing()
    private var task: Task<Void,Never>?
    private var finishing = false
    private var cancelled = false
    private var finalizing = false
    private var frames = ScrollFrameBuffer()
    private var processingTask: Task<Void,Never>?
    private var liveStream: ScrollFrameStream?
    private var streamTask: Task<Void,Never>?
    private var lastLiveFrame = Date.distantPast
    private var lastLiveImage: CGImage?
    private var acceptingLiveFrames = true
    private var filter: SCContentFilter?
    private var useCompatibleCapture = false
    private let outline: NSPanel
    private let panel: NSPanel
    private let status: NSTextField
    private let done: ActionButton
    private var count = 0

    init(screen: NSScreen, selection: NSRect) {
        self.screen = screen; self.selection = selection
        outline = NSPanel(contentRect:selection.offsetBy(dx:screen.frame.minX,dy:screen.frame.minY).insetBy(dx:-4,dy:-4),
                          styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        outline.isOpaque = false; outline.backgroundColor = .clear; outline.hasShadow = false
        outline.ignoresMouseEvents = true; outline.level = .screenSaver
        outline.hidesOnDeactivate = false; outline.isReleasedWhenClosed = false
        outline.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        outline.contentView = ScrollCaptureOutline(frame:NSRect(origin:.zero,size:outline.frame.size))
        let frame = screen.visibleFrame
        panel = NSPanel(contentRect:Self.hudFrame(screen:screen,selection:selection) ?? NSRect(x:frame.midX-220,y:frame.maxY-65,width:440,height:48),
                        styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.level = .screenSaver; panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false; panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary]
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        let row = ToolbarRow(frame:NSRect(x:0,y:0,width:440,height:48)); panel.contentView = row
        status = NSTextField(labelWithString:"准备长截图…")
        status.font = .systemFont(ofSize:12); status.textColor = DesignTheme.ink
        status.frame = NSRect(x:14,y:15,width:285,height:18); row.addSubview(status)
        let cancel = ActionButton(frame:NSRect(x:304,y:7,width:55,height:34))
        cancel.title = "取消"; cancel.tint = DesignTheme.red; row.addSubview(cancel)
        done = ActionButton(frame:NSRect(x:363,y:7,width:65,height:34))
        done.title = "完成"; done.tint = DesignTheme.green; done.isEnabled = false; row.addSubview(done)
        cancel.callback = { [weak self] in self?.cancel() }
        done.callback = { [weak self] in self?.finish() }
    }

    static func hudFrame(screen:NSScreen, selection:NSRect) -> NSRect? {
        let bounds = screen.visibleFrame
        let selected = selection.offsetBy(dx:screen.frame.minX,dy:screen.frame.minY)
        let x = max(bounds.minX,min(bounds.maxX-440,selected.midX-220))
        let candidates = [NSRect(x:x,y:selected.maxY+8,width:440,height:48),
                          NSRect(x:x,y:selected.minY-56,width:440,height:48),
                          NSRect(x:bounds.midX-220,y:bounds.maxY-56,width:440,height:48),
                          NSRect(x:bounds.midX-220,y:bounds.minY+8,width:440,height:48)]
        return candidates.first { bounds.contains($0) && !$0.intersects(selected.insetBy(dx:-4,dy:-4)) }
    }

    func start() {
        outline.orderFrontRegardless(); panel.orderFrontRegardless()
        task = Task { [weak self] in
            guard let self else { return }
            do {
                if #unavailable(macOS 26.0) {
                    do {
                        let content = try await SCShareableContent.excludingDesktopWindows(false,onScreenWindowsOnly:true)
                        let id = self.screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
                        guard let display = content.displays.first(where:{$0.displayID == id}) else { throw CocoaError(.fileReadUnknown) }
                        let own = content.applications.filter {$0.processID == ProcessInfo.processInfo.processIdentifier}
                        self.filter = SCContentFilter(display:display,excludingApplications:own,exceptingWindows:[])
                    } catch {
                        guard CGPreflightScreenCaptureAccess() else { throw error }
                        self.useCompatibleCapture = true
                    }
                }
                // Wait for the frozen screenshot windows to disappear and focus to return.
                try await Task.sleep(nanoseconds:250_000_000)
                guard !Task.isCancelled, !self.cancelled else { return }
                let source = ScrollFrameStream()
                self.streamTask = Task { [weak self] in
                    for await event in source.events {
                        guard let self, self.acceptingLiveFrames, !self.cancelled else { break }
                        self.lastLiveFrame = Date()
                        switch event {
                        case .frame(let image): self.lastLiveImage = image; self.enqueue(image)
                        case .idle: break
                        case .failed: self.lastLiveFrame = .distantPast
                        }
                    }
                }
                self.liveStream = source
                do {
                    try await source.start(screen:self.screen,selection:self.selection)
                    guard !Task.isCancelled, !self.cancelled else { await source.stop(); return }
                    self.lastLiveFrame = Date()
                } catch {
                    self.acceptingLiveFrames = false
                    await source.stop(); self.liveStream = nil
                }
                while !Task.isCancelled && !self.finishing {
                    // Idle stream frames do not enter the matcher. Still surface
                    // a persistent gap even when the page has stopped changing.
                    if self.overlapFeedback.shouldWarn(at:ProcessInfo.processInfo.systemUptime), self.resultNote == "最后一段未拼接" {
                        self.status.stringValue = "未找到重叠 · 向上回退一些再继续"
                    }
                    if self.liveStream == nil || Date().timeIntervalSince(self.lastLiveFrame) > 0.5 {
                        // Stream unavailable or starved: retain the proven still path.
                        self.acceptingLiveFrames = false
                        await self.liveStream?.stop(); self.liveStream = nil
                        let image = try await self.capture()
                        guard !Task.isCancelled, !self.finishing else { break }
                        self.enqueue(image)
                    }
                    try await Task.sleep(nanoseconds:60_000_000)
                }
            } catch {
                if !Task.isCancelled && !self.finishing { self.fail("捕获失败（\((error as NSError).domain):\((error as NSError).code)）· 请取消后重试") }
            }
        }
    }

    private func enqueue(_ image:CGImage) {
        guard !finishing, !cancelled else { return }
        frames.push(image)
        guard processingTask == nil else { return }
        processingTask = Task { [weak self] in
            guard let self else { return }
            while !self.cancelled, let frame = self.frames.pop() {
                let result = await self.worker.consume(frame)
                guard !self.cancelled else { break }
                self.update(result)
                if result == .limit || result == .invalid { self.frames.clear(); break }
            }
            self.processingTask = nil
        }
    }

    private func capture() async throws -> CGImage {
        do { return try await captureModern() }
        catch {
            // Same permission-gated WindowServer path used by normal capture and
            // upstream scrolling capture. Do not fall back to a desktop-only image.
            guard !Task.isCancelled, CGPreflightScreenCaptureAccess() else { throw error }
            let global = selection.offsetBy(dx:screen.frame.minX,dy:screen.frame.minY)
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let rect = CGRect(x:global.minX,y:primaryHeight-global.maxY,width:global.width,height:global.height)
            guard let image = CGWindowListCreateImage(rect,.optionOnScreenBelowWindow,
                CGWindowID(outline.windowNumber),[.bestResolution,.boundsIgnoreFraming]) else { throw error }
            useCompatibleCapture = true
            return image
        }
    }

    private func captureModern() async throws -> CGImage {
        if useCompatibleCapture { throw CocoaError(.featureUnsupported) }
        let scale = screen.backingScaleFactor
        if #available(macOS 26.0, *) {
            // The rect API also works when SCShareableContent returns no displays.
            // Keep the HUD and outline outside the selected rectangle.
            let primaryHeight = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
            let global = selection.offsetBy(dx:screen.frame.minX,dy:screen.frame.minY)
            let rect = CGRect(x:global.minX,y:primaryHeight-global.maxY,width:global.width,height:global.height)
            let config = SCScreenshotConfiguration()
            config.width = Int(selection.width*scale); config.height = Int(selection.height*scale)
            config.showsCursor = false; config.ignoreShadows = false
            config.displayIntent = .local; config.dynamicRange = .sdr
            return try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureScreenshot(rect:rect,configuration:config) { output, error in
                    if let error { continuation.resume(throwing:error) }
                    else if let image = output?.sdrImage { continuation.resume(returning:image) }
                    else { continuation.resume(throwing:CocoaError(.fileReadUnknown)) }
                }
            }
        }
        guard let filter else { throw CocoaError(.fileReadUnknown) }
        let config = SCStreamConfiguration()
        config.width = Int(screen.frame.width*scale); config.height = Int(screen.frame.height*scale)
        config.showsCursor = false; config.captureResolution = .best
        let image = try await SCScreenshotManager.captureImage(contentFilter:filter,configuration:config)
        let pixels = CaptureGeometry.pixelRect(selection,canvas:screen.frame.size,image:image)
        guard let crop = image.cropping(to:pixels) else { throw CocoaError(.fileReadUnknown) }
        return crop
    }

    private func update(_ result: ScrollStitcher.Result) {
        let warn = overlapFeedback.update(result,at:ProcessInfo.processInfo.systemUptime)
        switch result {
        case .appended:
            resultNote = nil
            count += 1; if !finalizing { done.isEnabled = true }
            status.stringValue = count == 1 ? "向下滚动 · 完成后点完成" : "已拼接 \(count) 段 · 继续向下滚动"
        case .unmatched:
            resultNote = "最后一段未拼接"
            status.stringValue = warn ? "未找到重叠 · 向上回退一些再继续" : "正在匹配滚动内容…"
        case .limit:
            resultNote = "已到长度上限"
            status.stringValue = count == 0 ? "选区过大 · 请取消后缩小选区" : "已到长度上限 · 请点完成"
            finishing = true
        case .invalid: fail("页面尺寸已变化 · 请完成或取消")
        case .unchanged:
            if resultNote == "最后一段未拼接" {
                resultNote = nil; status.stringValue = "已恢复匹配 · 继续向下滚动"
            }
        }
    }
    private func fail(_ message: String) { status.stringValue = message; resultNote = message; finishing = true }

    func finish() {
        guard done.isEnabled, !finalizing, !cancelled else { return }
        finalizing = true; done.isEnabled = false; finishing = true
        Task { [weak self] in
            guard let self else { return }
            await self.task?.value
            let wasStreaming = self.liveStream != nil
            if wasStreaming { try? await Task.sleep(nanoseconds:150_000_000) }
            self.acceptingLiveFrames = false
            await self.liveStream?.stop(); self.liveStream = nil
            await self.processingTask?.value
            guard !self.cancelled else { return }
            if wasStreaming, let final = self.lastLiveImage {
                // Keep one capture/color pipeline from first through last frame.
                self.applyFinal(await self.worker.consume(final))
            } else {
                var previous: CGImage?, accepted = false
                for _ in 0..<5 {
                    guard !self.cancelled else { break }
                    let image:CGImage
                    do { image = try await self.capture() }
                    catch { self.resultNote = "最后一帧捕获失败，已保留已截内容"; accepted = true; break }
                    if let previous, ScrollStitcher.stable(previous,image) {
                        self.applyFinal(await self.worker.consume(image))
                        accepted = true; break
                    }
                    previous = image
                    try? await Task.sleep(nanoseconds:150_000_000)
                }
                if !accepted { self.resultNote = "最后画面仍在移动，已保留已截内容" }
            }
            let image = await self.worker.output()
            self.complete(image)
        }
    }
    func complete(_ image:CGImage?) {
        guard !cancelled, let callback = onFinish else { return }
        onFinish = nil
        panel.orderOut(nil); outline.orderOut(nil)
        callback(image,resultNote)
    }
    private func applyFinal(_ result:ScrollStitcher.Result) {
        if case .appended = result { resultNote = nil }
        if result == .unchanged, resultNote == "最后一段未拼接" { resultNote = nil }
        if result == .unmatched { resultNote = "最后一段未拼接" }
        if result == .limit { resultNote = "已到长度上限" }
        if result == .invalid { resultNote = "页面尺寸已变化" }
    }
    func cancel() {
        cancelled = true; finishing = true; task?.cancel(); streamTask?.cancel(); frames.clear()
        let source = liveStream; liveStream = nil
        Task { await source?.stop() }
        panel.orderOut(nil); outline.orderOut(nil)
        let callback = onFinish; onFinish = nil; callback?(nil, nil)
    }
}

private final class ScrollCaptureOutline: NSView {
    override func draw(_ dirtyRect: NSRect) {
        DesignTheme.green.setStroke()
        let path = NSBezierPath(rect:bounds.insetBy(dx:1,dy:1))
        path.lineWidth = 2; path.stroke()
    }
}
