import BQCore
import SwiftUI

// MARK: - Surfaces

extension View {
    /// `.card` / `.tcard`: an opaque rounded surface. Facts never sit on glass.
    func bqCard(radius: CGFloat = Metrics.cardRadius, padding: CGFloat = 16, color: Color = BQColor.card) -> some View {
        modifier(DesignCard(radius: radius, padding: padding, color: color))
    }

    /// Bottom margin between blocks of the sheet (`margin-bottom: 12px`).
    func blockGap(_ value: CGFloat = Metrics.blockGap) -> some View {
        padding(.bottom, value)
    }
}

// MARK: - Flow layout (chip rows wrap like `display: flex; flex-wrap: wrap`)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    var lineSpacing: CGFloat = 6
    var alignment: HorizontalAlignment = .leading

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width.map { min(width, $0) } ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(width: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x: CGFloat
            switch alignment {
            case .center: x = bounds.minX + (bounds.width - row.width) / 2
            case .trailing: x = bounds.maxX - row.width
            default: x = bounds.minX
            }
            for item in row.items {
                subviews[item.index].place(at: CGPoint(x: x, y: y + (row.height - item.size.height) / 2),
                                           proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            var size = subviews[index].sizeThatFits(.unspecified)
            if size.width > maxWidth {
                size = subviews[index].sizeThatFits(ProposedViewSize(width: maxWidth, height: nil))
            }
            let needed = row.items.isEmpty ? size.width : row.width + spacing + size.width
            if !row.items.isEmpty, needed > maxWidth {
                rows.append(row)
                row = Row()
            }
            row.width = row.items.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.items.append((index, size))
        }
        if !row.items.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - Chips

/// `.chip` (and `.chip.safe/.caution/…`): a small capsule with an optional icon.
struct Chip: View {
    @Environment(\.bqDesign) private var design
    var text: String
    var icon: String?
    var tone: Tone?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if let icon {
                Image(systemName: icon)
                    .imageScale(.small)
                    .accessibilityHidden(true)
            }
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bqFont(13, .semibold, relativeTo: .footnote)
        .foregroundStyle(tone?.chipInk(in: design) ?? BQColor.label)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tone?.panel(in: design) ?? BQColor.fill, in: .capsule)
    }
}

/// `.type-chip`: type icon + type name on a grey capsule.
struct TypeChip: View {
    var text: String
    var icon: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .accessibilityHidden(true)
            Text(text)
        }
        .bqFont(13.5, .semibold, relativeTo: .footnote)
        .foregroundStyle(BQColor.label)
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(BQColor.fill, in: .capsule)
    }
}

// MARK: - Headings

/// `.section-title`: "PROČ?", "CO SE STANE…".
struct SectionTitle: View {
    var text: String

    var body: some View {
        Text(text)
            .bqCaps(13, tracking: 0.5)
            .foregroundStyle(BQColor.label2)
            .padding(.horizontal, 6)
            .padding(.top, 6)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `.sub-h`: small uppercase heading inside cards.
struct SubHeading: View {
    var text: String
    var top: CGFloat = 12

    var body: some View {
        Text(text)
            .bqCaps(13, tracking: 0.4)
            .foregroundStyle(BQColor.label2)
            .padding(.top, top)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

/// `.tcard .label`.
struct CardLabel: View {
    var text: String

    var body: some View {
        Text(text)
            .bqFont(13, .semibold, relativeTo: .footnote)
            .foregroundStyle(BQColor.label2)
    }
}

// MARK: - Notices, claims, fine print

/// `.notice`: a tinted box with an icon (incomplete check, sticker tip, extract note).
struct Notice<Content: View>: View {
    @Environment(\.bqDesign) private var design
    var icon: String
    var tone: Tone = .incomplete
    @ViewBuilder var content: Content
    @ScaledMetric(relativeTo: .subheadline) private var iconWidth: CGFloat = 22

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .bqFont(17, .medium, relativeTo: .subheadline)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .bqFont(14.5, relativeTo: .subheadline)
        .foregroundStyle(tone.panelInk(in: design))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tone.panel(in: design), in: .card(Metrics.noticeRadius))
    }
}

/// `.claim`: something a page or a code says about itself, quoted on a soft surface.
struct Claim: View {
    var caption: String?
    var text: String
    var highlight = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let caption {
                Text(caption)
                    .bqFont(12.6, relativeTo: .footnote)
                    .foregroundStyle(BQColor.label2)
            }
            if highlight {
                HighlightedText(text: text)
                    .bqFont(14, .bold, relativeTo: .subheadline)
            } else {
                Text(text)
                    .bqFont(14, relativeTo: .subheadline)
            }
        }
        .foregroundStyle(BQColor.label)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BQColor.card2, in: .card(Metrics.claimRadius))
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
    }
}

/// `.offer-hl`: a yellow marker under the lower half of the text.
struct HighlightedText: View {
    var text: String

