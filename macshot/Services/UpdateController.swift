// MacShot Simple, GPL-3.0. Added 2026-11-10: opt-out in-app updates via Sparkle 2.
import Cocoa
import Sparkle

/// Update state exposed to the status menu. Only version strings, never feed contents.
enum UpdateState: Equatable {
    case idle
    case available(version: String)

    var availableVersion: String? {
        if case .available(let version) = self { return version }
        return nil
    }
}

/// Selects the appcast for the machine's CPU, not the running slice: an Intel
/// build running under Rosetta migrates to the Apple silicon package.
enum UpdateFeed {
    static let base = "https://github.com/xiangyingchang/macshot-simple/releases/latest/download/"

    static func feedURLString(appleSilicon: Bool) -> String {
        base + (appleSilicon ? "appcast-arm64.xml" : "appcast-x86_64.xml")
    }

    static var hostIsAppleSilicon: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("hw.optional.arm64", &value, &size, nil, 0) == 0 && value == 1
    }

    #if DEBUG
    /// Debug-only local acceptance hook. Release builds compile this out, so
    /// a shipped app cannot be redirected through user defaults.
    static let debugOverrideKey = "debugUpdateFeedURL"
    #endif

    static var current: String {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: debugOverrideKey), !override.isEmpty {
            return override
        }
        #endif
        return feedURLString(appleSilicon: hostIsAppleSilicon)
    }
}

/// Owns Sparkle. Uses gentle reminders: scheduled finds only badge the menu bar
/// icon; the Sparkle window appears when the user picks the update row.
final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    private(set) var state: UpdateState = .idle {
        didSet { if state != oldValue { onStateChange?(state) } }
    }
    var onStateChange: ((UpdateState) -> Void)?
    /// Called before Sparkle presents a window, so AppDelegate can record focus.
    var onWillShowUpdateWindow: (() -> Void)?
    /// Called when Sparkle's window session ends, so focus returns centrally.
    var onSessionFinished: (() -> Void)?
    private var controller: SPUStandardUpdaterController?

    func start() {
        guard controller == nil else { return }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
        #if DEBUG
        // Acceptance evidence: preferences that must survive an in-place update.
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: "debugPersistCurrentHotkey") {
            let key = SimpleSettings.hotkey
            SimpleSettings.saveHotkey(key: key.key, modifiers: key.modifiers)
        }
        NSLog("MACSHOT_DEBUG launch build=%@ hotkeyStored=%@ hotkey=%@ autoChecks=%@ screenPreflight=%@",
              Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?",
              defaults.object(forKey: "hotkeyKeyCode") == nil ? "false" : "true",
              SimpleSettings.hotkeyDescription,
              automaticallyChecksForUpdates ? "true" : "false",
              CGPreflightScreenCaptureAccess() ? "true" : "false")
        onStateChange = { [previous = onStateChange] state in
            NSLog("MACSHOT_DEBUG updateState=%@", String(describing: state))
            previous?(state)
        }
        // Local acceptance runs must not wait for the daily schedule.
        if UserDefaults.standard.string(forKey: UpdateFeed.debugOverrideKey)?.isEmpty == false {
            controller?.updater.checkForUpdatesInBackground()
        }
        #endif
    }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set { controller?.updater.automaticallyChecksForUpdates = newValue }
    }

    func checkForUpdates() {
        guard let controller, controller.updater.canCheckForUpdates else { return }
        onWillShowUpdateWindow?()
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    // MARK: SPUUpdaterDelegate

    func feedURLString(for updater: SPUUpdater) -> String? { UpdateFeed.current }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        state = .available(version: item.displayVersionString)
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        #if DEBUG
        NSLog("MACSHOT_DEBUG noUpdateFound")
        #endif
        state = .idle
    }

    #if DEBUG
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        NSLog("MACSHOT_DEBUG updateAborted %@", (error as NSError).localizedDescription)
    }
    #endif

    #if DEBUG
    /// Debug-only unattended acceptance: when automatic downloads are enabled,
    /// install and relaunch immediately through Sparkle's normal installer path.
    static let debugInstallImmediatelyKey = "debugInstallUpdateImmediately"

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        guard UserDefaults.standard.bool(forKey: Self.debugInstallImmediatelyKey) else { return false }
        immediateInstallHandler()
        return true
    }
    #endif

    // MARK: SPUStandardUserDriverDelegate

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // A menu bar app should never pop a window over the user's work.
        false
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        self.state = .available(version: update.displayVersionString)
    }

    func standardUserDriverWillFinishUpdateSession() {
        // Keep the badge if the user dismissed without installing; a later
        // check clears it through updaterDidNotFindUpdate.
        DispatchQueue.main.async { [weak self] in self?.onSessionFinished?() }
    }
}

/// Menu bar glyph with an optional availability dot. Stays a template image so
/// the system tints it correctly in light, dark and increased-contrast menus.
enum StatusIcon {
    static func image(badged: Bool) -> NSImage? {
        guard let base = NSImage(systemSymbolName: "viewfinder", accessibilityDescription: "MacShot Simple") else { return nil }
        guard badged else { return base }
        let size = base.size
        let image = NSImage(size: size, flipped: false) { rect in
            base.draw(in: rect)
            let diameter = max(5, rect.width * 0.36)
            let dot = NSRect(x: rect.maxX - diameter, y: rect.maxY - diameter, width: diameter, height: diameter)
            // Clear a ring around the dot so it separates from the glyph.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.2, dy: -1.2)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "MacShot Simple，有可用更新"
        return image
    }
}
