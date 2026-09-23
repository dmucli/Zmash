import CoreText
import SwiftUI

/// The design system's few tokens for the targets that can't see the app's `Design` (the widgets, the Live Activity
/// and the Watch, D119): the tarmac and bone ramp, vermilion and team blue, bib numerals and mono labels.
/// The fonts are bundled in each target (UIAppFonts).
enum Brand {
    static let vermilion = Color(red: 0xE8 / 255, green: 0x54 / 255, blue: 0x33 / 255)
    static let teamBlue = Color(red: 0x00 / 255, green: 0x8E / 255, blue: 0xF9 / 255)
    static let go = Color(red: 0x53 / 255, green: 0xBE / 255, blue: 0x70 / 255)
    static let caution = Color(red: 0xE9 / 255, green: 0xAB / 255, blue: 0x2B / 255)
    static let bone = Color(red: 0xF4 / 255, green: 0xF1 / 255, blue: 0xEC / 255)
    static let bone2 = Color(red: 0xA8 / 255, green: 0xA3 / 255, blue: 0x96 / 255)
    static let stone = Color(red: 0x8E / 255, green: 0x89 / 255, blue: 0x7D / 255)
    static let tarmac = Color(red: 0x12 / 255, green: 0x11 / 255, blue: 0x10 / 255)
    static let tarmac850 = Color(red: 0x1C / 255, green: 0x1B / 255, blue: 0x19 / 255)
    static let tarmac700 = Color(red: 0x3A / 255, green: 0x37 / 255, blue: 0x32 / 255)
    static let blockRest = Color(red: 0x4A / 255, green: 0x47 / 255, blue: 0x40 / 255)

    /// Race-bib numerals: Archivo at 62 % width.
    static func bib(_ size: CGFloat, weight: Double = 800) -> Font {
        variable("ArchivoRoman-Thin", size, axes: [2003265652: weight, 2003072104: 62])
    }

    /// Archivo text.
    static func sans(_ size: CGFloat, weight: Double = 500) -> Font {
        variable("ArchivoRoman-Thin", size, axes: [2003265652: weight, 2003072104: 100])
    }

    /// JetBrains Mono, for labels and clocks.
    static func mono(_ size: CGFloat, weight: Double = 500) -> Font {
        variable("JetBrainsMonoRoman-Thin", size, axes: [2003265652: weight])
    }

    private static func variable(_ name: String, _ size: CGFloat, axes: [Int: Double]) -> Font {
        let attributes: [CFString: Any] = [kCTFontNameAttribute: name, kCTFontVariationAttribute: axes]
        let descriptor = CTFontDescriptorCreateWithAttributes(attributes as CFDictionary)
        return Font(CTFontCreateWithFontDescriptor(descriptor, size, nil))
    }
}

extension View {
    /// The mono label: uppercase, +0.14 em.
    func brandLabel(_ size: CGFloat = 11) -> some View {
        font(Brand.mono(size)).tracking(size * 0.14).textCase(.uppercase)
    }
}
