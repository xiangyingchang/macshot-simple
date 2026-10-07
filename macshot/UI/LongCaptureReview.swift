// MacShot Simple, GPL-3.0. Reuses the capture canvas and annotation toolbar.
import Cocoa

@MainActor final class LongCaptureReview: NSWindowController, NSWindowDelegate {
    let canvas: CaptureCanvas
    var onClose: (() -> Void)?
    init(image: CGImage) {
        let available = NSScreen.main?.visibleFrame.size ?? NSSize(width:1000,height:800)
        let size = NSSize(width:min(940,available.width-40),height:min(760,available.height-40))
        let window = NSWindow(contentRect:NSRect(origin:.zero,size:size),
                              styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "长截图"; window.isReleasedWhenClosed = false
        let width = size.width-24
        canvas = CaptureCanvas(frame:NSRect(x:0,y:0,width:width,height:width*CGFloat(image.height)/CGFloat(image.width)),image:image,windowRects:[])
        canvas.locksSelection = true
        super.init(window:window); window.delegate = self
        let root = NSView(frame:NSRect(origin:.zero,size:size))
        root.wantsLayer = true; root.layer?.backgroundColor = DesignTheme.paper.cgColor
        window.contentView = root
        let scroll = NSScrollView(frame:NSRect(x:12,y:104,width:width,height:size.height-116))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = true
        scroll.backgroundColor = DesignTheme.paper; scroll.documentView = canvas
        root.addSubview(scroll)
        canvas.onToolbarLayout = { [weak self, weak root] in
            guard let self, let root else { return }
            let toolbar = self.canvas.toolbar
            toolbar.optionsAbove = true
            toolbar.frame.origin = NSPoint(x:(root.bounds.width-toolbar.frame.width)/2,y:10)
        }
        canvas.select(canvas.bounds)
        canvas.toolbar.removeFromSuperview(); root.addSubview(canvas.toolbar)
        canvas.updateToolbar()
        scroll.contentView.scroll(to:NSPoint(x:0,y:max(0,canvas.bounds.height-scroll.contentSize.height)))
        scroll.reflectScrolledClipView(scroll.contentView)
        window.center(); window.makeFirstResponder(canvas)
    }
    required init?(coder:NSCoder) { fatalError() }
    func windowWillClose(_ notification:Notification) { onClose?() }
}
