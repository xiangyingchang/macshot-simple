// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

final class CaptureCanvas: NSView, NSTextViewDelegate {
    private enum Gesture { case none, select(NSPoint), move(NSPoint, NSRect), resize(Int, NSRect), annotate }
    private var gesture: Gesture = .none
    let baseImage: CGImage
    var windowRects: [NSRect]
    private(set) var selection: NSRect?
    private(set) var preview: NSRect?
    private(set) var history = AnnotationHistory()
    private(set) var activeTool: AnnotationTool?
    private var pending: Annotation?
    private var renderedImage: CGImage?
    private var textView: NSTextView?
    let toolbar = CaptureToolbar(frame: .zero)
    var locksSelection = false
    var onToolbarLayout: (() -> Void)?
    var onScroll: ((NSRect) -> Void)?
    var onSelected: (() -> Void)?
    var onCancel: (() -> Void)?
    var onCopy: ((CGImage) -> Void)?
    var onSave: ((CGImage) -> Void)?
    var onFailure: (() -> Void)?
    private var tracking: NSTrackingArea?
    override var acceptsFirstResponder: Bool { true }

    init(frame: NSRect, image: CGImage, windowRects: [NSRect]) {
        self.baseImage = image
        self.windowRects = windowRects
        super.init(frame: frame)
        addSubview(toolbar)
        toolbar.isHidden = true
        toolbar.onAction = { [weak self] action in self?.perform(action) }
        toolbar.onWidth = { [weak self] width in
            guard let self, let tool = self.activeTool else { return }
            SimpleSettings.saveWidth(width, for: tool); self.updateToolbar()
        }
        toolbar.onColor = { [weak self] index in
            SimpleSettings.colorIndex = index
            self?.textView?.textColor = SimpleSettings.palette[index]
            self?.updateToolbar()
        }
        toolbar.onFontSize = { [weak self] size in
            SimpleSettings.fontSize = size
            self?.textView?.font = .systemFont(ofSize: SimpleSettings.fontSize)
            self?.updateToolbar()
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: activeTool == .text ? .iBeam : .crosshair)
        if let selection, activeTool == nil { addCursorRect(selection.insetBy(dx: 10, dy: 10), cursor: .openHand) }
        if !toolbar.isHidden { addCursorRect(toolbar.frame, cursor: .arrow) }
    }

    func refreshPreview(at point: NSPoint) {
        guard selection == nil else { return }
        guard bounds.contains(point) else { preview = nil; needsDisplay = true; return }
        preview = windowRects.first { $0.contains(point) }.map { $0.intersection(bounds) }
        needsDisplay = true
    }
    override func mouseMoved(with event: NSEvent) { refreshPreview(at: convert(event.locationInWindow, from: nil)) }

    func select(_ rect: NSRect) {
        let clipped = rect.intersection(bounds)
        guard !clipped.isEmpty, clipped.width >= 2, clipped.height >= 2 else { return }
        selection = clipped; preview = nil
        toolbar.isHidden = false
        updateToolbar(); needsDisplay = true
        onSelected?()
    }

