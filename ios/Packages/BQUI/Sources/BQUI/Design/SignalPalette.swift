import SwiftUI

/// One scale drives both the risk strip and the verdict surface. Higher means riskier.
enum SignalPalette {
    struct RGB: Equatable {
        let r: Double, g: Double, b: Double
        init(_ hex: UInt32) {
            r = Double((hex >> 16) & 255) / 255
            g = Double((hex >> 8) & 255) / 255
            b = Double(hex & 255) / 255
        }
        private init(r: Double, g: Double, b: Double) { self.r = r; self.g = g; self.b = b }
        var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }
        func mixed(with other: RGB, fraction: Double) -> RGB {
            RGB(r: r + (other.r - r) * fraction, g: g + (other.g - g) * fraction, b: b + (other.b - b) * fraction)
        }
        var luminance: Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        func contrast(with other: RGB) -> Double {
            (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
        }
    }
    static let stops: [(position: Double, color: RGB)] = [
        (0, RGB(0x34C759)), (0.25, RGB(0xFFD60A)),
        (0.45, RGB(0xFF9F0A)), (0.60, RGB(0xFF453A)), (1, RGB(0xD70015)),
    ]
    static var gradientStops: [Gradient.Stop] {
        (0...200).map { .init(color: sample(at: Double($0) / 200).color, location: Double($0) / 200) }
    }
    static var gradient: LinearGradient {
        LinearGradient(stops: gradientStops, startPoint: .leading, endPoint: .trailing)
    }
    static func color(at score: Int) -> RGB {
        sample(at: Double(score) / 100)
    }
    static func smooth(_ fraction: Double) -> Double {
        let t = min(1, max(0, fraction))
        return t * t * (3 - 2 * t)
    }
    /// One continuous sampler for surfaces, linear charts and the angular stroke.
    static func sample(at position: Double) -> RGB {
        let fraction = min(1, max(0, position))
        for index in 1..<stops.count where fraction <= stops[index].position {
            let a = stops[index - 1], b = stops[index]
            if fraction == b.position { return b.color }
            return a.color.mixed(with: b.color, fraction: smooth((fraction - a.position) / (b.position - a.position)))
        }
        return stops.last!.color
    }
    static func color(for tone: Tone) -> RGB {
        switch tone {
        case .safe: color(at: 0)
        case .caution, .alert: RGB(0xFF9F0A)
        case .danger: RGB(0xE52B36)
        case .incomplete: RGB(0x353F4B)
        case .info: RGB(0x1765DE)
        }
    }
    struct Surface {
        let start: RGB, end: RGB, ink: RGB
        init(_ base: RGB) {
            let black = RGB(0x000000), white = RGB(0xFFFFFF)
            let darker = base.mixed(with: black, fraction: 0.08)
            let blackMinimum = min(base.contrast(with: black), darker.contrast(with: black))
            let whiteMinimum = min(base.contrast(with: white), darker.contrast(with: white))
            start = base
            if max(blackMinimum, whiteMinimum) >= 4.5 {
                end = darker; ink = blackMinimum >= whiteMinimum ? black : white
            } else {
                // Keep all small labels legible at the black/white crossover.
                end = base; ink = base.contrast(with: black) >= base.contrast(with: white) ? black : white
            }
        }
    }
}

extension Tone {
    func panel(in design: DesignDirection) -> Color { design == .signal ? SignalPalette.color(for: self).color : background }
    func panelInk(in design: DesignDirection) -> Color { design == .signal ? SignalPalette.Surface(SignalPalette.color(for: self)).ink.color : strong }
    func chipInk(in design: DesignDirection) -> Color { design == .signal ? panelInk(in: design) : chipText }
}
