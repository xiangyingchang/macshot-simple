// MacShot Simple, GPL-3.0. Modified 2026-10-07.
import Cocoa

/// Quiet paper chrome around a green selection. Keep annotation colors fixed
/// so a red stroke never changes hue when the system appearance changes.
enum DesignTheme {
    static func color(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                green: CGFloat((hex >> 8) & 255) / 255,
                blue: CGFloat(hex & 255) / 255, alpha: 1)
    }
    static let paper = color(0xFAFAFA)
    static let ink = color(0x34363B)
    static let muted = color(0x8B8F96)
    static let divider = color(0xE1E3E6)
    static let hover = color(0xECEEF0)
    static let green = color(0x00C878)
    static let red = color(0xFF565B)
    static let mainHeight: CGFloat = 44
    static let optionsHeight: CGFloat = 36
    static let rowGap: CGFloat = 6
    static let expandedHeight = mainHeight + optionsHeight + rowGap
    static let iconSize: CGFloat = 18
    static let iconStroke: CGFloat = 1.55
    static var increasedContrast: Bool { NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast }
    static var border: NSColor { increasedContrast ? ink : divider }
}
