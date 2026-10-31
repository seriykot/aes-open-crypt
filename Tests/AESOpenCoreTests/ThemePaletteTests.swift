import XCTest
import AESOpenCore

final class ThemePaletteTests: XCTestCase {
    func testLightPaletteMeetsContrastRequirements() {
        assertContrast(ThemePalette.light)
    }

    func testDarkPaletteMeetsContrastRequirements() {
        assertContrast(ThemePalette.dark)
    }

    func testEveryComponentIsInGamut() {
        for palette in [ThemePalette.light, ThemePalette.dark] {
            for color in palette.allColors {
                XCTAssertGreaterThanOrEqual(color.red, 0)
                XCTAssertLessThanOrEqual(color.red, 1)
                XCTAssertGreaterThanOrEqual(color.green, 0)
                XCTAssertLessThanOrEqual(color.green, 1)
                XCTAssertGreaterThanOrEqual(color.blue, 0)
                XCTAssertLessThanOrEqual(color.blue, 1)
            }
        }
    }

    private func assertContrast(_ palette: ThemePalette) {
        let white = ThemeRGB(red: 1, green: 1, blue: 1)

        XCTAssertGreaterThanOrEqual(palette.textPrimary.contrastRatio(with: palette.canvas), 7)
        XCTAssertGreaterThanOrEqual(palette.textPrimary.contrastRatio(with: palette.surface), 7)

        XCTAssertGreaterThanOrEqual(palette.textSecondary.contrastRatio(with: palette.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(palette.textSecondary.contrastRatio(with: palette.surface), 4.5)

        XCTAssertGreaterThanOrEqual(palette.textTertiary.contrastRatio(with: palette.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(palette.textTertiary.contrastRatio(with: palette.surface), 4.5)

        XCTAssertGreaterThanOrEqual(palette.accent.contrastRatio(with: palette.canvas), 4.5)
        XCTAssertGreaterThanOrEqual(palette.accent.contrastRatio(with: palette.surface), 4.5)
        XCTAssertGreaterThanOrEqual(palette.accent.contrastRatio(with: palette.accentSoft), 4.5)

        XCTAssertGreaterThanOrEqual(palette.accentFill.contrastRatio(with: palette.canvas), 3)
        XCTAssertGreaterThanOrEqual(white.contrastRatio(with: palette.accentFill), 4.5)

        XCTAssertGreaterThanOrEqual(palette.success.contrastRatio(with: palette.surface), 4.5)
        XCTAssertGreaterThanOrEqual(palette.success.contrastRatio(with: palette.successSoft), 4.5)

        XCTAssertGreaterThanOrEqual(palette.warning.contrastRatio(with: palette.surface), 4.5)
        XCTAssertGreaterThanOrEqual(palette.warning.contrastRatio(with: palette.warningSoft), 4.5)

        XCTAssertGreaterThanOrEqual(palette.danger.contrastRatio(with: palette.surface), 4.5)
        XCTAssertGreaterThanOrEqual(palette.danger.contrastRatio(with: palette.dangerSoft), 4.5)
    }
}