    func resetSelection() {
        cancelText()
        selection = nil; preview = nil; activeTool = nil; pending = nil
        gesture = .none; history.clear(); renderedImage = nil
        toolbar.isHidden = true; needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = CaptureGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        commitText()
        window?.makeFirstResponder(self)
        if let selection {
            if event.clickCount == 2 && activeTool == nil && selection.contains(point) { perform(.copy); return }
            if !locksSelection, let index = CaptureGeometry.handles(for: selection).firstIndex(where: { abs($0.x - point.x) <= 8 && abs($0.y - point.y) <= 8 }) {
                gesture = .resize(index, selection); toolbar.isHidden = true; return
            }
            if selection.contains(point) {
                if let tool = activeTool {
                    if tool == .text { beginText(at: point) }
                    else {
                        pending = Annotation(tool: tool, points: [point, point], color: SimpleSettings.palette[SimpleSettings.colorIndex], width: SimpleSettings.strokeWidth(for: tool))
                        gesture = .annotate
                    }
                } else if !locksSelection { gesture = .move(point, selection); toolbar.isHidden = true }
                return
            }
            if locksSelection { return }
            resetSelection()
        }
        gesture = .select(point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = CaptureGeometry.clamp(convert(event.locationInWindow, from: nil), to: bounds)
        switch gesture {
        case .select(let origin): selection = CaptureGeometry.rect(from: origin, to: point); preview = nil
        case .move(let origin, let rect): selection = CaptureGeometry.move(rect, by: NSPoint(x: point.x - origin.x, y: point.y - origin.y), in: bounds)
        case .resize(let index, let rect): selection = CaptureGeometry.resize(rect, handle: index, to: point, in: bounds)
        case .annotate:
            guard let selection, var annotation = pending else { return }
            let clipped = CaptureGeometry.clamp(point, to: selection)
            if annotation.tool == .pencil { annotation.points.append(clipped) }
            else { annotation.points[annotation.points.count - 1] = clipped }
            pending = annotation; invalidateImage()
        case .none: break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch gesture {
        case .select:
            if let selection, selection.width >= 2, selection.height >= 2 { select(selection) }
            else {
                selection = nil
                if let preview { select(preview) }
                else { refreshPreview(at: convert(event.locationInWindow, from: nil)) }
            }
        case .annotate:
            if let pending, pending.tool == .pencil || pending.rect.width >= 1 || pending.rect.height >= 1 {
                history.append(pending)
            }
            pending = nil; invalidateImage(); updateToolbar()
        case .move, .resize: toolbar.isHidden = false; updateToolbar()
        case .none: break
        }
        gesture = .none
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        if locksSelection { return }
        if selection != nil {
            resetSelection(); refreshPreview(at: convert(event.locationInWindow, from: nil))
        } else { onCancel?() }
    }

    @objc func undo(_ sender: Any?) { perform(.undo) }
    @objc func redo(_ sender: Any?) { perform(.redo) }
    @objc func copy(_ sender: Any?) { perform(.copy) }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onCancel?(); return }
        if event.keyCode == 36 { perform(.copy); return }
        if KeyboardShortcutMatcher.matches(event, character: "z", modifiers: .command) { perform(.undo); return }
        if KeyboardShortcutMatcher.matches(event, character: "z", modifiers: [.command, .shift]) { perform(.redo); return }
        if KeyboardShortcutMatcher.matches(event, character: "c", modifiers: .command) { perform(.copy); return }
        if KeyboardShortcutMatcher.matches(event, character: "s", modifiers: .command) { perform(.save); return }
        super.keyDown(with: event)
    }

    func perform(_ action: ToolbarAction) {
        commitText()
        switch action {
        case .tool(let tool):
            activeTool = activeTool == tool ? nil : tool
            updateToolbar(); window?.invalidateCursorRects(for: self)
        case .undo: history.undo(); invalidateImage(); updateToolbar()
        case .redo: history.redo(); invalidateImage(); updateToolbar()
        case .cancel: onCancel?()
        case .copy:
            guard selection != nil else { return }
            guard let image = outputImage() else { onFailure?(); return }
            onCopy?(image)
        case .scroll:
            if !locksSelection, history.annotations.isEmpty, let selection { onScroll?(selection) }
        case .save:
            guard selection != nil else { return }
            guard let image = outputImage() else { onFailure?(); return }
            onSave?(image)
        }
        needsDisplay = true
    }

    func updateToolbar() {
        guard let selection else { return }
        toolbar.update(tool: activeTool, width: SimpleSettings.strokeWidth(for: activeTool ?? .rectangle), colorIndex: SimpleSettings.colorIndex,
                       fontSize: SimpleSettings.fontSize, canUndo: !history.annotations.isEmpty, canRedo: !history.undone.isEmpty, canScroll: !locksSelection && history.annotations.isEmpty)
        // Scale only on unusually narrow displays; hit targets transform with the view.
        let natural = toolbar.frame.size
        let scale = min(1, max(0.1, (bounds.width - 16) / natural.width))
        let visible = NSSize(width: natural.width * scale, height: natural.height * scale)
        let placement = CaptureGeometry.toolbarPlacement(selection: selection, size: visible,
                                                        reservedHeight: DesignTheme.expandedHeight * scale, bounds: bounds)
        toolbar.optionsAbove = placement.optionsAbove
        toolbar.frame = NSRect(origin: placement.origin, size: visible)
        toolbar.bounds = NSRect(origin: .zero, size: natural)
        onToolbarLayout?()
    }

