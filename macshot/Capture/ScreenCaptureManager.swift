// Derived from MacShot v4.3.0 (sw33tLie), GPL-3.0.
// Modified 2026-10-07: keep screenshot paths only.
import Cocoa
import ScreenCaptureKit

struct ScreenCapture {
    let screen: NSScreen
    let image: CGImage
}

class ScreenCaptureManager {

    struct ImmediateCaptureContext {
        let screens: [NSScreen]
        let mainHeight: CGFloat
    }

    /// Synchronous WindowServer snapshot used by global hotkeys before macshot
    /// activates. This preserves transient UI such as menu extras, app menus,
    /// Raycast/Spotlight-style panels, and other windows that disappear as soon
    /// as focus changes.
    static func makeImmediateCaptureContext(timing: (@Sendable (String) -> Void)? = nil) -> ImmediateCaptureContext {
        timing?("makeImmediateCaptureContext NSScreen.screens begin")
        let screens = NSScreen.screens
        timing?("makeImmediateCaptureContext NSScreen.screens end count=\(screens.count)")
        let mainHeight = screens.first?.frame.height ?? 0
        return ImmediateCaptureContext(screens: screens, mainHeight: mainHeight)
    }

    static func captureAllScreensImmediately(
        context: ImmediateCaptureContext,
        timing: (@Sendable (String) -> Void)? = nil
    ) -> [ScreenCapture] {
        timing?("captureAllScreensImmediately screens=\(context.screens.count)")
        return context.screens.enumerated().compactMap { index, screen in
            let cgRect = CGRect(
                x: screen.frame.origin.x,
                y: context.mainHeight - screen.frame.origin.y - screen.frame.height,
                width: screen.frame.width,
                height: screen.frame.height)
            timing?("CGWindowListCreateImage begin screen=\(index)")
            guard
                let image = CGWindowListCreateImage(
                    cgRect, .optionAll, kCGNullWindowID, .bestResolution
                )
            else {
                timing?("CGWindowListCreateImage failed screen=\(index)")
                return nil
            }
            timing?("CGWindowListCreateImage end screen=\(index) pixels=\(image.width)x\(image.height)")
            return ScreenCapture(screen: screen, image: image)
        }
    }

    /// SCScreenshotManager-based immediate capture (macOS 14+). Unlike
    /// `captureAllScreensImmediately` (which uses CGWindowListCreateImage and
    /// cannot exclude the WindowServer-composited cursor), SCK omits the cursor.
    /// Simple has no cursor-capture setting.
    ///
    /// On macOS 26+, first uses the rect-based screenshot API. That avoids
    /// enumerating SCShareableContent in the hot path, while still freezing
    /// trigger-time pixels before the overlay is ordered front. If that fails,
    /// falls back to the older content-filter path, which fetches fresh
    /// shareable content so transient UI present at hotkey time — open menus,
    /// Spotlight/Raycast panels — is in the window list and gets captured.
    /// Returns nil on any failure so the caller can fall back to the synchronous
    /// CGWindowListCreateImage path.
    @available(macOS 14.0, *)
    static func captureAllScreensImmediatelySCK(
        timing: (@Sendable (String) -> Void)? = nil
    ) async -> [ScreenCapture]? {
        let showsCursor = false
        if #available(macOS 26.0, *) {
            if let captures = await captureAllScreensImmediatelySCKRect(
                showsCursor: showsCursor,
                timing: timing
            ) {
                return captures
            }
        }

        timing?("SCK immediate: shareable content begin")
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
        else {
            timing?("SCK immediate: shareable content failed — fallback")
            return nil
        }
        timing?("SCK immediate: shareable content end displays=\(content.displays.count) windows=\(content.windows.count)")

        let screens = NSScreen.screens
        var pairs: [(SCDisplay, NSScreen)] = []
        for display in content.displays {
            if let screen = screens.first(where: { nsScreen in
                let screenNumber =
                    nsScreen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
                    as? CGDirectDisplayID
                return screenNumber == display.displayID
            }) {
                pairs.append((display, screen))
            }
        }
        guard !pairs.isEmpty else {
            timing?("SCK immediate: no display-screen pairs — fallback")
            return nil
        }

