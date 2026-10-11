import Cocoa

final class StatusPopoverController: NSViewController {
    private static let rowHeight: CGFloat = 34
    private static let rowInset: CGFloat = 4
    private static let horizontalPadding: CGFloat = 10
    private static let symbolSize: CGFloat = 15
    private static let symbolTextSpacing: CGFloat = 8
    private static let sectionSpacing: CGFloat = 6
    private static let minimumRowWidth: CGFloat = 160

    private let hotkeyDescription: String
    private let rowWidth: CGFloat
    private let onCapture: () -> Void
    private let onSettings: () -> Void
    private let onPermissionSettings: () -> Void
    private let onAbout: () -> Void
    private let onQuit: () -> Void

    init(
        hotkeyDescription: String,
        onCapture: @escaping () -> Void,
        onSettings: @escaping () -> Void,
        onPermissionSettings: @escaping () -> Void,
        onAbout: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.hotkeyDescription = hotkeyDescription
        rowWidth = Self.rowWidth(for: hotkeyDescription)
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onPermissionSettings = onPermissionSettings
        self.onAbout = onAbout
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(
            width: rowWidth + Self.horizontalPadding * 2,
            height: Self.panelHeight
        )
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(origin: .zero, size: preferredContentSize))
        root.wantsLayer = true
        root.layer?.backgroundColor = DesignTheme.paper.cgColor
        root.layer?.cornerRadius = 12
        root.layer?.borderColor = DesignTheme.border.cgColor
        root.layer?.borderWidth = DesignTheme.increasedContrast ? 1 : 0.5
        root.layer?.masksToBounds = true

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(
            top: 8,
            left: Self.horizontalPadding,
            bottom: 8,
            right: Self.horizontalPadding
        )
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let captureRow = makeRow(
            "截图",
            symbol: "viewfinder",
            shortcut: hotkeyDescription,
            isPrimary: true,
            action: #selector(capturePressed)
        )
        let settingsRow = makeRow(
            "设置快捷键…",
            symbol: "keyboard",
            action: #selector(settingsPressed)
        )
        let permissionRow = makeRow(
            "屏幕录制权限…",
            symbol: "lock.shield",
            action: #selector(permissionSettingsPressed)
        )
        let aboutRow = makeRow(
            "关于 MacShot Simple",
            symbol: "info.circle",
            action: #selector(aboutPressed)
        )
        let quitRow = makeRow(
            "退出",
            symbol: "power",
            action: #selector(quitPressed)
        )

        stack.addArrangedSubview(captureRow)
        let captureSeparator = addSeparator(to: stack)
        stack.setCustomSpacing(Self.sectionSpacing, after: captureRow)
        stack.setCustomSpacing(Self.sectionSpacing, after: captureSeparator)

        stack.addArrangedSubview(settingsRow)
        stack.addArrangedSubview(permissionRow)
        let footerSeparator = addSeparator(to: stack)
        stack.setCustomSpacing(Self.sectionSpacing, after: permissionRow)
        stack.setCustomSpacing(Self.sectionSpacing, after: footerSeparator)

