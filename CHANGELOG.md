# Changelog

## 0.2.4 — 2026-11-10 (capture focus and lifecycle)

跨屏移动鼠标时更新截图窗口焦点和光标，非活动截图窗口接受首次拖选，并保留原生文字编辑。取消、复制、保存和进入长截图时释放普通截图画布及像素；新增生命周期回归测试与可选本机诊断。

Update capture focus and cursor on display entry, accept the first drag in inactive capture windows, and preserve native text editing. Release ordinary capture canvases and pixels on cancellation, copy, successful save and transition to long capture. Add lifecycle regression tests and opt-in local diagnostics.

Release packages retain the previous stable Apple signing identity and remain **not notarized**. Local notes are excluded from Git and source archives. The reported memory fluctuation was not reproduced; this release does not claim to resolve its root cause.

## 0.2.3 — 2026-11-09 (double-click copy anywhere)

Double-click anywhere on the screenshot canvas to copy and finish, including outside the selection and while an annotation tool is active. Clicking outside the selection keeps it; dragging starts a new selection and clears annotations. Double-clicking existing text still selects the word, and marked (composing) text does not trigger a copy.

Release DMGs now require a stable code-signing identity and refuse ad-hoc signing, so Screen Recording consent can survive updates/reinstalls with the same identity. The current preview is not notarized; changing identity may require one fresh permission grant.

## 0.2.2 — 2026-10-12 (menu and capture stability)

Keep the status menu compact and aligned with the About panel's opaque light surface.
Starting a screenshot from the global hotkey leaves the open menu or About panel in place,
without dimming its captured pixels. Keep the About panel light and consistent with the menu.

## 0.2.1 — 2026-10-11 (hotkey and About window)

Keep the global screenshot shortcut responsive while the status menu is open.
Make About a nonmodal panel so screenshot selection remains usable while it is shown.
Release as a macOS preview for Apple Silicon and Intel, with source and checksums.

## 0.2.0 — 2026-10-07 (long screenshot preview)

Manual vertical long screenshots (macOS 14+), continuous region capture, an eight-frame
buffer, content-edge overlap validation, compatible still-capture fallback, and a
scrollable result reusing the six annotation tools.
One-pixel scrolling, tolerance for small local changes, and delayed recovery guidance
reduce transient overlap failures. Fix completion/cancellation delivery, bounded stream
handoff, initial viewport limits, partial-result reporting and failed mosaic exports.
Remove unused helpers and redundant pixel conversion. Enable size optimization,
dead-code stripping and compact DMG packaging; installers are about 1.32/1.33 MB.
No event injection, third-party dependency or additional entitlement.

## 0.1.2 — 2026-10-07 (new app icon)

Original minimal screenshot-selection icon replaces the upstream shutter icon.
Off-white tile, charcoal corner brackets and a green selection handle.
All macOS icon sizes updated; screenshot behavior and permissions unchanged.

## 0.1.1 — 2026-10-07 (design refinement)

Consistent outline icons, restrained paper surfaces and clear selected/hover/press states.
Selected stroke widths and colors have explicit rings. Main toolbar remains anchored
when options open above or below a selection. Annotation colors are fixed across
system themes. Settings use native typography and an explicit shortcut recording state.
No new features, permissions, runtime dependencies or selection animations.

## 0.1.0 — 2026-10-07 (development preview)

Screenshot-only extraction of MacShot v4.3.0. Keeps window preview, manual selection,
six annotations, fixed stroke widths, colors, undo/redo, PNG save and clipboard output.
Removes recording, network integrations, history, OCR, translation, scrolling,
beautification, standalone editors, automatic updates and external packages.

The earlier 4.3.0-simple.1–4 prototypes changed the full upstream application.
This source tree contains the smaller independent screenshot implementation.
