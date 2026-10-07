import Cocoa
import XCTest

final class ScrollStitcherTests: XCTestCase {
    // Unique textured rows, directly stored in top-to-bottom RGBA order.
    private func frame(offset: Int, header: Int = 0, footer: Int = 0, height: Int = 180, repeated: Bool = false) -> CGImage {
        let w = 96
        var data = Data(count:w*height*4)
        data.withUnsafeMutableBytes { (p: UnsafeMutableRawBufferPointer) in
            for y in 0..<height { for x in 0..<w {
                let row = y < header ? y : y >= height-footer ? 3000+y : y+offset
                let yy = repeated ? row%12 : row
                let seed = UInt32(truncatingIfNeeded: yy*92821+x*68917)
                let hash = (seed ^ (seed >> 13)) &* 1274126177
                let i = (y*w+x)*4
                p[i]=UInt8(truncatingIfNeeded:hash);p[i+1]=UInt8(truncatingIfNeeded:hash>>8)
                p[i+2]=UInt8(truncatingIfNeeded:hash>>16);p[i+3]=255
            } }
        }
        return CGImage(width:w,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,
                       space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
                       provider:CGDataProvider(data:data as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
    }
    private func color(_ image: CGImage, _ y: Int) -> [UInt8] {
        let f = ScrollStitcher.frame(image)!, i = f.offset(x:40,y:y)!
        return [f.bytes[i+f.redOffset],f.bytes[i+f.greenOffset],f.bytes[i+f.blueOffset]]
    }
    private func article() -> CGImage {
        let ctx = CGContext(data:nil,width:800,height:1800,bitsPerComponent:8,bytesPerRow:3200,
                            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(NSColor.white.cgColor);ctx.fill(CGRect(x:0,y:0,width:800,height:1800))
        NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=NSGraphicsContext(cgContext:ctx,flipped:false)
        for row in 0..<40 {
            let text="第 \(row) 段：截图工具应当识别真实文字与留白。Item \(row * 173)"
            (text as NSString).draw(at:NSPoint(x:90,y:1760-CGFloat(row)*42),withAttributes:[.font:NSFont.systemFont(ofSize:16),.foregroundColor:NSColor.black])
        }
        NSGraphicsContext.restoreGraphicsState();return ctx.makeImage()!
    }
    func testTextArticleWithWhitespaceMatches() {
        let page=article(),a=page.cropping(to:CGRect(x:0,y:0,width:800,height:600))!,b=page.cropping(to:CGRect(x:0,y:137,width:800,height:600))!
        var s=ScrollStitcher(a)
        XCTAssertFalse(ScrollStitcher.stable(a,b))
        XCTAssertEqual(s.append(b),.appended(137))
    }
    func testContinuousTextArticleKeepsLastRows() async {
        let page = article(), worker = ScrollProcessing()
        for offset in stride(from:0,through:600,by:30) {
            let viewport = page.cropping(to:CGRect(x:0,y:offset,width:800,height:600))!
            let result = await worker.consume(viewport)
            XCTAssertEqual(result,.appended(offset == 0 ? 0 : 30))
        }
        let output = await worker.output()
        XCTAssertEqual(output?.height,1200)
        let expected = page.cropping(to:CGRect(x:0,y:0,width:800,height:1200))!
        XCTAssertTrue(ScrollStitcher.frame(output!)!.bytes == ScrollStitcher.frame(expected)!.bytes,
                      "Continuous text output must preserve every source pixel")
    }
    func testTransientMismatchDoesNotWarnAndRecoveryResetsWarning() {
        var feedback = ScrollOverlapFeedback()
        XCTAssertFalse(feedback.update(.unmatched,at:10))
        XCTAssertFalse(feedback.update(.unmatched,at:10.3))
        XCTAssertTrue(feedback.shouldWarn(at:10.9)) // Even if no new frame arrives.
        XCTAssertTrue(feedback.update(.unmatched,at:10.9))
        XCTAssertFalse(feedback.update(.appended(1),at:11))
        XCTAssertFalse(feedback.update(.unmatched,at:11.1))
        XCTAssertFalse(feedback.update(.unchanged,at:11.5))
        XCTAssertFalse(feedback.update(.unmatched,at:12))
    }
    func testOnePixelScrollDoesNotLoseOverlap() {
        var stitcher = ScrollStitcher(frame(offset:0))
        XCTAssertEqual(stitcher.append(frame(offset:1)),.appended(1))
    }
    func testSmallChangingOverlayDoesNotBreakRealOverlap() {
        let next = frame(offset:60), normalized = ScrollStitcher.frame(next)!
        var bytes = Data(bytes:normalized.bytes,count:CFDataGetLength(normalized.data))
        bytes.withUnsafeMutableBytes { (p:UnsafeMutableRawBufferPointer) in
            for y in 65..<85 { for x in 20..<60 {
                let i=y*normalized.bytesPerRow+x*4
                p[i]=255-p[i];p[i+1]=255-p[i+1];p[i+2]=255-p[i+2]
            } }
        }
        let modified = CGImage(width:next.width,height:next.height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:normalized.bytesPerRow,
            space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.premultipliedLast.rawValue),
            provider:CGDataProvider(data:bytes as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        var stitcher = ScrollStitcher(frame(offset:0))
        XCTAssertEqual(stitcher.append(modified),.appended(60))
    }
    func testExactStitchAndLastRows() {
        let first = frame(offset:0), next = frame(offset:60)
        var stitcher = ScrollStitcher(first)
        XCTAssertEqual(stitcher.append(next),.appended(60))
        XCTAssertEqual(stitcher.image.height,240)
        for y in [0,119,179] { XCTAssertEqual(color(stitcher.image,y),color(first,y)) }
        for y in [180,199,239] { XCTAssertEqual(color(stitcher.image,y),color(next,y-60)) }
        XCTAssertEqual(stitcher.append(frame(offset:120)),.appended(60))
        XCTAssertEqual(stitcher.image.height,300)
    }
    func testNoMovementUpwardNoOverlapAndSizeChangeDoNotAdvance() {
        var s = ScrollStitcher(frame(offset:60))
        XCTAssertEqual(s.append(frame(offset:60)),.unchanged)
        XCTAssertEqual(s.append(frame(offset:0)),.unmatched)
        XCTAssertEqual(s.append(frame(offset:800)),.unmatched)
        XCTAssertEqual(s.append(frame(offset:80,height:200)),.invalid)
        XCTAssertEqual(s.image.height,180)
        XCTAssertEqual(s.append(frame(offset:120)),.appended(60))
    }
    func testRepeatingPatternsAreRejected() {
        var s = ScrollStitcher(frame(offset:0,repeated:true))
        XCTAssertEqual(s.append(frame(offset:7,repeated:true)),.unmatched)
        XCTAssertEqual(s.image.height,180)
    }
    func testPinnedHeaderAndFooterAppearOnce() {
        let a=frame(offset:0,header:20,footer:16),b=frame(offset:50,header:20,footer:16)
        var s=ScrollStitcher(a)
        XCTAssertEqual(s.append(b),.appended(50))
        XCTAssertEqual(s.image.height,230)
        XCTAssertEqual(color(s.image,10),color(a,10))
        XCTAssertEqual(color(s.image,165),color(b,115))
        XCTAssertEqual(color(s.image,200),color(b,150))
        XCTAssertEqual(color(s.image,220),color(b,170))
    }
    func testContinuousFrameProcessingAndRecovery() async {
        let worker = ScrollProcessing()
        let first = await worker.consume(frame(offset:0))
        XCTAssertEqual(first,.appended(0))
        // Every viewport moves: no identical pair and no stop between frames.
        for offset in stride(from:15,through:300,by:15) {
            let result = await worker.consume(frame(offset:offset))
            XCTAssertEqual(result,.appended(15))
        }
        let rejected = await worker.consume(frame(offset:1200))
        XCTAssertEqual(rejected,.unmatched)
        let resumed = await worker.consume(frame(offset:330))
        XCTAssertEqual(resumed,.appended(30))
        let output = await worker.output()
        XCTAssertEqual(output?.height,510)
        XCTAssertEqual(color(output!,509),color(frame(offset:330),179))
    }
    func testBoundedBufferPreservesBridgeFramesAndNewestFrame() {
        var buffer = ScrollFrameBuffer(capacity:3)
        for offset in [0,30,60,90,120] { buffer.push(frame(offset:offset)) }
        XCTAssertEqual(buffer.frames.count,3)
        var stitcher = ScrollStitcher(buffer.pop()!)
        XCTAssertEqual(stitcher.append(buffer.pop()!),.appended(30))
        XCTAssertEqual(stitcher.append(buffer.pop()!),.appended(90))
        XCTAssertNil(buffer.pop())
        XCTAssertEqual(stitcher.image.height,300)
        buffer.push(frame(offset:150));buffer.clear();XCTAssertNil(buffer.pop())
    }
    func testFirstViewportMustFitLimitsWithoutOverflow() async {
        XCTAssertFalse(ScrollStitcher.fitsLimits(width:Int.max,height:2))
        XCTAssertFalse(ScrollStitcher.fitsLimits(width:10_000,height:5_000))
        XCTAssertFalse(ScrollStitcher.fitsLimits(width:0,height:100))
        XCTAssertTrue(ScrollStitcher.fitsLimits(width:2000,height:20_000))
        let worker = ScrollProcessing()
        let invalid = await worker.consume(Fixture.image(width:16,height:32))
        XCTAssertEqual(invalid,.invalid)
        let output = await worker.output();XCTAssertNil(output)
    }
    func testLimitsKeepLastValidImage() {
        var height=ScrollStitcher(frame(offset:0),maxHeight:200)
        XCTAssertEqual(height.append(frame(offset:50)),.limit)
        XCTAssertEqual(height.image.height,180)
        var pixels=ScrollStitcher(frame(offset:0),maxPixels:96*200)
        XCTAssertEqual(pixels.append(frame(offset:50)),.limit)
        XCTAssertEqual(pixels.image.height,180)
    }
}

@MainActor final class LongCaptureUITests: XCTestCase {
    func testCompletionIsDeliveredOnceAndCancelCannotReopenReview() throws {
        guard #available(macOS 14.0,*),let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let session = ScrollCaptureSession(screen:screen,selection:NSRect(x:100,y:150,width:300,height:200))
        var delivered = 0
        session.onFinish = { _,_ in delivered += 1 }
        session.complete(Fixture.image(width:96,height:180))
        session.complete(Fixture.image(width:96,height:180))
        session.cancel()
        XCTAssertEqual(delivered,1)
        let cancelled = ScrollCaptureSession(screen:screen,selection:NSRect(x:100,y:150,width:300,height:200))
        var images = 0, cancellations = 0
        cancelled.onFinish = { image,_ in if image == nil { cancellations += 1 } else { images += 1 } }
        cancelled.cancel();cancelled.complete(Fixture.image(width:96,height:180))
        XCTAssertEqual(cancellations,1);XCTAssertEqual(images,0)
    }
    func testHUDRemainsOutsideCaptureRegion() throws {
        guard #available(macOS 14.0,*), let screen = NSScreen.main else { throw XCTSkip("Requires a screen") }
        let selection=NSRect(x:100,y:150,width:500,height:400)
        let hud=try XCTUnwrap(ScrollCaptureSession.hudFrame(screen:screen,selection:selection))
        XCTAssertFalse(hud.intersects(selection.offsetBy(dx:screen.frame.minX,dy:screen.frame.minY)))
        XCTAssertTrue(screen.visibleFrame.contains(hud))
        XCTAssertNil(ScrollCaptureSession.hudFrame(screen:screen,selection:NSRect(origin:.zero,size:screen.frame.size)))
    }
    func testEntryAndAnnotationGuard() {
        let c=CaptureCanvas(frame:NSRect(x:0,y:0,width:400,height:300),image:Fixture.image(width:800,height:600),windowRects:[])
        c.select(NSRect(x:10,y:10,width:300,height:200))
        var received:NSRect?
        c.onScroll={received=$0};c.perform(.scroll)
        XCTAssertEqual(received,c.selection)
        let button=c.toolbar.buttons.first {$0.toolTip?.hasPrefix("长截图") == true}
        XCTAssertTrue(button?.isEnabled == true)
        c.perform(.tool(.rectangle))
        c.mouseDown(with:Fixture.event(.leftMouseDown,x:50,y:50));c.mouseDragged(with:Fixture.event(.leftMouseDragged,x:100,y:100));c.mouseUp(with:Fixture.event(.leftMouseUp,x:100,y:100))
        XCTAssertFalse(c.toolbar.buttons.first {$0.toolTip?.hasPrefix("长截图") == true}!.isEnabled)
        received=nil;c.perform(.scroll);XCTAssertNil(received)
    }
    func testLongReviewPreservesPixelsAndDisablesNewCapture() throws {
        let review=LongCaptureReview(image:Fixture.image(width:800,height:3200))
        let image=try XCTUnwrap(review.canvas.outputImage())
        XCTAssertEqual(image.width,800);XCTAssertEqual(image.height,3200)
        XCTAssertFalse(review.canvas.toolbar.buttons.first {$0.toolTip?.hasPrefix("长截图") == true}!.isEnabled)
        XCTAssertTrue(review.canvas.toolbar.superview !== review.canvas)
        review.close()
    }
}
