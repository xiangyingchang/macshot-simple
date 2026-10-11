import Cocoa

final class AboutPanelController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(version: String) {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 190),
            styleMask: [.titled, .closable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "关于 MacShot Simple"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        panel.delegate = self
        panel.contentView = makeContentView(version: version)
        panel.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }

    @objc private func openProjectWebsite() {
        guard let url = URL(string: "https://github.com/xiangyingchang/macshot-simple") else { return }
        NSWorkspace.shared.open(url)
    }

    private func makeContentView(version: String) -> NSView {
        let content = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 190))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: content.bottomAnchor, constant: -18)
        ])

        let title = NSTextField(labelWithString: "MacShot Simple")
        title.font = .systemFont(ofSize: 20, weight: .semibold)
        stack.addArrangedSubview(title)

        let details = NSTextField(wrappingLabelWithString:
            "简单截图与标注。\n基于 sw33tLie 的 MacShot v4.3.0 修改。\nGPL-3.0 开源许可证。\n版本 \(version)"
        )
        details.font = .systemFont(ofSize: 12)
        details.textColor = .secondaryLabelColor
        details.preferredMaxLayoutWidth = 372
        stack.addArrangedSubview(details)

        let projectLink = NSButton(
            title: "https://github.com/xiangyingchang/macshot-simple",
            target: self,
            action: #selector(openProjectWebsite)
        )
        projectLink.isBordered = false
        projectLink.bezelStyle = .inline
        projectLink.alignment = .left
        projectLink.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        projectLink.contentTintColor = .linkColor
        projectLink.setAccessibilityLabel("打开 MacShot Simple 的 GitHub 仓库")
        stack.addArrangedSubview(projectLink)

        return content
    }
}
