# MacShot Simple development

Screenshot-only fork of sw33tLie/macshot v4.3.0, GPL-3.0. No third-party packages.
The old full application is not part of this source tree.

## Scope

Keep: multi-display screen capture, window hover preview, selection/move/eight-handle resize,
six annotations (rectangle, ellipse, arrow, pencil, pixelate, text), three stroke widths,
six colors, undo/redo, clipboard and PNG save, one configurable global hotkey.
Do not reintroduce recording, uploads, OCR, history, standalone editors or updates incidentally.

## Architecture

- AppDelegate owns menu, hotkey, capture windows, permission errors and output.
- ScreenCaptureManager preserves upstream ScreenCaptureKit paths and a permission-gated CoreGraphics fallback.
- CaptureGeometry handles bottom-left AppKit to top-left screenshot-pixel conversions.
- CaptureCanvas owns selection gestures and a native NSTextView for text/IME input.
- AnnotationRenderer produces one composite for both preview and output. Mosaic must read already-composited pixels.
- CaptureToolbar uses native NSButton subclasses; options are fixed choices, never sliders.
- UserDefaults stores only preferences, not screenshots or history.

## Rules

Read relevant source before editing. Preserve user changes and stay in scope.
All UI/state mutations run on the main actor. No network clients, telemetry or new permissions.
Use KeyboardShortcutMatcher for character commands, physical key codes only for global hotkey storage and non-character keys.
Retain pixel data and crop coordinates at original screen scale; do not accidentally export the dimming mask or handles.
Do not use `NSApp.hide`: it can suspend Carbon global hotkeys. Return focus centrally in AppDelegate.
Native text editing must preserve Chinese input and marked text before interpreting Return.
Use one compositing implementation for live annotation display and output.
Do not fallback to raw screenshots if annotation rendering fails during output.
Keep menus, tool controls and labels readable in light and dark system appearance.
Do not persist screenshot pixels during tests or diagnostics of real screens.
Keep signed identity and machine-specific paths out of source. Signing identity comes from an environment variable.

## Validation

`scripts/run-tests.sh`: headless XCTest target compiles app sources except main.swift.
Tests cover behavior, geometry and actual raster output; do not mirror implementation details.
`scripts/build-simple.sh`: Release build catches strict concurrency issues.
`SIMPLE_ARCHS='arm64 x86_64' scripts/build-simple.sh`: universal build.
`--check-capture`: optional installed-app diagnostic, no clipboard change or persisted screen pixels.
Report tests/build/install separately from real mouse, input-method and multi-monitor acceptance.

Do not commit, push, publish, change signing identity or reset permissions without task authorization.
