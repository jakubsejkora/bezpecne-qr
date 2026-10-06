import BQCore
import SwiftUI

/// "Našli jsme 2 kódy. Který chcete zkontrolovat?" — shown before any selection when one frame
/// holds several different codes. Numbered like the outlines on the frozen camera image.
public struct ChooserView: View {
    private let candidates: [Analysis]
    private let checking: Set<Int>
    private let language: Language
    private let onPick: (Int) -> Void
    private let onClose: () -> Void
    @Environment(\.bqSnapshot) private var snapshot
    @Environment(\.bqCapture) private var capture
    @Environment(\.bqDesign) private var design

    public init(candidates: [Analysis], checking: Set<Int> = [], language: Language, onPick: @escaping (Int) -> Void, onClose: @escaping () -> Void) {
        self.candidates = candidates
        self.checking = checking
        self.language = language
        self.onPick = onPick
        self.onClose = onClose
    }

    public var body: some View {
        SheetPage(close: onClose) {
            ChooserContent(candidates: candidates, checking: checking, onPick: onPick)
        }
        .frame(maxWidth: .infinity, maxHeight: snapshot ? nil : .infinity, alignment: .top)
        .background(design.background).modifier(ChooserBackground())
        .presentationDetents([.medium, .large])
        .environment(\.bqLanguage, language)
    }
}

/// iOS 26 keeps the system's glass sheet (the rows are opaque); iOS 18 gets the grouped background.
private struct ChooserBackground: ViewModifier {
    @Environment(\.bqSnapshot) private var snapshot

    func body(content: Content) -> some View {
        if snapshot {
            content.background(BQColor.background)
        } else if #available(iOS 26, *) {
            content
        } else {
            content.presentationBackground(BQColor.background)
        }
    }
}

private struct ChooserContent: View {
    var candidates: [Analysis]
    var checking: Set<Int>
    var onPick: (Int) -> Void
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.bqCapture) private var capture
    @Environment(\.bqDesign) private var design

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 6)
                .padding(.bottom, 12)
            if let capture {
                CapturePreview(capture).frame(height: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.bottom, 14)
            }
            VStack(spacing: 0) {
                ForEach(Array(candidates.enumerated()), id: \.offset) { index, candidate in
                    if index > 0 {
                        BQColor.separator.frame(height: 1).padding(.leading, 60)
                    }
                    Button {
                        onPick(index)
                    } label: {
                        ChooserRow(number: index + 1, analysis: candidate, checking: checking.contains(index), recommended: CodeComparison.recommendation(candidates, checking: checking) == index)
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(BQColor.card, in: .card(18))
            .blockGap()
            Notice(icon: "info.circle", tone: .info) {
                Text(Typo.prose(lang.t("choose.comparisonNote"), lang)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var header: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        let count = candidates.count
        let title = lang.t((2...4).contains(count) || lang == .en ? "choose.titleFew" : "choose.titleMany", ["n": String(count)])
        return layout {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .bqFont(26, .bold, relativeTo: .title)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                Text(lang.t("choose.compareSub"))
                    .bqFont(15.5, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct ChooserRow: View {
    var number: Int
    var analysis: Analysis
    var checking: Bool
    var recommended: Bool
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqCapture) private var capture
    @Environment(\.bqCaptureStyle) private var style
    @Environment(\.bqDesign) private var design

    var body: some View {
        HStack(spacing: 12) {
            if style == .thumbnailDock, let capture, capture.regions.indices.contains(number - 1),
               let thumbnail = captureCrop(capture.regions[number - 1], image: capture.image) {
                Image(uiImage: thumbnail).resizable().scaledToFit().frame(width: 40, height: 40)
                    .padding(4).background(.white, in: RoundedRectangle(cornerRadius: 7)).accessibilityHidden(true)
            }
            Text(String(number))
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(design.ink)
                .frame(width: 34, height: 34)
                .background(BQColor.fill2, in: Circle())

                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title
                if recommended {
                    Label(lang.t("choose.lowest"), systemImage: "arrow.down.right")
                        .font(.subheadline.bold()).foregroundStyle(.primary)
                }
                if checking {
                    HStack { ProgressView().controlSize(.small); Text(lang.t("choose.checking")).font(.footnote) }
                } else {
                    let summary = ResultSummary(analysis, texts: FindingTexts(analysis, lang), language: lang)
                    Text(summary.verdict.title).font(.subheadline.weight(.semibold))
                    if let reason = summary.leadingReason {
                        Text(reason).font(.footnote).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    if let score = summary.score {
                        Text(lang.t(summary.provisional ? "choose.provisional" : "choose.score", ["score": String(score)]))
                            .font(.footnote.monospacedDigit()).foregroundStyle(.secondary)
                    }
                }
                if analysis.type != .url {
                    Text(lang.t("type.\(analysis.type.rawValue)"))
                        .bqFont(13.5, relativeTo: .footnote).foregroundStyle(BQColor.label2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(BQColor.label3)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 56)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(lang.t("choose.openResult"))
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private var title: some View {
        if let host = host {
            HostText(host: host.host, registrable: host.registrable, size: 16.5, relativeTo: .body, regular: .regular, emphasis: .bold)
                .foregroundStyle(BQColor.label)
        } else {
            Text(summary)
                .bqFont(16.5, .semibold, relativeTo: .body)
                .foregroundStyle(BQColor.label)
                .lineLimit(3)
        }
    }

    private var host: (host: String, registrable: String?)? {
        if analysis.isSensitive { return nil }
        if let host = analysis.resolvedHost { return (HostFormat.display(host), DomainKit.registrable(host)) }
        return switch analysis.content {
        case .link(let l): (HostFormat.display(l.hostDisplay ?? l.host), l.registrable)
        case .store(let s): (s.host, s.registrable)
        case .messenger(let m): (m.host, m.registrable)
        case .intent(let i): i.host.map { ($0, i.registrable) }
        case .appInstall(let i): i.host.map { ($0, i.registrable) }
        default: nil
        }
    }

    /// A one-line description for codes without a host. Sensitive content is never shown.
    private var summary: String {
        if let host { return host.host }
        if analysis.isSensitive { return lang.t("type.\(analysis.type.rawValue)") }
        switch analysis.content {
        case .payment(let p):
            let money = Format.money(p.amount, currency: p.currency, language: lang)
            return [money, p.domestic ?? Format.iban(p.iban)].compactMap { $0 }.joined(separator: " · ")
        case .transfer(let t):
            return [Format.money(t.amount, currency: t.currency, language: lang), t.name ?? t.creditor].compactMap { $0 }.joined(separator: " · ")
        case .sms(let s): return s.numberDisplay
        case .phone(let p): return p.numberDisplay
        case .email(let e): return e.to
        case .contact(let c): return c.name
        case .event(let e): return e.summary
        case .geo(let g): return g.label ?? "\(g.lat), \(g.lon)"
        default:
            let text = analysis.code.text.replacingOccurrences(of: "\n", with: " ")
            return text.count > 60 ? String(text.prefix(60)) + "…" : text
        }
    }
}

extension Verdict {
    /// The chooser's header badge: a QR symbol in caution colours.
    static let chooser = Verdict(tone: .caution, icon: "qrcode", effect: .none, kicker: nil, title: "", subtitle: nil, chip: nil)

    init(tone: Tone, icon: String, effect: Effect, kicker: String?, title: String, subtitle: String?, chip: VerdictChip?) {
        self.tone = tone
        self.icon = icon
        self.effect = effect
        self.kicker = kicker
        self.title = title
        self.subtitle = subtitle
        self.chip = chip
    }
}