        stack.addArrangedSubview(aboutRow)
        stack.addArrangedSubview(quitRow)
        view = root
    }

    private static let panelHeight: CGFloat =
        rowHeight * 5 + 2 + sectionSpacing * 4 + 16

    private func addSeparator(to stack: NSStackView) -> NSBox {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return separator
    }

    private func makeRow(
        _ title: String,
        symbol: String,
        shortcut: String? = nil,
        isPrimary: Bool = false,
        action: Selector
    ) -> NSView {
        let row = StatusPopoverRowView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: rowWidth).isActive = true
        row.heightAnchor.constraint(equalToConstant: Self.rowHeight).isActive = true

        let button = NSButton(title: "", target: self, action: action)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.setAccessibilityLabel(
            shortcut.map { "\(title)，快捷键 \($0)" } ?? title
        )
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)

        let symbolColor = isPrimary ? DesignTheme.green : NSColor.secondaryLabelColor
        let symbolConfiguration = NSImage.SymbolConfiguration(
            pointSize: Self.symbolSize,
            weight: isPrimary ? .medium : .regular
        )
        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)
        icon.image?.isTemplate = true
        icon.contentTintColor = symbolColor
        icon.imageScaling = .scaleProportionallyDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let titleFont: NSFont = isPrimary
            ? NSFont.systemFont(ofSize: 13, weight: .semibold)
            : NSFont.menuFont(ofSize: 13)
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = titleFont
        titleLabel.textColor = .labelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let visuals = StatusPopoverAccessoryView()
        visuals.translatesAutoresizingMaskIntoConstraints = false
        visuals.addSubview(icon)
        visuals.addSubview(titleLabel)
        row.addSubview(visuals)

        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.rowInset),
            button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.rowInset),
            button.topAnchor.constraint(equalTo: row.topAnchor),
            button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
            visuals.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: Self.rowInset),
            visuals.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            visuals.widthAnchor.constraint(equalToConstant: Self.symbolSize + Self.symbolTextSpacing + Self.textWidth(title, font: titleFont)),
            visuals.heightAnchor.constraint(equalToConstant: Self.rowHeight),
            icon.leadingAnchor.constraint(equalTo: visuals.leadingAnchor),
            icon.centerYAnchor.constraint(equalTo: visuals.centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: Self.symbolSize),
            icon.heightAnchor.constraint(equalToConstant: Self.symbolSize),
            titleLabel.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: Self.symbolTextSpacing),
            titleLabel.trailingAnchor.constraint(equalTo: visuals.trailingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: visuals.centerYAnchor)
        ])

        if let shortcut {
            let chip = makeShortcutChip(shortcut)
            row.addSubview(chip)
            NSLayoutConstraint.activate([
                chip.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -Self.rowInset),
                chip.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
        }
        return row
    }

    private func makeShortcutChip(_ shortcut: String) -> NSView {
        let chip = StatusPopoverAccessoryView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        chip.wantsLayer = true
        chip.layer?.backgroundColor = DesignTheme.hover.cgColor
        chip.layer?.cornerRadius = 5

        let label = NSTextField(labelWithString: shortcut)
        label.font = .monospacedSystemFont(ofSize: 11, weight: .medium)
        label.textColor = DesignTheme.ink
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        chip.addSubview(label)

        NSLayoutConstraint.activate([
            chip.widthAnchor.constraint(
                equalToConstant: Self.shortcutChipWidth(for: shortcut)
            ),
            chip.heightAnchor.constraint(equalToConstant: 22),
            label.leadingAnchor.constraint(equalTo: chip.leadingAnchor, constant: 6),
            label.trailingAnchor.constraint(equalTo: chip.trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: chip.centerYAnchor)
        ])
        return chip
    }

    private static func rowWidth(for hotkeyDescription: String) -> CGFloat {
        let titleFont = NSFont.menuFont(ofSize: 13)
        let titles = [
            "设置快捷键…",
            "屏幕录制权限…",
            "关于 MacShot Simple",
            "退出"
        ]
        let widestTitle = titles.map { textWidth($0, font: titleFont) }.max() ?? 0
        let contentWidth =
            widestTitle
            + symbolSize
            + symbolTextSpacing
            + rowInset * 2
            + 8
        let captureWidth =
            symbolSize
            + symbolTextSpacing
            + textWidth("截图", font: .systemFont(ofSize: 13, weight: .semibold))
            + 8
            + shortcutChipWidth(for: hotkeyDescription)
            + rowInset * 2

        return ceil(max(minimumRowWidth, contentWidth, captureWidth))
    }

    private static func shortcutChipWidth(for shortcut: String) -> CGFloat {
        ceil(textWidth(
            shortcut,
            font: .monospacedSystemFont(ofSize: 11, weight: .medium)
        ) + 12)
    }

    private static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font]).width
    }

    @objc private func capturePressed() { onCapture() }
    @objc private func settingsPressed() { onSettings() }
    @objc private func permissionSettingsPressed() { onPermissionSettings() }
    @objc private func aboutPressed() { onAbout() }
    @objc private func quitPressed() { onQuit() }
}

private final class StatusPopoverRowView: NSView {
    private var trackingAreaForHover: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 8
    }

    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaForHover { removeTrackingArea(trackingAreaForHover) }
        let trackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        trackingAreaForHover = trackingArea
    }

    override func mouseEntered(with event: NSEvent) {
        layer?.backgroundColor = DesignTheme.hover.cgColor
    }

    override func mouseExited(with event: NSEvent) {
        layer?.backgroundColor = NSColor.clear.cgColor
    }
}

private final class StatusPopoverAccessoryView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
