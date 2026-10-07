# MacShot Simple

[中文](README.md) | English

A small macOS menu bar app for screenshots and basic annotations. Derived from [sw33tLie/macshot v4.3.0](https://github.com/sw33tLie/macshot/tree/v4.3.0), built with Swift, AppKit and system capture APIs. No third-party dependencies.

Version 0.2.0 is a development preview. Source and macOS preview downloads are available; notarized installers are not available yet. The interface currently uses Chinese labels.

## Download and install

Download the matching `.dmg` from [Releases](https://github.com/xiangyingchang/macshot-simple/releases): Apple Silicon (M-series) or Intel. Check About This Mac for your chip. Open the disk image and drag the app into Applications.

Version 0.2.0 installers are approximately **1.32 MB (Apple Silicon) / 1.33 MB (Intel)**.

Preview packages are ad hoc signed and **not notarized**. macOS may block first opening; review Open Anyway in System Settings → Privacy & Security. Do not disable system security. The deployment target is macOS 12.3, but older systems and Apple Silicon device runtime acceptance remain unverified.

**macOS only. There is no Windows build.** Windows requires a separate port of capture, UI and hotkey implementations.

## Use

1. Open the app and grant Screen Recording permission in System Settings.
2. Press `⌘⇧X`, or choose Screenshot from the menu bar. The menu shows your current shortcut; existing preferences are preserved.
3. Hover to preview a window. Click to select it, or drag to select a region.
4. Drag inside the selection to move it; drag any of the eight handles to resize. Choose an annotation tool. Click the selected tool again to return to selection mode.
5. Click the green checkmark to copy and finish, or the save button to export PNG.

Six tools: rectangle, ellipse, arrow, pencil, pixelate and text. Three stroke widths, six colors, undo and redo. One configurable global shortcut.

- `Esc`: cancel; while editing text, cancel the current text first.
- `Enter`: copy and finish; while editing text, confirm text first. `Shift+Enter` inserts a newline.
- `⌘C`: copy and finish. `⌘S`: save. `⌘Z` / `⌘⇧Z`: undo / redo. Native editing shortcuts apply while typing text.
- Right-click: return to region selection, or exit if no region is selected.
- Double-click the selection in selection mode: copy and finish.

Each display has its own canvas; a selection stays on one display. Output preserves the original screenshot pixel resolution, without downscaling. The size label reports output pixels. On a 2× Retina display, a 500 × 300 point region produces approximately 1000 × 600 pixels, with crop edges rounded to pixel boundaries. PNG export is lossless.

No recording, uploads, accounts, history, OCR, translation, pinned screenshots, beautification, automatic updates or standalone image editor. Interaction is inspired by common chat screenshot tools; exact WeChat or Feishu parity is not claimed.

## Long screenshots (0.2.0)

Requires macOS 14+. Select a scrollable region before adding annotations, click the long screenshot button, wait until ready, then scroll downward without pausing after each movement. Continuous capture buffers intermediate frames; avoid jumping a full viewport, as adjacent captured frames still need roughly one quarter overlap. Click Finish to annotate the scrollable result, copy, or save.

On macOS 26, leave roughly 60 points above or below the selection for the floating controls. Avoid sticky controls, navigation bars and video when possible. Basic fixed headers/footers are retained once; complex dynamic or repeating content may not match. Single-frame mismatches are retried; recovery guidance appears after about 0.8 seconds of persistent failure. Roll back to captured content if prompted. One-pixel movements and small local visual changes are supported. Upward scrolling adds nothing. Limits: 20,000 pixels tall and 40 million pixels total. A partial result is preserved and its title states the reason when capture cannot continue.

No automatic scrolling or added Accessibility permission. Stitching stays in memory. Preview downloads for 0.2.0 are available. See [the plan and research](docs/LONG-CAPTURE.md).

## Build

Requires macOS 12.3 or later and Xcode with the macOS 26 SDK. New capture APIs are guarded by availability checks. No additional packages need downloading.

```sh
git clone https://github.com/xiangyingchang/macshot-simple.git
cd macshot-simple
scripts/build-simple.sh
open 'build/Build/Products/Release/MacShot Simple.app'
```

The default build uses the local architecture and ad hoc signing. To build for Intel and Apple Silicon:

```sh
SIMPLE_ARCHS='arm64 x86_64' scripts/build-simple.sh
```

To sign with your own developer certificate:

```sh
SIMPLE_SIGNING_IDENTITY='Your signing identity' scripts/build-simple.sh
```

Alternatively, open `macshot.xcodeproj` in Xcode, select the `macshot` scheme and configure your signing team. The default bundle identifier is `local.macshot.simple`; choose your own for distribution. Changing the identifier or signing identity may require granting Screen Recording permission again.

The build script does not install, publish or change system permissions. Ad hoc builds are not notarized and may require approval in System Settings. A consumer distribution needs developer signing and notarization.

## Verification

```sh
scripts/run-tests.sh
```

Headless tests cover selection geometry, Retina cropping, annotation raster output, pixelation, undo/redo, stroke choices and toolbar appearance. Version 0.2.0 passed 40 Release-mode tests and a universal build. A controlled native text window with continuous variable-speed scrolling also passed. This does not establish manual mouse/IME acceptance, chat paste behavior, real multi-display behavior, or runtime compatibility on every supported macOS version and Apple Silicon device. See [RELEASE-READINESS.md](RELEASE-READINESS.md).

After quitting the running app, an optional local capture diagnostic is available:

```sh
'build/Build/Products/Release/MacShot Simple.app/Contents/MacOS/MacShot Simple' --check-capture
```

It captures screens, renders annotations and encodes PNG/TIFF in memory. It prints screen counts, dimensions and success metadata only, without saving screen images or changing the clipboard. It may trigger a system Screen Recording permission prompt.

## Source layout

- `macshot/Capture/ScreenCaptureManager.swift`: upstream-derived capture engine, with compatibility paths.
- `macshot/Capture/ScrollCaptureSession.swift`, `ScrollFrameStream.swift`, `ScrollStitcher.swift`: continuous region capture, bounded buffers, fallback and stitching.
- `macshot/UI/LongCaptureReview.swift`: scrollable long-image annotations and export.
- `macshot/Model/CaptureGeometry.swift`: selection geometry and pixel cropping.
- `macshot/Model/Annotation.swift`: six tools, rendering and undo history.
- `macshot/UI/CaptureCanvas.swift`: selection gestures and native text editing.
- `macshot/UI/CaptureToolbar.swift`: tools, width choices and colors.
- `macshot/UI/DesignTheme.swift`: shared visual constants; see [DESIGN.md](DESIGN.md).
- `macshot/Services/`: hotkey, keyboard layout matching, preferences and diagnostics.
- `macshot/AppDelegate.swift`: menu bar, capture lifecycle, clipboard and saving.

## Privacy, contributions and license

Screenshots stay on your Mac. The app has no upload feature, network client entitlement or telemetry. See [PRIVACY.md](PRIVACY.md).

Report bugs through [Issues](https://github.com/xiangyingchang/macshot-simple/issues). See [CONTRIBUTING.md](CONTRIBUTING.md) for contributions and [SECURITY.md](SECURITY.md) for private security reports.

This is an independently maintained modification of MacShot, licensed under GPL-3.0. Upstream author sw33tLie and contributors retain their attribution. The capture engine and keyboard layout handling derive from upstream. The current app icon was created for MacShot Simple. See [LICENSE](LICENSE) and [NOTICE](NOTICE). This is not an official MacShot, WeChat or Feishu release.