    private func invalidateImage() { renderedImage = nil; needsDisplay = true }
    private func composite() -> CGImage? {
        if let renderedImage { return renderedImage }
        let annotations = history.annotations + (pending.map { [$0] } ?? [])
        if annotations.isEmpty { return baseImage }
        let image = AnnotationRenderer.render(base: baseImage, canvas: bounds.size, annotations: annotations)
        renderedImage = image; return image
    }
    func outputImage() -> CGImage? {
        guard let selection, !selection.isEmpty, let image = composite() else { return nil }
        let rect = CaptureGeometry.pixelRect(selection, canvas: bounds.size, image: image)
        return rect.isEmpty ? nil : image.cropping(to: rect)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.draw(composite() ?? baseImage, in: bounds)
        let highlight = selection ?? preview
        let mask = NSBezierPath(rect: bounds)
        if let highlight { mask.append(NSBezierPath(rect: highlight)) }
        mask.windingRule = .evenOdd
        NSColor.black.withAlphaComponent(0.5).setFill(); mask.fill()
        guard let highlight, !highlight.isEmpty else { return }
        SimpleSettings.green.setStroke()
        let border = NSBezierPath(rect: highlight); border.lineWidth = 2; border.stroke()
        if selection != nil {
            SimpleSettings.green.setFill()
            for point in CaptureGeometry.handles(for: highlight) {
                NSBezierPath(roundedRect: NSRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6), xRadius: 1, yRadius: 1).fill()
            }
            let sx = CGFloat(baseImage.width) / bounds.width, sy = CGFloat(baseImage.height) / bounds.height
            let dimensions = "\(Int(highlight.width * sx)) × \(Int(highlight.height * sy))"
            let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium), .foregroundColor: NSColor.white]
            let size = (dimensions as NSString).size(withAttributes: attributes)
            (dimensions as NSString).draw(at: NSPoint(x: max(4, min(bounds.maxX - size.width - 4, highlight.minX + 4)), y: min(bounds.maxY - size.height - 3, highlight.maxY + 5)), withAttributes: attributes)
        }
    }

    private func beginText(at point: NSPoint) {
        guard let selection else { return }
        let width = max(1, selection.maxX - point.x)
        let height = min(selection.height, max(30, SimpleSettings.fontSize * 3))
        let origin = NSPoint(x: point.x, y: max(selection.minY, point.y - height))
        let editor = NSTextView(frame: NSRect(origin: origin, size: NSSize(width: width, height: height)))
        editor.isRichText = false; editor.drawsBackground = false
        editor.font = .systemFont(ofSize: SimpleSettings.fontSize)
        editor.textColor = SimpleSettings.palette[SimpleSettings.colorIndex]
        editor.insertionPointColor = editor.textColor ?? .red
        editor.textContainerInset = .zero
        editor.textContainer?.lineFragmentPadding = 0
        editor.isVerticallyResizable = false; editor.isHorizontallyResizable = false
        editor.allowsUndo = true; editor.delegate = self
        addSubview(editor); textView = editor
        window?.makeFirstResponder(editor)
    }
    private func commitText() {
        guard let editor = textView else { return }
        if !editor.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            history.append(Annotation(tool: .text, points: [editor.frame.origin], color: editor.textColor ?? .red,
                                      width: 2, text: editor.string, fontSize: editor.font?.pointSize ?? 18, textRect: editor.frame))
        }
        cancelText(); invalidateImage(); updateToolbar()
    }
    private func cancelText() {
        textView?.delegate = nil; textView?.removeFromSuperview(); textView = nil
        window?.makeFirstResponder(self)
    }
    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            if textView.hasMarkedText() || NSApp.currentEvent?.modifierFlags.contains(.shift) == true { return false }
            commitText(); return true
        }
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) { cancelText(); return true }
        return false
    }
}
