import BQCore
import SwiftUI

/// One reason, written as observation → implication → action (`.reason`).
struct ReasonRow: View {
    var reason: FindingTexts.Reason
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        layout {
            ReasonIcon(icon: reason.icon, tone: reason.tone)
            VStack(alignment: .leading, spacing: 4) {
                Text(reason.texts.title)
                    .bqFont(16, .bold, relativeTo: .callout)
                    .foregroundStyle(BQColor.label)
                    .padding(.top, 2)
                if !reason.texts.observation.isEmpty {
                    Text(reason.texts.observation)
                        .bqFont(15, relativeTo: .subheadline)
                        .foregroundStyle(BQColor.label)
                }
                if !reason.texts.implication.isEmpty {
                    Text(reason.texts.implication)
                        .bqFont(15, relativeTo: .subheadline)
                        .foregroundStyle(BQColor.label2)
                }
                if !reason.texts.action.isEmpty {
                    Group {
                        if typeSize.isAccessibilitySize {
                            // Inline arrow: the text gets the full width at huge sizes.
                            Text("\(Image(systemName: Symbol.arrow)) \(reason.texts.action)")
                        } else {
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Image(systemName: Symbol.arrow)
                                    .imageScale(.small)
                                    .accessibilityHidden(true)
                                Text(reason.texts.action)
                            }
                        }
                    }
                    .bqFont(15, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label)
                }
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

/// The tinted square in front of a reason; it stops growing at the largest non-accessibility size.
private struct ReasonIcon: View {
    var icon: String
    var tone: Tone?
    @ScaledMetric(relativeTo: .callout) private var box: CGFloat = 34

    var body: some View {
        Image(systemName: icon)
            .bqFont(17, .semibold, relativeTo: .callout)
            .foregroundStyle(tone?.color ?? BQColor.label2)
            .frame(width: box, height: box)
            .background(tone?.background ?? BQColor.fill, in: .card(box * 0.32))
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .accessibilityHidden(true)
    }
}

/// A card of reasons separated by hairlines.
struct ReasonList: View {
    var reasons: [FindingTexts.Reason]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(reasons.enumerated()), id: \.offset) { index, reason in
                if index > 0 {
                    BQColor.separator.frame(height: 1).padding(.vertical, 14)
                }
                ReasonRow(reason: reason)
            }
        }
    }
}

/// "Co se stane, když budete pokračovat" — a tinted box per consequence (`.consequence`).
struct ConsequenceBox: View {
    var consequence: FindingTexts.Consequence
    @ScaledMetric(relativeTo: .callout) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: consequence.texts.severity == .info ? Symbol.info : Symbol.caution)
                .bqFont(19, .semibold, relativeTo: .callout)
                .frame(width: iconWidth)
                .padding(.top, 1)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(consequence.texts.title)
                    .bqFont(16, .bold, relativeTo: .callout)
                if !consequence.texts.text.isEmpty {
                    Text(consequence.texts.text)
                        .bqFont(14.5, relativeTo: .subheadline)
                        .lineSpacing(2)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(consequence.tone.strong)
        .padding(14)
        .background(consequence.tone.background, in: .card(Metrics.consequenceRadius))
        .blockGap()
        .accessibilityElement(children: .combine)
    }
}

/// `ul.checks`: what we verified, each with a green check.
struct ChecksList: View {
    var checks: [(id: String, text: String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(checks.enumerated()), id: \.offset) { index, check in
                if index > 0 {
                    BQColor.separator.frame(height: 1)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Image(systemName: Symbol.check)
                        .font(.body.weight(.semibold))
                        .imageScale(.small)
                        .foregroundStyle(Tone.safe.color)
                        .accessibilityHidden(true)
                    Text(check.text)
                        .bqFont(14.5, relativeTo: .subheadline)
                        .foregroundStyle(BQColor.label)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 8)
            }
        }
    }
}

/// The completeness notice under the type card (cards.js `completenessNotice`).
struct CompletenessNotice: View {
    var analysis: Analysis
    var onManualCheck: () -> Void
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        let completeness = analysis.completeness
        let state = completeness.state
        if state == .incomplete || state == .skipped {
            if analysis.band == .incomplete {
                // Under "Nelze ověřit" the reason is already the subtitle — show only the next step.
                if state == .skipped {
                    Notice(icon: Symbol.info) { manualPart(completeness) }
                        .blockGap()
                }
            } else {
                Notice(icon: Symbol.incomplete) {
                    Text(attributedReason(completeness))
                        .fixedSize(horizontal: false, vertical: true)
                    if state == .skipped { manualPart(completeness) }
                }
                .blockGap()
            }
        }
    }

    private func attributedReason(_ c: Completeness) -> AttributedString {
        var head = AttributedString(lang.t("sec.incomplete") + ". ")
        head.inlinePresentationIntent = .stronglyEmphasized
        return head + AttributedString(Typo.prose(RuleSet.bundled.texts.incomplete(c.reason, lang), lang))
    }

    @ViewBuilder private func manualPart(_ c: Completeness) -> some View {
        if c.manual {
            Button(action: onManualCheck) {
                Text(lang.t("sec.manual"))
                    .bqFont(14.5, .semibold, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.tintText)
                    .frame(minHeight: Metrics.minTouch, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, -8)
        } else {
            Text(Typo.prose(lang.t("sec.noManual"), lang))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
