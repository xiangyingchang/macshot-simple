// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

enum ToolbarAction { case tool(AnnotationTool), undo, redo, save, cancel, copy }

/// Native button tracking provides press/release cancellation and keyboard
/// activation; custom drawing only controls the small floating chrome.
class FeedbackButton: NSButton {
    // NSButton is normally flipped; vector icons use the canvas's y-up convention.
    override var isFlipped: Bool { false }
    var callback: (() -> Void)?
    private(set) var hovered = false
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) {
        super.init(frame: frame)
        title = ""; isBordered = false
        target = self; action = #selector(clicked)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func clicked() { callback?() }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area); tracking = area
    }
    override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .arrow) }
    func drawFeedback(selected: Bool = false, accent: NSColor = DesignTheme.ink) {
        let rect = bounds.insetBy(dx: 2, dy: 3)
        let path = NSBezierPath(roundedRect: rect, xRadius: 6, yRadius: 6)
        if isEnabled && (selected || hovered || isHighlighted) {
            let fill = isHighlighted ? accent.withAlphaComponent(0.17) : selected ? accent.withAlphaComponent(0.09) : DesignTheme.hover
            fill.setFill(); path.fill()
        }
        if window?.firstResponder === self {
            NSColor.keyboardFocusIndicatorColor.setStroke()
            let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 2), xRadius: 7, yRadius: 7)
            ring.lineWidth = 1.5; ring.stroke()
        }
    }
}

final class ToolbarButton: FeedbackButton {
    var tint = DesignTheme.ink { didSet { needsDisplay = true } }
    var chosen = false {
        didSet { setAccessibilityValue(chosen ? "已选中" : "未选中"); needsDisplay = true }
    }
    var tool: AnnotationTool?
    var symbol = ""
    var completion = false
    override func draw(_ dirtyRect: NSRect) {
        let accent = chosen ? DesignTheme.green : tint
        let color = isEnabled ? accent : DesignTheme.muted.withAlphaComponent(0.5)
        drawFeedback(selected: chosen || completion, accent: accent)
        let rect = NSRect(x: bounds.midX - 9, y: bounds.midY - 9, width: 18, height: 18)
        if let tool { drawTool(tool, in: rect, color: color); return }
        if symbol == "xmark" || symbol == "checkmark" {
            color.setStroke()
            let path = NSBezierPath(); path.lineWidth = 1.8; path.lineCapStyle = .round; path.lineJoinStyle = .round
            if symbol == "xmark" {
                path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2)); path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
                path.move(to: NSPoint(x: rect.minX + 2, y: rect.maxY - 2)); path.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + 2))
            } else {
                path.move(to: NSPoint(x: rect.minX + 1, y: rect.midY)); path.line(to: NSPoint(x: rect.minX + 7, y: rect.minY + 2)); path.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 2))
            }
            path.stroke(); return
        }
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: toolTip) else { return }
        let symbolImage = image.withSymbolConfiguration(.init(pointSize: DesignTheme.iconSize, weight: .regular)) ?? image
        let icon = NSImage(size: rect.size)
        icon.lockFocus()
        symbolImage.draw(in: NSRect(origin: .zero, size: rect.size))
        color.setFill(); NSRect(origin: .zero, size: rect.size).fill(using: .sourceAtop)
        icon.unlockFocus(); icon.draw(in: rect)
    }

    private func drawTool(_ tool: AnnotationTool, in rect: NSRect, color: NSColor) {
        color.setStroke(); color.setFill()
        let path = NSBezierPath(); path.lineWidth = DesignTheme.iconStroke
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        switch tool {
        case .rectangle: path.appendRoundedRect(rect.insetBy(dx: 1, dy: 2), xRadius: 1.3, yRadius: 1.3)
        case .ellipse: path.appendOval(in: rect.insetBy(dx: 0.5, dy: 1.5))
        case .arrow:
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2)); path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2))
            path.move(to: NSPoint(x: rect.minX + 7, y: rect.maxY - 2)); path.line(to: NSPoint(x: rect.maxX - 2, y: rect.maxY - 2)); path.line(to: NSPoint(x: rect.maxX - 2, y: rect.minY + 7))
        case .pencil:
            path.move(to: NSPoint(x: rect.minX + 2, y: rect.minY + 2))
            path.line(to: NSPoint(x: rect.minX + 3, y: rect.minY + 7))
            path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 1))
            path.line(to: NSPoint(x: rect.maxX - 1, y: rect.maxY - 5))
            path.line(to: NSPoint(x: rect.minX + 7, y: rect.minY + 3)); path.close()
            path.move(to: NSPoint(x: rect.maxX - 7, y: rect.maxY - 3)); path.line(to: NSPoint(x: rect.maxX - 3, y: rect.maxY - 7))
        case .pixelate:
            path.appendRoundedRect(rect.insetBy(dx: 1, dy: 1), xRadius: 1, yRadius: 1)
            for row in 0..<4 { for column in 0..<4 where (row + column) % 2 == 0 {
                NSBezierPath(rect: NSRect(x: rect.minX + 3 + CGFloat(column) * 3, y: rect.minY + 3 + CGFloat(row) * 3, width: 3, height: 3)).fill()
            } }
        case .text:
            path.appendRoundedRect(rect.insetBy(dx: 1, dy: 1), xRadius: 1, yRadius: 1)
            path.move(to: NSPoint(x: rect.minX + 5, y: rect.maxY - 5)); path.line(to: NSPoint(x: rect.maxX - 5, y: rect.maxY - 5))
            path.move(to: NSPoint(x: rect.midX, y: rect.maxY - 5)); path.line(to: NSPoint(x: rect.midX, y: rect.minY + 5))
        }
        path.stroke()
    }
}

