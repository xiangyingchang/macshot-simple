# Changelog

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
