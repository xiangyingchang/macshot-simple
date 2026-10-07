// MacShot Simple, derived from MacShot v4.3.0 (sw33tLie), GPL-3.0.
// Modified 2026-10-07: screenshot-only app, no network or recording features.
import Cocoa
import Carbon
import UniformTypeIdentifiers

final class CaptureWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let hotkey = HotkeyManager()
    private var windows: [CaptureWindow] = []
    private var previousApp: NSRunningApplication?
    private var capturing = false
    private var saving = false
    private var preferences: PreferencesController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--check-capture") {
            Task { await CaptureCheck.run(); NSApp.terminate(nil) }
            return
        }
        // Prevent two copies from silently competing for the same global hotkey.
        if let id = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: id).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil); return
        }
        buildMainMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem?.button?.image = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "MacShot Simple")
        hotkey.onCapture = { [weak self] in self?.startCapture() }
        registerHotkey()
        updateStatusMenu()
    }
    func applicationWillTerminate(_ notification: Notification) { hotkey.unregister() }

    private func buildMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 MacShot Simple", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu; main.addItem(appItem)
        let editItem = NSMenuItem(); let edit = NSMenu(title: "编辑")
        for (name, selector, key) in [("撤销", Selector("undo:"), "z"), ("剪切", #selector(NSText.cut(_:)), "x"),
                                     ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"),
                                     ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.addItem(withTitle: name, action: selector, keyEquivalent: key)
        }
        let redo = edit.addItem(withTitle: "重做", action: Selector("redo:"), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editItem.submenu = edit; main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func updateStatusMenu() {
        let menu = NSMenu()
        let capture = NSMenuItem(title: "截图  \(SimpleSettings.hotkeyDescription)", action: #selector(captureFromMenu), keyEquivalent: "")
        capture.target = self; menu.addItem(capture)
        let settings = NSMenuItem(title: "设置快捷键…", action: #selector(showPreferences), keyEquivalent: "")
        settings.target = self; menu.addItem(settings)
        let permission = NSMenuItem(title: "屏幕录制权限…", action: #selector(openPermissionSettings), keyEquivalent: "")
        permission.target = self; menu.addItem(permission)
        menu.addItem(.separator())
        let about = NSMenuItem(title: "关于 MacShot Simple", action: #selector(showAbout), keyEquivalent: "")
        about.target = self; menu.addItem(about)
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "")
        statusItem?.menu = menu
    }

    @objc private func captureFromMenu() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.startCapture() }
    }
    private func registerHotkey() {
        let key = SimpleSettings.hotkey
        if hotkey.register(key: key.key, modifiers: key.modifiers) != noErr {
            showError("截图快捷键被占用", detail: "请在菜单栏的设置中换一个快捷键。")
        }
    }

    @objc private func showPreferences() {
        guard windows.isEmpty, !capturing else { return }
        if preferences?.window?.isVisible == true {
            NSApp.activate(ignoringOtherApps: true); preferences?.showWindow(nil); return
        }
        previousApp = NSWorkspace.shared.frontmostApplication
        preferences = PreferencesController { [weak self] key, mods in
            guard let self else { return }
            let old = SimpleSettings.hotkey
            if self.hotkey.register(key: key, modifiers: mods) == noErr {
                SimpleSettings.saveHotkey(key: key, modifiers: mods); self.updateStatusMenu()
            } else {
                _ = self.hotkey.register(key: old.key, modifiers: old.modifiers)
                self.showError("这个快捷键无法使用", detail: "快捷键可能被其他应用占用，请换一个组合。")
            }
        }
        preferences?.onClose = { [weak self] in self?.returnFocusIfNeeded() }
        NSApp.activate(ignoringOtherApps: true)
        preferences?.showWindow(nil)
    }

    @objc private func showAbout() {
        guard windows.isEmpty, !capturing else { return }
        previousApp = NSWorkspace.shared.frontmostApplication
        let alert = NSAlert()
        alert.messageText = "MacShot Simple"
        alert.informativeText = "简单截图与标注。\n基于 sw33tLie 的 MacShot v4.3.0 修改。\nGPL-3.0 开源许可证。\n版本 \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")"
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal(); returnFocusIfNeeded()
    }

    @objc private func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
    }

    func startCapture() {
        guard !capturing, !saving, windows.isEmpty, preferences?.window?.isVisible != true else { return }
        capturing = true
        previousApp = NSWorkspace.shared.frontmostApplication
        let immediate = ScreenCaptureManager.makeImmediateCaptureContext()
        let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        Task { [weak self] in
            guard let self else { return }
            var captures: [ScreenCapture]?
            if #available(macOS 14.0, *) { captures = await ScreenCaptureManager.captureAllScreensImmediatelySCK() }
            // Never turn denied permission into a desktop-only screenshot.
            if captures == nil, CGPreflightScreenCaptureAccess() {
                let fallback = ScreenCaptureManager.captureAllScreensImmediately(context: immediate)
                if !fallback.isEmpty, fallback.count == immediate.screens.count { captures = fallback }
            }
            self.capturing = false
            guard let captures, !captures.isEmpty else {
                if !CGPreflightScreenCaptureAccess() {
                    _ = CGRequestScreenCaptureAccess()
                    self.showPermissionHelp()
                } else { self.showError("截图失败", detail: "屏幕暂时无法读取，请稍后重试。") }
                self.returnFocusIfNeeded(); return
            }
            self.showCaptures(captures, windowInfo: windowInfo)
        }
    }

    private func showCaptures(_ captures: [ScreenCapture], windowInfo: [[String: Any]]) {
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? captures[0].screen.frame.maxY
        for capture in captures {
            let frame = capture.screen.frame
            let rects = windowInfo.compactMap { info -> NSRect? in
                guard (info[kCGWindowOwnerPID as String] as? Int32) != ProcessInfo.processInfo.processIdentifier,
                      (info[kCGWindowLayer as String] as? Int) == 0,
                      (info[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                      let dictionary = info[kCGWindowBounds as String] as? [String: Any],
                      let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary), rect.width >= 40, rect.height >= 40 else { return nil }
                let local = CaptureGeometry.windowRect(rect, primaryHeight: primaryHeight, screenFrame: frame)
                return local.intersects(NSRect(origin: .zero, size: frame.size)) ? local : nil
            }
            let window = CaptureWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.hidesOnDeactivate = false; window.isReleasedWhenClosed = false
            window.isOpaque = true; window.hasShadow = false; window.acceptsMouseMovedEvents = true
            let canvas = CaptureCanvas(frame: NSRect(origin: .zero, size: frame.size), image: capture.image, windowRects: rects)
            window.contentView = canvas
            canvas.onSelected = { [weak self, weak canvas] in
                guard let self else { return }
                for other in self.windows.compactMap({ $0.contentView as? CaptureCanvas }) where other !== canvas { other.resetSelection() }
            }
            canvas.onCancel = { [weak self] in self?.dismissCaptures() }
            canvas.onCopy = { [weak self] image in self?.copy(image) }
            canvas.onSave = { [weak self] image in self?.save(image) }
            canvas.onFailure = { [weak self] in self?.showError("无法生成截图", detail: "截图没有复制或保存，请重试。") }
            windows.append(window)
            window.orderFrontRegardless()
        }
        NSApp.activate(ignoringOtherApps: true)
        let mouse = NSEvent.mouseLocation
        let active = windows.first { $0.frame.contains(mouse) } ?? windows.first
        active?.makeKeyAndOrderFront(nil)
        for window in windows {
            window.makeFirstResponder(window.contentView)
            if let canvas = window.contentView as? CaptureCanvas {
                canvas.refreshPreview(at: NSPoint(x: mouse.x - window.frame.minX, y: mouse.y - window.frame.minY))
            }
        }
    }

    private func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
    private func copy(_ image: CGImage) {
        guard let png = pngData(image) else { showError("复制失败", detail: "无法生成 PNG，请重试。"); return }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = NSBitmapImageRep(cgImage: image).tiffRepresentation { item.setData(tiff, forType: .tiff) }
        NSPasteboard.general.clearContents()
        guard NSPasteboard.general.writeObjects([item]) else { showError("复制失败", detail: "剪贴板暂时不可用，请重试。"); return }
        dismissCaptures()
    }
    private func save(_ image: CGImage) {
        guard !saving, let data = pngData(image) else { showError("保存失败", detail: "无法生成 PNG，请重试。"); return }
        saving = true
        windows.forEach { $0.orderOut(nil) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        panel.nameFieldStringValue = "截图 \(formatter.string(from: Date())).png"
        NSApp.activate(ignoringOtherApps: true)
        let result = panel.runModal()
        if result == .OK, let url = panel.url {
            do { try data.write(to: url, options: .atomic); saving = false; dismissCaptures(); return }
            catch { showError("保存失败", detail: error.localizedDescription) }
        }
        saving = false
        windows.forEach { $0.orderFrontRegardless() }
        windows.first(where: { ($0.contentView as? CaptureCanvas)?.selection != nil })?.makeKeyAndOrderFront(nil)
    }
    private func dismissCaptures() {
        for window in windows { window.orderOut(nil); window.close() }
        windows.removeAll()
        returnFocusIfNeeded()
    }
    private func returnFocusIfNeeded() {
        guard preferences?.window?.isVisible != true else { return }
        NSApp.setActivationPolicy(.accessory)
        if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp.activate(options: .activateIgnoringOtherApps) }
        previousApp = nil
    }
    private func showPermissionHelp() {
        let alert = NSAlert()
        alert.messageText = "请允许 MacShot Simple 录制屏幕"
        alert.informativeText = "在系统设置的“隐私与安全性 → 屏幕与系统音频录制”中打开 MacShot Simple。若已经打开，请退出本应用后重新打开。"
        alert.addButton(withTitle: "打开系统设置"); alert.addButton(withTitle: "稍后")
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn { openPermissionSettings() }
    }
    private func showError(_ message: String, detail: String) {
        let alert = NSAlert(); alert.messageText = message; alert.informativeText = detail
        let visible = windows.filter { $0.isVisible }
        visible.forEach { $0.orderOut(nil) }
        NSApp.activate(ignoringOtherApps: true); alert.runModal()
        visible.forEach { $0.orderFrontRegardless() }
        visible.first(where: { ($0.contentView as? CaptureCanvas)?.selection != nil })?.makeKeyAndOrderFront(nil)
    }
}
