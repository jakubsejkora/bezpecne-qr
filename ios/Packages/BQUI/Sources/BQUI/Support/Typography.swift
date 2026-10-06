import BQCore
import SwiftUI

// Type scale of the prototype (sizes in pt at the default text size), scaled with Dynamic Type.
// SF Pro everywhere; SF Pro Rounded (`ui-rounded`) for amounts, scores, phone numbers and initials.

private struct ScaledFont: ViewModifier {
    @Environment(\.bqDesign) private var direction
    @ScaledMetric private var size: CGFloat
    @Environment(\.legibilityWeight) private var legibility
    private let weight: Font.Weight
    private let design: Font.Design

    init(size: CGFloat, weight: Font.Weight, design: Font.Design, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.design = design
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size + (direction == .signal && size >= 24 ? 2 : 0), weight: legibility == .bold ? Self.bolder(weight) : weight, design: design == .monospaced ? .monospaced : direction == .softContrast ? .rounded : design))
    }

    /// Bold Text makes every weight one step heavier.
    private static func bolder(_ w: Font.Weight) -> Font.Weight {
        switch w {
        case .ultraLight, .thin, .light: .regular
        case .regular: .semibold
        case .medium: .bold
        case .semibold: .bold
        case .bold: .heavy
        default: .black
        }
    }
}

extension View {
    /// A system font of `size` pt that scales with Dynamic Type like `style`.
    func bqFont(_ size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default,
                relativeTo style: Font.TextStyle = .body) -> some View {
        modifier(ScaledFont(size: size, weight: weight, design: design, relativeTo: style))
    }

    /// Small uppercase headings: `.section-title` and `.sub-h`.
    func bqCaps(_ size: CGFloat = 13, tracking: CGFloat = 0.5) -> some View {
        bqFont(size, .bold, relativeTo: .footnote)
            .tracking(tracking)
            .textCase(.uppercase)
    }
}

/// Line-breaking care for running text: numbers ("+420 606 000 000", "1 500 Kč") never break
/// apart, and in Czech one-letter prepositions and conjunctions stay with the next word ("vlna").
enum Typo {
    /// 1. Digit groups: "902 11 99", "+420 606 000 000", "250 000".
    private static let digitGroups = try! NSRegularExpression(pattern: "(?<=[0-9+]) (?=[0-9])")
    /// 2. A number and its unit: "99 Kč", "50 Kč/min", "25 €", "10 %", "2 dny".
    private static let units = try! NSRegularExpression(pattern: "(?<=[0-9]) (?=(Kč|CZK|€|EUR|CHF|%|min\\b|s\\b|dní|dny|den\\b|days?\\b))")
    /// 3. Czech "vlna": a one-letter preposition or conjunction stays with the next word.
    private static let vlna = try! NSRegularExpression(pattern: "(?<=^|[\\s(„\"\u{00A0}])([ksvzouaiKSVZOUAI]) ")

    static func prose(_ s: String, _ lang: Language) -> String {
        guard s.contains(" ") else { return s }
        let ns = NSMutableString(string: s)
        digitGroups.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "\u{00A0}")
        units.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "\u{00A0}")
        if lang == .cs {
            // Twice, so chains like "a v Praze" are joined too.
            for _ in 0..<2 {
                vlna.replaceMatches(in: ns, range: NSRange(location: 0, length: ns.length), withTemplate: "$1\u{00A0}")
            }
        }
        return ns as String
    }
}

/// Draws a marker stroke under the lower half of every line (`.offer-hl`, linear-gradient 55%).
struct MarkerRenderer: TextRenderer {
    var color: Color

    func draw(layout: Text.Layout, in ctx: inout GraphicsContext) {
        for line in layout {
            let r = line.typographicBounds.rect
            let marker = CGRect(x: r.minX - 2, y: r.minY + r.height * 0.5, width: r.width + 4, height: r.height * 0.45)
            ctx.fill(Path(roundedRect: marker, cornerRadius: 2), with: .color(color))
        }
        for line in layout {
            ctx.draw(line)
        }
    }
}
