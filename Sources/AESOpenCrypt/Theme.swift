import AESOpenCore
import AppKit
import SwiftUI

/// Presentation-only theme. The palette lives in AESOpenCore so its contrast
/// ratios are unit tested; this file maps it to dynamic AppKit colors.
enum Theme {
    static let canvas = color(light: ThemePalette.light.canvas, dark: ThemePalette.dark.canvas)
    static let surface = color(light: ThemePalette.light.surface, dark: ThemePalette.dark.surface)
    static let surfaceRaised = color(light: ThemePalette.light.surfaceRaised, dark: ThemePalette.dark.surfaceRaised)
    static let border = color(light: ThemePalette.light.border, dark: ThemePalette.dark.border)
    static let borderStrong = color(light: ThemePalette.light.borderStrong, dark: ThemePalette.dark.borderStrong)
    static let textPrimary = color(light: ThemePalette.light.textPrimary, dark: ThemePalette.dark.textPrimary)
    static let textSecondary = color(light: ThemePalette.light.textSecondary, dark: ThemePalette.dark.textSecondary)
    static let textTertiary = color(light: ThemePalette.light.textTertiary, dark: ThemePalette.dark.textTertiary)
    static let accent = color(light: ThemePalette.light.accent, dark: ThemePalette.dark.accent)
    static let accentFill = color(light: ThemePalette.light.accentFill, dark: ThemePalette.dark.accentFill)
    static let accentFillPressed = color(light: ThemePalette.light.accentFillPressed, dark: ThemePalette.dark.accentFillPressed)
    static let accentSoft = color(light: ThemePalette.light.accentSoft, dark: ThemePalette.dark.accentSoft)
    static let accentBorder = color(light: ThemePalette.light.accentBorder, dark: ThemePalette.dark.accentBorder)
    static let success = color(light: ThemePalette.light.success, dark: ThemePalette.dark.success)
    static let successSoft = color(light: ThemePalette.light.successSoft, dark: ThemePalette.dark.successSoft)
    static let warning = color(light: ThemePalette.light.warning, dark: ThemePalette.dark.warning)
    static let warningSoft = color(light: ThemePalette.light.warningSoft, dark: ThemePalette.dark.warningSoft)
    static let danger = color(light: ThemePalette.light.danger, dark: ThemePalette.dark.danger)
    static let dangerSoft = color(light: ThemePalette.light.dangerSoft, dark: ThemePalette.dark.dangerSoft)
    static let info = color(light: ThemePalette.light.info, dark: ThemePalette.dark.info)

    static let shadow = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return NSColor.black.withAlphaComponent(isDark ? 0.45 : 0.06)
    })

    enum Metrics {
        static let windowPadding: CGFloat = 24
        static let sectionSpacing: CGFloat = 16
        static let cardRadius: CGFloat = 16
        static let rowRadius: CGFloat = 10
        static let fieldRadius: CGFloat = 9
        static let iconTileRadius: CGFloat = 12
    }

    private static func color(light: ThemeRGB, dark: ThemeRGB) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return nsColor(isDark ? dark : light)
        })
    }

    private static func nsColor(_ rgb: ThemeRGB) -> NSColor {
        NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
    }
}