        let captures = await withTaskGroup(
            of: ScreenCapture?.self, returning: [ScreenCapture].self
        ) { group in
            for (index, pair) in pairs.enumerated() {
                let (display, screen) = pair
                group.addTask {
                    // Capture the whole display, excluding nothing: transient UI
                    // must be preserved. The cursor is controlled by showsCursor,
                    // not by the window list.
                    let filter = SCContentFilter(display: display, excludingWindows: [])
                    let config = SCStreamConfiguration()
                    let scale = Int(screen.backingScaleFactor)
                    config.width = display.width * scale
                    config.height = display.height * scale
                    config.showsCursor = showsCursor
                    config.captureResolution = .best
                    timing?("SCK immediate capture begin display=\(index)")
                    guard
                        let image = try? await SCScreenshotManager.captureImage(
                            contentFilter: filter, configuration: config)
                    else {
                        timing?("SCK immediate capture failed display=\(index)")
                        return nil
                    }
                    timing?("SCK immediate capture end display=\(index) pixels=\(image.width)x\(image.height)")
                    return ScreenCapture(screen: screen, image: image)
                }
            }
            var results: [ScreenCapture] = []
            for await capture in group { if let capture = capture { results.append(capture) } }
            return results
        }

        // If SCK couldn't produce an image for every display, fall back rather
        // than show a partial capture.
        guard captures.count == pairs.count else {
            timing?("SCK immediate: partial captures \(captures.count)/\(pairs.count) — fallback")
            return nil
        }
        return captures
    }

    @available(macOS 26.0, *)
    private static func captureAllScreensImmediatelySCKRect(
        showsCursor: Bool,
        timing: (@Sendable (String) -> Void)? = nil
    ) async -> [ScreenCapture]? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            timing?("SCK rect immediate: no screens — fallback")
            return nil
        }

        timing?("SCK rect immediate: begin screens=\(screens.count)")
        // SCScreenshotManager.captureScreenshot(rect:) takes CoreGraphics display
        // space: origin at the TOP-left of the primary display, y down. NSScreen
        // frames are AppKit space: origin at the BOTTOM-left of the primary, y up.
        // The two only coincide for the primary display — non-primary screens
        // captured with the raw AppKit frame come back vertically shifted with a
        // black stripe where the rect fell off the display (#291, #294).
        guard let primaryScreen = screens.first else { return [] }
        let primaryHeight = primaryScreen.frame.maxY
        let captures = await withTaskGroup(
            of: ScreenCapture?.self,
            returning: [ScreenCapture].self
        ) { group in
            for (index, screen) in screens.enumerated() {
                group.addTask {
                    let appKitFrame = screen.frame
                    let rect = CGRect(
                        x: appKitFrame.origin.x,
                        y: primaryHeight - appKitFrame.maxY,
                        width: appKitFrame.width,
                        height: appKitFrame.height)
                    let config = SCScreenshotConfiguration()
                    config.width = Int(rect.width * screen.backingScaleFactor)
                    config.height = Int(rect.height * screen.backingScaleFactor)
                    config.showsCursor = showsCursor
                    // Rectangle screenshots omit window framing by default on
                    // macOS 26. Preserve the shadows visible on the desktop.
                    config.ignoreShadows = false
                    config.displayIntent = .local
                    config.dynamicRange = .sdr
                    timing?("SCK rect capture begin screen=\(index) rect=\(Int(rect.origin.x)),\(Int(rect.origin.y)) \(Int(rect.width))x\(Int(rect.height))")
                    let result = await captureScreenshotOutput(rect: rect, configuration: config)
                    guard
                        result.error == nil,
                        let output = result.output,
                        let image = output.sdrImage ?? output.hdrImage
                    else {
                        let reason = result.error?.localizedDescription ?? "no image returned"
                        timing?("SCK rect capture failed screen=\(index) error=\(reason)")
                        return nil
                    }
                    timing?("SCK rect capture end screen=\(index) pixels=\(image.width)x\(image.height)")
                    return ScreenCapture(screen: screen, image: image)
                }
            }

            var results: [ScreenCapture] = []
            for await capture in group {
                if let capture { results.append(capture) }
            }
            return results
        }

        guard captures.count == screens.count else {
            timing?("SCK rect immediate: partial captures \(captures.count)/\(screens.count) — fallback")
            return nil
        }

        timing?("SCK rect immediate: end")
        return captures
    }

    @available(macOS 26.0, *)
    private static func captureScreenshotOutput(
        rect: CGRect,
        configuration: SCScreenshotConfiguration
    ) async -> (output: SCScreenshotOutput?, error: Error?) {
        await withCheckedContinuation { continuation in
            SCScreenshotManager.captureScreenshot(rect: rect, configuration: configuration) {
                output,
                error in
                continuation.resume(returning: (output, error))
            }
        }
    }

}
