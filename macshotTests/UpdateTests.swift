import Cocoa
import XCTest

final class UpdateTests: XCTestCase {
    func testFeedFollowsHostCPUNotRunningSlice() {
        XCTAssertEqual(
            UpdateFeed.feedURLString(appleSilicon: true),
            "https://github.com/xiangyingchang/macshot-simple/releases/latest/download/appcast-arm64.xml"
        )
        XCTAssertEqual(
            UpdateFeed.feedURLString(appleSilicon: false),
            "https://github.com/xiangyingchang/macshot-simple/releases/latest/download/appcast-x86_64.xml"
        )
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        let rosetta = sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0) == 0 && translated == 1
        #if arch(arm64)
        XCTAssertTrue(UpdateFeed.hostIsAppleSilicon)
        #else
        // An Intel slice under Rosetta must still pick the Apple silicon feed.
        XCTAssertEqual(UpdateFeed.hostIsAppleSilicon, rosetta)
        #endif
    }

    func testInfoPlistRequiresSignedUpdatesAndSecureFeed() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("macshot/Info.plist")
        let plist = try XCTUnwrap(NSDictionary(contentsOf: url) as? [String: Any])
        XCTAssertEqual(plist["SUFeedURL"] as? String, UpdateFeed.feedURLString(appleSilicon: true))
        XCTAssertEqual((plist["SUPublicEDKey"] as? String)?.count, 44)
        XCTAssertEqual(plist["SURequireSignedFeed"] as? Bool, true)
        XCTAssertEqual(plist["SUVerifyUpdateBeforeExtraction"] as? Bool, true)
        XCTAssertEqual(plist["SUEnableInstallerLauncherService"] as? Bool, true)
        XCTAssertEqual(plist["SUScheduledCheckInterval"] as? Int, 86400)
    }

    func testStatusPopoverShowsCheckRowWhenIdle() throws {
        var checked = false
        let controller = makePopover(.idle) { checked = true }
        let button = try XCTUnwrap(findButton("检查更新…", in: controller.view))
        button.performClick(nil)
        XCTAssertTrue(checked)
        XCTAssertNil(findButton("升级到 0.2.6", in: controller.view))
        XCTAssertEqual(controller.preferredContentSize.height, StatusPopoverController.panelHeight(rows: 6))
    }

    func testStatusPopoverHighlightsAvailableUpdate() throws {
        var checked = false
        let controller = makePopover(.available(version: "0.2.6")) { checked = true }
        let button = try XCTUnwrap(findButton("升级到 0.2.6", in: controller.view))
        XCTAssertNil(findButton("检查更新…", in: controller.view))
        button.performClick(nil)
        XCTAssertTrue(checked)
        let idleWidth = makePopover(.idle) {}.preferredContentSize.width
        XCTAssertGreaterThanOrEqual(controller.preferredContentSize.width, idleWidth)
        XCTAssertLessThan(controller.preferredContentSize.width, 240)
        // Review artifact only (no screen pixels): rendered menu in /tmp.
        let view = controller.view
        // AppDelegate pins the status popover to the light paper appearance.
        view.appearance = NSAppearance(named: .aqua)
        view.frame = NSRect(origin: .zero, size: controller.preferredContentSize)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: URL(fileURLWithPath: "/tmp/macshot-simple-update-menu-available.png"))
        XCTAssertGreaterThan(png.count, 1000)
    }

    func testBadgedStatusIconStaysTemplateAndAddsDot() throws {
        let plain = try XCTUnwrap(StatusIcon.image(badged: false))
        let badged = try XCTUnwrap(StatusIcon.image(badged: true))
        XCTAssertTrue(badged.isTemplate)
        XCTAssertEqual(plain.size, badged.size)
        func alpha(_ image: NSImage, at point: NSPoint) throws -> CGFloat {
            let rep = try XCTUnwrap(NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(image.size.width * 2), pixelsHigh: Int(image.size.height * 2),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = image.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            image.draw(in: NSRect(origin: .zero, size: image.size))
            NSGraphicsContext.restoreGraphicsState()
            return try XCTUnwrap(rep.colorAt(x: Int(point.x * 2), y: rep.pixelsHigh - 1 - Int(point.y * 2))).alphaComponent
        }
        // Dot center sits in the top-right corner of the glyph.
        let d = max(5, badged.size.width * 0.36)
        let center = NSPoint(x: badged.size.width - d / 2, y: badged.size.height - d / 2)
        XCTAssertGreaterThan(try alpha(badged, at: center), 0.9)
    }

    func testPreferencesAutomaticUpdateToggleReportsChoice() {
        var received: [Bool] = []
        let view = PreferencesContentView(
            automaticallyChecksForUpdates: true,
            onShortcut: { _, _ in },
            onAutomaticUpdatesChange: { received.append($0) }
        )
        XCTAssertEqual(view.automaticUpdatesCheckbox.state, .on)
        view.automaticUpdatesCheckbox.performClick(nil)
        XCTAssertEqual(received, [false])
    }

    private func makePopover(_ state: UpdateState, onCheck: @escaping () -> Void) -> StatusPopoverController {
        StatusPopoverController(
            hotkeyDescription: "⌘⇧X", updateState: state,
            onCapture: {}, onSettings: {}, onPermissionSettings: {},
            onCheckUpdate: onCheck, onAbout: {}, onQuit: {}
        )
    }

    private func findButton(_ label: String, in view: NSView) -> NSButton? {
        if let button = view as? NSButton, button.accessibilityLabel() == label { return button }
        for subview in view.subviews { if let found = findButton(label, in: subview) { return found } }
        return nil
    }
}