final class ToolbarRow: NSView {
    var dividers: [CGFloat] = []
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = DesignTheme.paper.cgColor
        layer?.cornerRadius = 9
        layer?.borderColor = DesignTheme.border.cgColor
        layer?.borderWidth = DesignTheme.increasedContrast ? 1 : 0.5
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.14
        layer?.shadowRadius = 7
        layer?.shadowOffset = NSSize(width: 0, height: -3)
        // Preserve the familiar white screenshot toolbar in both system themes.
        appearance = NSAppearance(named: .aqua)
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        DesignTheme.border.setStroke()
        for x in dividers {
            let line = NSBezierPath()
            line.move(to: NSPoint(x: x, y: 8)); line.line(to: NSPoint(x: x, y: bounds.height - 8))
            line.lineWidth = 0.5; line.stroke()
        }
    }
}

final class CaptureToolbar: NSView {
    var onAction: ((ToolbarAction) -> Void)?
    var onWidth: ((CGFloat) -> Void)?
    var onColor: ((Int) -> Void)?
    var onFontSize: ((CGFloat) -> Void)?
    private let mainRow = ToolbarRow(frame: .zero)
    private let optionsRow = ToolbarRow(frame: .zero)
    private(set) var buttons: [ToolbarButton] = []
    private(set) var widthButtons: [NSButton] = []
    private(set) var tool: AnnotationTool?
    var optionsAbove = false { didSet { layoutRows() } }
    var mainRowFrame: NSRect { mainRow.frame }

