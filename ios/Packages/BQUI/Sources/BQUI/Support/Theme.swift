import SwiftUI
import UIKit

// Design tokens mirrored from prototype/css/app.css (`:root` and `[data-theme="dark"] .screen`).
// Colours follow light/dark mode and get stronger variants with Increase Contrast.

private func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> UIColor {
    UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

private func dynamic(_ light: UIColor, _ dark: UIColor, contrastLight: UIColor? = nil, contrastDark: UIColor? = nil) -> Color {
    Color(uiColor: UIColor { traits in
        let isDark = traits.userInterfaceStyle == .dark
        if traits.accessibilityContrast == .high {
            return isDark ? (contrastDark ?? dark) : (contrastLight ?? light)
        }
        return isDark ? dark : light
    })
}

enum BQColor {
    // Neutrals
    static let label = dynamic(rgb(0x0B0B0F), rgb(0xF5F5F7))
    static let label2 = dynamic(rgb(0x3C3C43, 0.64), rgb(0xEBEBF5, 0.64),
                                contrastLight: rgb(0x3C3C43, 0.86), contrastDark: rgb(0xEBEBF5, 0.86))
    static let label3 = dynamic(rgb(0x3C3C43, 0.34), rgb(0xEBEBF5, 0.32),
                                contrastLight: rgb(0x3C3C43, 0.6), contrastDark: rgb(0xEBEBF5, 0.6))
    static let fill = dynamic(rgb(0x787880, 0.12), rgb(0x787880, 0.24),
                              contrastLight: rgb(0x787880, 0.2), contrastDark: rgb(0x787880, 0.34))
    static let fill2 = dynamic(rgb(0x787880, 0.2), rgb(0x787880, 0.36))
    static let background = dynamic(rgb(0xF2F2F7), rgb(0x000000))
    static let card = dynamic(rgb(0xFFFFFF), rgb(0x1C1C1E))
    static let card2 = dynamic(rgb(0xF7F7FA), rgb(0x2C2C2E), contrastLight: rgb(0xEDEDF2), contrastDark: rgb(0x38383A))
    static let separator = dynamic(rgb(0x3C3C43, 0.14), rgb(0x545458, 0.6),
                                   contrastLight: rgb(0x3C3C43, 0.3), contrastDark: rgb(0x545458, 0.9))

    // Accent
    static let tint = dynamic(rgb(0x0A84FF), rgb(0x0A84FF), contrastLight: rgb(0x0060DF), contrastDark: rgb(0x409CFF))
    /// Tinted text on grey fills (`.btn-secondary`, link buttons); lighter in dark mode for contrast.
    static let tintText = dynamic(rgb(0x0A7AEF), rgb(0x4DA3FF), contrastLight: rgb(0x0060DF), contrastDark: rgb(0x7DBBFF))

    /// Solid toast background (`.toast.solid`).
    static let toast = Color(uiColor: rgb(0x1E1E20, 0.94))
    /// "Paper" of the plain-text note card.
    static let notePaper = dynamic(rgb(0xFFFBE6), rgb(0x2C2610))
    static let noteInk = dynamic(rgb(0x3B3000), rgb(0xFBEEC2))
    static let noteMark = Color(uiColor: rgb(0xFF9F0A, 0.35))
    /// Yellow marker behind quoted offers ("Předplatné 99 Kč/týden").
    static let highlighter = Color(uiColor: rgb(0xFFCC00, 0.55))
    static let codeBlock = Color(uiColor: rgb(0x1C1F26))
    static let codeText = Color(uiColor: rgb(0xF1F5F9))
    static let badgeYellow = Color(uiColor: rgb(0xFFD60A))
    static let smsGreen = Color(uiColor: rgb(0x34C759))
    static let iMessageBlue = Color(uiColor: rgb(0x0A84FF))
    static let calendarRed = Color(uiColor: rgb(0xFF3B30))

    static func hex(_ value: UInt32, _ alpha: CGFloat = 1) -> Color {
        Color(uiColor: rgb(value, alpha))
    }
}

/// The colour families of verdicts, chips, notices and reasons.
enum Tone: String, Sendable, CaseIterable {
    case safe, caution, danger, alert, incomplete, info

    /// `--safe`, `--caution`… — icons, kickers, the meter of a band.
    var color: Color {
        switch self {
        case .safe: Tone.c(0x15914A, 0x30D158, 0x0B6E35, 0x5BE37D)
        case .caution: Tone.c(0xC46A00, 0xFFB340, 0x8F4D00, 0xFFC56E)
        case .danger: Tone.c(0xD42A2A, 0xFF5A5A, 0xA51717, 0xFF8585)
        case .alert: Tone.c(0xD4570B, 0xFF8A3D, 0x9E3F06, 0xFFA466)
        case .incomplete: Tone.c(0x5F6B7C, 0xA6B0C0, 0x434D5C, 0xC3CBD8)
        case .info: Tone.c(0x0A66FF, 0x4D9DFF, 0x004CD1, 0x80B9FF)
        }
    }

    /// `--safe-bg`… — badge, chip, notice and consequence backgrounds.
    var background: Color {
        switch self {
        case .safe: Tone.c(0xE7F6ED, 0x0F2C1C)
        case .caution: Tone.c(0xFFF3DC, 0x33230A)
        case .danger: Tone.c(0xFDEAEA, 0x3A1214)
        case .alert: Tone.c(0xFFF0E5, 0x3A1D0B)
        case .incomplete: Tone.c(0xEEF1F5, 0x23262D)
        case .info: Tone.c(0xE8F0FF, 0x0D2144)
        }
    }

    /// `--safe-strong`… — text on the tinted backgrounds.
    var strong: Color {
        switch self {
        case .safe: Tone.c(0x0F7A3D, 0x6EE7A0, 0x09592C, 0x9AF0BD)
        case .caution: Tone.c(0x9A5300, 0xFFD08A, 0x6E3B00, 0xFFE0B3)
        case .danger: Tone.c(0xA81D1D, 0xFFA3A3, 0x7F1212, 0xFFC4C4)
        case .alert: Tone.c(0xA8420A, 0xFFC199, 0x7A2F06, 0xFFD6BD)
        case .incomplete: Tone.c(0x475264, 0xCDD5E1, 0x323A47, 0xE1E6EE)
        case .info: Tone.c(0x0850C7, 0x9CC6FF, 0x063C96, 0xC2DCFF)
        }
    }

    /// Text of a chip: `-strong` in light mode, the base colour in dark mode (as in the prototype).
    var chipText: Color {
        switch self {
        case .safe: Tone.c(0x0F7A3D, 0x30D158, 0x09592C, 0x5BE37D)
        case .caution: Tone.c(0x9A5300, 0xFFB340, 0x6E3B00, 0xFFC56E)
        case .danger: Tone.c(0xA81D1D, 0xFF5A5A, 0x7F1212, 0xFF8585)
        case .alert: Tone.c(0xA8420A, 0xFF8A3D, 0x7A2F06, 0xFFA466)
        case .incomplete: Tone.c(0x475264, 0xCDD5E1, 0x323A47, 0xE1E6EE)
        case .info: Tone.c(0x0850C7, 0x9CC6FF, 0x063C96, 0xC2DCFF)
        }
    }

    private static func c(_ light: UInt32, _ dark: UInt32, _ contrastLight: UInt32? = nil, _ contrastDark: UInt32? = nil) -> Color {
        dynamic(rgb(light), rgb(dark), contrastLight: contrastLight.map { rgb($0) }, contrastDark: contrastDark.map { rgb($0) })
    }
}

/// Corner radii and spacing from app.css.
enum Metrics {
    static let screenPadding: CGFloat = 16
    static let blockGap: CGFloat = 12
    static let cardRadius: CGFloat = 22
    static let typeCardRadius: CGFloat = 24
    static let meterRadius: CGFloat = 18
    static let noticeRadius: CGFloat = 18
    static let consequenceRadius: CGFloat = 20
    static let detailsRadius: CGFloat = 20
    static let claimRadius: CGFloat = 14
    static let minTouch: CGFloat = 44
}

extension Shape where Self == RoundedRectangle {
    static func card(_ radius: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }
}

// MARK: - HSL helpers (business card and bank colours use hsl() in the prototype)

extension Color {
    /// CSS `hsl(h s% l%)`.
    static func hsl(_ hue: Double, _ saturation: Double, _ lightness: Double) -> Color {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = saturation / 100, l = lightness / 100
        let brightness = l + s * min(l, 1 - l)
        let sat = brightness == 0 ? 0 : 2 * (1 - l / brightness)
        return Color(hue: h, saturation: sat, brightness: brightness)
    }
}
