import Foundation
import Testing

@testable import Unlatch

/// WCAG 2 contrast ratio between two sRGB colors.
private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
    func luminance(_ hex: UInt32) -> Double {
        let channels = [hex >> 16, hex >> 8, hex].map { channel -> Double in
            let value = Double(channel & 0xFF) / 255
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2]
    }
    let (a, b) = (luminance(first), luminance(second))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
}

struct PopoverPaletteTests {
    @Test func contrastMatchesKnownValues() {
        #expect(abs(contrast(0xFFFFFF, 0x000000) - 21) < 0.001)
        #expect(contrast(0x777777, 0x777777) == 1)
    }

    @Test(arguments: [RowTone.neutral, .success, .warning, .error])
    func badgeGlyphIsReadable(_ tone: RowTone) {
        #expect(contrast(0xFFFFFF, PopoverPalette.badgeFill(tone)) >= 4.5)
    }

    /// Backgrounds are estimates, since the real popover is vibrant: plain, and the tinted file list.
    @Test(arguments: [UInt32(0xFFFFFF), 0xECECEC, 0xE6E6E6])
    func errorTextIsReadableInLightMode(_ background: UInt32) {
        #expect(contrast(PopoverPalette.errorTextLight, background) >= 4.5)
    }

    @Test(arguments: [UInt32(0x1E1E1E), 0x323232, 0x3A3A3A])
    func errorTextIsReadableInDarkMode(_ background: UInt32) {
        #expect(contrast(PopoverPalette.errorTextDark, background) >= 4.5)
    }
}

struct DestinationOptionMoveTests {
    @Test func arrowsStepThroughOptionsAndStopAtTheEnds() {
        #expect(DestinationOption.suffix.moved(by: 1) == .replace)
        #expect(DestinationOption.desktop.moved(by: 1) == .other)
        #expect(DestinationOption.replace.moved(by: -1) == .suffix)
        #expect(DestinationOption.suffix.moved(by: -1) == .suffix)
        #expect(DestinationOption.other.moved(by: 1) == .other)
    }
}