    override init(frame: NSRect) { super.init(frame: frame); addSubview(mainRow); addSubview(optionsRow) }
    required init?(coder: NSCoder) { fatalError() }
    override func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return super.hitTest(point) ?? self
    }
    override func mouseDown(with event: NSEvent) {}

    func update(tool: AnnotationTool?, width: CGFloat, colorIndex: Int, fontSize: CGFloat, canUndo: Bool, canRedo: Bool) {
        self.tool = tool
        mainRow.subviews.forEach { $0.removeFromSuperview() }; optionsRow.subviews.forEach { $0.removeFromSuperview() }
        buttons.removeAll(); widthButtons.removeAll()
        let actions = AnnotationTool.allCases.map { ToolbarAction.tool($0) } + [.undo, .redo, .save, .cancel, .copy]
        var x: CGFloat = 8
        mainRow.dividers.removeAll()
        for (index, action) in actions.enumerated() {
            if index == 6 || index == 9 { mainRow.dividers.append(x + 4); x += 12 }
            let button = ToolbarButton(frame: NSRect(x: x, y: 4, width: 36, height: 36))
            switch action {
            case .tool(let item): button.tool = item; button.toolTip = item.title; button.chosen = tool == item
            case .undo: button.symbol = "arrow.uturn.backward"; button.toolTip = "撤销 · ⌘Z"; button.isEnabled = canUndo
            case .redo: button.symbol = "arrow.uturn.forward"; button.toolTip = "重做 · ⇧⌘Z"; button.isEnabled = canRedo
            case .save: button.symbol = "square.and.arrow.down"; button.toolTip = "保存 PNG · ⌘S"
            case .cancel: button.symbol = "xmark"; button.toolTip = "取消 · Esc"; button.tint = DesignTheme.red
            case .copy: button.symbol = "checkmark"; button.toolTip = "复制并完成 · Enter"; button.tint = DesignTheme.green; button.completion = true
            }
            button.setAccessibilityLabel(button.toolTip)
            button.callback = { [weak self] in self?.onAction?(action) }
            buttons.append(button); mainRow.addSubview(button); x += 40
        }
        let mainWidth = x + 8
        frame.size = NSSize(width: mainWidth, height: tool == nil ? DesignTheme.mainHeight : DesignTheme.expandedHeight)
        bounds = NSRect(origin: .zero, size: frame.size)
        optionsRow.isHidden = tool == nil
        guard let tool else { layoutRows(); return }
        x = 8; optionsRow.dividers.removeAll()
        if tool == .text {
            let minus = ActionButton(frame: NSRect(x: x, y: 3, width: 28, height: 30))
            minus.title = "−"; minus.toolTip = "减小字号"; minus.isEnabled = fontSize > 12
            minus.callback = { [weak self] in self?.onFontSize?(fontSize - 2) }
            optionsRow.addSubview(minus); x += 30
            let label = NSTextField(labelWithString: "\(Int(fontSize))")
            label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
            label.alignment = .center; label.textColor = DesignTheme.ink
            label.frame = NSRect(x: x, y: 9, width: 28, height: 18)
            optionsRow.addSubview(label); x += 30
            let plus = ActionButton(frame: NSRect(x: x, y: 3, width: 28, height: 30))
            plus.title = "+"; plus.toolTip = "增大字号"; plus.isEnabled = fontSize < 72
            plus.callback = { [weak self] in self?.onFontSize?(fontSize + 2) }
            optionsRow.addSubview(plus); x += 30
        } else {
            for (index, value) in SimpleSettings.widths.enumerated() {
                let button = DotButton(frame: NSRect(x: x, y: 3, width: 30, height: 30))
                button.diameter = [4, 8, 12][index]; button.selected = value == width
                button.toolTip = ["细", "中", "粗"][index]; button.setAccessibilityLabel(button.toolTip)
                button.setAccessibilityValue(button.selected ? "已选中" : "未选中")
                button.callback = { [weak self] in self?.onWidth?(value) }
                optionsRow.addSubview(button); widthButtons.append(button); x += 30
            }
        }
        if tool != .pixelate {
            optionsRow.dividers.append(x + 5); x += 16
            for (index, color) in SimpleSettings.palette.enumerated() {
                let button = ColorButton(frame: NSRect(x: x, y: 3, width: 28, height: 30))
                button.color = color; button.selected = colorIndex == index
                button.toolTip = ["蓝色", "绿色", "黄色", "灰色", "白色", "红色"][index]
                button.setAccessibilityLabel(button.toolTip); button.setAccessibilityValue(button.selected ? "已选中" : "未选中")
                button.callback = { [weak self] in self?.onColor?(index) }
                optionsRow.addSubview(button); x += 30
            }
        }
        optionsRow.frame.size = NSSize(width: x + 8, height: DesignTheme.optionsHeight)
        layoutRows()
    }
    private func layoutRows() {
        let height = tool == nil ? DesignTheme.mainHeight : DesignTheme.expandedHeight
        mainRow.frame = NSRect(x: 0, y: optionsAbove ? 0 : height - DesignTheme.mainHeight, width: frame.width, height: DesignTheme.mainHeight)
        optionsRow.frame.origin = NSPoint(x: 0, y: optionsAbove ? DesignTheme.mainHeight + DesignTheme.rowGap : 0)
    }
}

final class ActionButton: FeedbackButton {
    override func draw(_ dirtyRect: NSRect) {
        drawFeedback()
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 16, weight: .regular), .foregroundColor: isEnabled ? DesignTheme.ink : DesignTheme.muted]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(at: NSPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attributes)
    }
}

final class DotButton: FeedbackButton {
    var diameter: CGFloat = 4
    var selected = false
    override func draw(_ dirtyRect: NSRect) {
        drawFeedback()
        (selected ? DesignTheme.green : DesignTheme.muted).setFill()
        NSBezierPath(ovalIn: NSRect(x: bounds.midX - diameter / 2, y: bounds.midY - diameter / 2, width: diameter, height: diameter)).fill()
        if selected {
            DesignTheme.green.setStroke()
            let ring = NSBezierPath(ovalIn: NSRect(x: bounds.midX - 10, y: bounds.midY - 10, width: 20, height: 20))
            ring.lineWidth = 1; ring.stroke()
        }
    }
}

final class ColorButton: FeedbackButton {
    var color: NSColor = .red
    var selected = false
    override func draw(_ dirtyRect: NSRect) {
        drawFeedback()
        let rect = bounds.insetBy(dx: 6, dy: 7)
        let swatch = NSBezierPath(roundedRect: rect, xRadius: 3, yRadius: 3)
        color.setFill(); swatch.fill(); DesignTheme.divider.setStroke(); swatch.lineWidth = 0.5; swatch.stroke()
        if selected {
            DesignTheme.ink.setStroke()
            let ring = NSBezierPath(roundedRect: rect.insetBy(dx: -3, dy: -3), xRadius: 5, yRadius: 5)
            ring.lineWidth = 1.2; ring.stroke()
        }
    }
}