    var body: some View {
        Text(text)
            .textRenderer(MarkerRenderer(color: BQColor.highlighter))
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// `.fine`: small print with an icon.
struct FinePrint: View {
    var icon: String
    var text: String
    var bold: String?
    var centered = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(composed)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bqFont(13, relativeTo: .footnote)
        .foregroundStyle(BQColor.label2)
        .multilineTextAlignment(centered ? .center : .leading)
        .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private var composed: AttributedString {
        var out = AttributedString(text)
        if let bold {
            var b = AttributedString(" " + HostFormat.breakable(bold))
            b.inlinePresentationIntent = .stronglyEmphasized
            out += b
        }
        return out
    }
}

// MARK: - Key–value rows (`dl.kv`)

struct KeyValue: Identifiable {
    var id: String { key + "\u{1F}" + value }
    var key: String
    var value: String
    var keyIcon: String?
    var mono = false
}

/// `dl.kv`: label left, value right (stacked at accessibility sizes).
struct KeyValueList: View {
    var rows: [KeyValue]
    var top: CGFloat = 10
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(rows) { row in
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 1) {
                        keyView(row)
                        valueView(row).multilineTextAlignment(.leading)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        keyView(row)
                            .layoutPriority(1)
                        Spacer(minLength: 0)
                        valueView(row)
                            .multilineTextAlignment(.trailing)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .bqFont(15, relativeTo: .subheadline)
        .padding(.top, top)
    }

    @ViewBuilder private func keyView(_ row: KeyValue) -> some View {
        Group {
            if let icon = row.keyIcon {
                Image(systemName: icon).accessibilityLabel(row.key)
            } else {
                Text(row.key)
            }
        }
        .foregroundStyle(BQColor.label2)
    }

    private func valueView(_ row: KeyValue) -> some View {
        Text(row.value)
            .fontWeight(.semibold)
            .fontDesign(row.mono ? .monospaced : .default)
            .foregroundStyle(BQColor.label)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Hosts with the registrable domain emphasised (format.js `hostHTML`)

enum HostFormat {
    /// Splits a host into (prefix, registrable) when it ends with the registrable domain.
    static func split(_ host: String, registrable: String?) -> (prefix: String, registrable: String) {
        guard let registrable, !registrable.isEmpty else { return ("", host) }
        let candidates = [registrable, DomainKit.displayHost(registrable)]
        for candidate in candidates where host.lowercased().hasSuffix(candidate.lowercased()) && host.count >= candidate.count {
            let cut = host.index(host.endIndex, offsetBy: -candidate.count)
            return (String(host[..<cut]), String(host[cut...]))
        }
        return ("", host)
    }

    /// The host as people should read it (IDN decoded).
    static func display(_ host: String) -> String {
        DomainKit.displayHost(host)
    }

    /// Allows line breaks after dots, hyphens and slashes in long hosts and URLs (zero-width spaces),
    /// so nothing is truncated or clipped.
    static func breakable(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count + s.count / 8)
        for c in s {
            out.append(c)
            if c == "." || c == "-" || c == "/" || c == "?" || c == "&" || c == "=" || c == "_" || c == "@" { out.append("\u{200B}") }
        }
        return out
    }
}

/// A host name with its registrable part in a heavier weight, never truncated.
struct HostText: View {
    var host: String
    var registrable: String?
    var regular: Font.Weight = .regular
    var emphasis: Font.Weight = .bold
    @ScaledMetric private var size: CGFloat

    init(host: String, registrable: String?, size: CGFloat = 17, relativeTo style: Font.TextStyle = .body,
         regular: Font.Weight = .regular, emphasis: Font.Weight = .bold) {
        self.host = host
        self.registrable = registrable
        self.regular = regular
        self.emphasis = emphasis
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
    }

    var body: some View {
        Text(attributed)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(host)
    }

    private var attributed: AttributedString {
        let parts = HostFormat.split(host, registrable: registrable)
        var prefix = AttributedString(HostFormat.breakable(parts.prefix))
        prefix.font = .system(size: size, weight: regular)
        var main = AttributedString(HostFormat.breakable(parts.registrable))
        main.font = .system(size: size, weight: emphasis)
        return prefix + main
    }
}

/// Monospaced URL / code text that may break anywhere (`.mono`).
struct MonoText: View {
    var text: String
    var size: CGFloat = 13
    var color: Color = BQColor.label2

    var body: some View {
        Text(HostFormat.breakable(text))
            .bqFont(size, design: .monospaced, relativeTo: .footnote)
            .foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel(text)
    }
}

private struct DesignCard: ViewModifier {
    var radius: CGFloat
    var padding: CGFloat
    var color: Color
    @Environment(\.bqDesign) private var design
    func body(content: Content) -> some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(color, in: RoundedRectangle(cornerRadius: min(radius, design.radius)))
    }
}
