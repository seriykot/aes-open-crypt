import Foundation

/// One sRGB color as components in 0...1, plus WCAG contrast helpers.
public struct ThemeRGB: Equatable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double

    public init(red: Double, green: Double, blue: Double) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }

    /// WCAG 2.x relative luminance.
    public var relativeLuminance: Double {
        0.2126 * ThemeRGB.linear(red)
            + 0.7152 * ThemeRGB.linear(green)
            + 0.0722 * ThemeRGB.linear(blue)
    }

    /// WCAG 2.x contrast ratio, 1...21.
    public func contrastRatio(with other: ThemeRGB) -> Double {
        let first = relativeLuminance
        let second = other.relativeLuminance
        let high = max(first, second)
        let low = min(first, second)
        return (high + 0.05) / (low + 0.05)
    }

    private static func linear(_ component: Double) -> Double {
        component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
    }
}

/// The muted ink and sage palette used by the app. Light and dark values are
/// chosen to meet WCAG AA for text and the 3:1 rule for UI components.
public struct ThemePalette: Equatable, Sendable {
    public let canvas: ThemeRGB
    public let surface: ThemeRGB
    public let surfaceRaised: ThemeRGB
    public let border: ThemeRGB
    public let borderStrong: ThemeRGB
    public let textPrimary: ThemeRGB
    public let textSecondary: ThemeRGB
    public let textTertiary: ThemeRGB
    public let accent: ThemeRGB
    public let accentFill: ThemeRGB
    public let accentFillPressed: ThemeRGB
    public let accentSoft: ThemeRGB
    public let accentBorder: ThemeRGB
    public let success: ThemeRGB
    public let successSoft: ThemeRGB
    public let warning: ThemeRGB
    public let warningSoft: ThemeRGB
    public let danger: ThemeRGB
    public let dangerSoft: ThemeRGB
    public let info: ThemeRGB

    public init(
        canvas: ThemeRGB,
        surface: ThemeRGB,
        surfaceRaised: ThemeRGB,
        border: ThemeRGB,
        borderStrong: ThemeRGB,
        textPrimary: ThemeRGB,
        textSecondary: ThemeRGB,
        textTertiary: ThemeRGB,
        accent: ThemeRGB,
        accentFill: ThemeRGB,
        accentFillPressed: ThemeRGB,
        accentSoft: ThemeRGB,
        accentBorder: ThemeRGB,
        success: ThemeRGB,
        successSoft: ThemeRGB,
        warning: ThemeRGB,
        warningSoft: ThemeRGB,
        danger: ThemeRGB,
        dangerSoft: ThemeRGB,
        info: ThemeRGB
    ) {
        self.canvas = canvas
        self.surface = surface
        self.surfaceRaised = surfaceRaised
        self.border = border
        self.borderStrong = borderStrong
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.accentFill = accentFill
        self.accentFillPressed = accentFillPressed
        self.accentSoft = accentSoft
        self.accentBorder = accentBorder
        self.success = success
        self.successSoft = successSoft
        self.warning = warning
        self.warningSoft = warningSoft
        self.danger = danger
        self.dangerSoft = dangerSoft
        self.info = info
    }

    public static let light = ThemePalette(
        canvas: ThemeRGB(hex: 0xF4F6F3),
        surface: ThemeRGB(hex: 0xFBFCFA),
        surfaceRaised: ThemeRGB(hex: 0xFFFFFF),
        border: ThemeRGB(hex: 0xD9DFDB),
        borderStrong: ThemeRGB(hex: 0xC4CCC7),
        textPrimary: ThemeRGB(hex: 0x1C2523),
        textSecondary: ThemeRGB(hex: 0x5A6864),
        textTertiary: ThemeRGB(hex: 0x5F6C68),
        accent: ThemeRGB(hex: 0x3D6E68),
        accentFill: ThemeRGB(hex: 0x35635D),
        accentFillPressed: ThemeRGB(hex: 0x2C534E),
        accentSoft: ThemeRGB(hex: 0xE2ECE9),
        accentBorder: ThemeRGB(hex: 0xB6CBC6),
        success: ThemeRGB(hex: 0x356B4A),
        successSoft: ThemeRGB(hex: 0xE2EEE6),
        warning: ThemeRGB(hex: 0x8A5F1F),
        warningSoft: ThemeRGB(hex: 0xF3EADB),
        danger: ThemeRGB(hex: 0xA24A44),
        dangerSoft: ThemeRGB(hex: 0xF4E5E3),
        info: ThemeRGB(hex: 0x4A657F)
    )

    public static let dark = ThemePalette(
        canvas: ThemeRGB(hex: 0x121715),
        surface: ThemeRGB(hex: 0x1A211F),
        surfaceRaised: ThemeRGB(hex: 0x222A27),
        border: ThemeRGB(hex: 0x313A36),
        borderStrong: ThemeRGB(hex: 0x3F4A45),
        textPrimary: ThemeRGB(hex: 0xE8EDEA),
        textSecondary: ThemeRGB(hex: 0xA6B2AE),
        textTertiary: ThemeRGB(hex: 0x8B9793),
        accent: ThemeRGB(hex: 0x79ACA5),
        accentFill: ThemeRGB(hex: 0x3F716B),
        accentFillPressed: ThemeRGB(hex: 0x35635D),
        accentSoft: ThemeRGB(hex: 0x22302D),
        accentBorder: ThemeRGB(hex: 0x3E5651),
        success: ThemeRGB(hex: 0x7BB28F),
        successSoft: ThemeRGB(hex: 0x1E2E24),
        warning: ThemeRGB(hex: 0xCBA463),
        warningSoft: ThemeRGB(hex: 0x2E2619),
        danger: ThemeRGB(hex: 0xCB837B),
        dangerSoft: ThemeRGB(hex: 0x2F211F),
        info: ThemeRGB(hex: 0x8FA9C2)
    )

    public var allColors: [ThemeRGB] {
        [
            canvas, surface, surfaceRaised, border, borderStrong,
            textPrimary, textSecondary, textTertiary,
            accent, accentFill, accentFillPressed, accentSoft, accentBorder,
            success, successSoft, warning, warningSoft, danger, dangerSoft, info,
        ]
    }
}
