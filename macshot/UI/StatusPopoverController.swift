import Cocoa

final class StatusPopoverController: NSViewController {
    private let hotkeyDescription: String
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
        self.onCapture = onCapture
        self.onSettings = onSettings
        self.onPermissionSettings = onPermissionSettings
        self.onAbout = onAbout
        self.onQuit = onQuit
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = NSSize(width: 268, height: 202)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 268, height: 202))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        stack.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            stack.topAnchor.constraint(equalTo: root.topAnchor),
            stack.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])

        let captureRow = makeRow("截图", shortcut: hotkeyDescription, action: #selector(capturePressed))
        let settingsRow = makeRow("设置快捷键…", action: #selector(settingsPressed))
        let permissionRow = makeRow("屏幕录制权限…", action: #selector(permissionSettingsPressed))
        let aboutRow = makeRow("关于 MacShot Simple", action: #selector(aboutPressed))
        stack.addArrangedSubview(captureRow)
        stack.addArrangedSubview(settingsRow)
        stack.addArrangedSubview(permissionRow)
        stack.addArrangedSubview(aboutRow)

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalToConstant: 252).isActive = true
        separator.heightAnchor.constraint(equalToConstant: 1).isActive = true
        stack.setCustomSpacing(6, after: aboutRow)
        stack.setCustomSpacing(6, after: separator)

        stack.addArrangedSubview(makeRow("退出", action: #selector(quitPressed)))
        view = root
    }

    private func makeRow(_ title: String, shortcut: String? = nil, action: Selector) -> NSView {
        let row = NSView()
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: 252).isActive = true
        row.heightAnchor.constraint(equalToConstant: 32).isActive = true

        let button = NSButton(title: title, target: self, action: action)
        button.isBordered = false
        button.alignment = .left
        button.font = .menuFont(ofSize: 13)
        button.contentTintColor = .labelColor
        button.setAccessibilityLabel(title)
        button.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(button)

        if let shortcut {
            let keyLabel = NSTextField(labelWithString: shortcut)
            keyLabel.font = .menuFont(ofSize: 12)
            keyLabel.textColor = .secondaryLabelColor
            keyLabel.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(keyLabel)
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
                button.trailingAnchor.constraint(equalTo: keyLabel.leadingAnchor, constant: -8),
                button.centerYAnchor.constraint(equalTo: row.centerYAnchor),
                keyLabel.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                keyLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                button.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 8),
                button.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -8),
                button.centerYAnchor.constraint(equalTo: row.centerYAnchor)
            ])
        }
        return row
    }

    @objc private func capturePressed() { onCapture() }
    @objc private func settingsPressed() { onSettings() }
    @objc private func permissionSettingsPressed() { onPermissionSettings() }
    @objc private func aboutPressed() { onAbout() }
    @objc private func quitPressed() { onQuit() }
}
