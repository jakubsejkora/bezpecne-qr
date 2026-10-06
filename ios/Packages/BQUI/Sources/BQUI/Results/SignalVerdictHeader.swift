import BQCore
import SwiftUI

struct SignalVerdictHeader: View {
    let summary: ResultSummary
    var bleed: CGFloat = 0
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqDesign) private var design
    @Environment(\.bqSignalPreset) private var preset
    @Environment(\.bqScoreChart) private var scoreChart
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.dynamicTypeSize) private var typeSize

    private var warning: Bool { summary.verdict.tone == .danger || summary.verdict.isAlert }
    private var unboxed: Bool { preset == .type && !warning }
    private var ink: Color { unboxed || preset == .fade ? design.ink : summary.surface.ink.color }
    private var title: String { preset != .current && summary.verdict.tone == .danger ? "Stop." : summary.verdict.title }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .padding(preset == .current ? 18 : 22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .measureFadeHeader()
                .background {
                    if preset == .current {
                        LinearGradient(colors: [summary.surface.start.color, contrast == .increased ? summary.surface.start.color : summary.surface.end.color], startPoint: .topLeading, endPoint: .bottomTrailing)
                    } else if preset != .fade { unboxed ? design.background : summary.surface.start.color }
                }
            if let score = summary.score {
                RiskScoreChart(score: score, muted: summary.provisional, slim: preset == .type)
                    .padding(.horizontal, separateChart ? 22 : 0)
                    .padding(.top, scoreChart == .spectrum ? 0 : 8)
                    .padding(.bottom, separateChart ? 10 : 0)
                    .background(preset == .fade ? Color.clear : separateChart ? design.background : summary.surface.start.color)
            }
        }
        .foregroundStyle(ink)
        .clipShape(RoundedRectangle(cornerRadius: preset == .current ? 16 : 0))
        .padding(.horizontal, preset == .current ? 0 : -bleed)
        .padding(.top, preset == .current ? 4 : 0).padding(.bottom, 14)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier("result.verdict")
    }

    private var separateChart: Bool { scoreChart != .spectrum || preset == .fade || unboxed }

    private var content: some View {
        VStack(alignment: .leading, spacing: preset == .current ? 9 : 12) {
            if typeSize.isAccessibilitySize { scoreBlock }
            if !typeSize.isAccessibilitySize && (preset != .current || summary.verdict.kicker != nil) {
                HStack {
                    Label(summary.typeName, systemImage: summary.verdict.icon)
                        .font(.caption.weight(.bold)).textCase(.uppercase).tracking(0.8)
                    Spacer(minLength: 8)
                    if title == "Stop." { Text(summary.verdict.title).font(.caption.weight(.bold)) }
                }
            }
            if preset == .poster && !typeSize.isAccessibilitySize {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    heading
                    Spacer(minLength: 0)
                    scoreBlock
                }
            } else {
                heading
                if !typeSize.isAccessibilitySize { scoreBlock }
            }
            if let reason = summary.leadingReason, !reason.isEmpty {
                Text(reason).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private var heading: some View {
        Text(title).bqFont(preset == .current ? 28 : title == "Stop." ? 58 : 32, .heavy, relativeTo: .title)
            .tracking(preset == .current ? -0.5 : -1.1).fixedSize(horizontal: false, vertical: true)
    }
    @ViewBuilder private var scoreBlock: some View {
        if let score = summary.score {
            VStack(alignment: .leading, spacing: 3) {
                if preset == .poster || preset == .type || typeSize.isAccessibilitySize {
                    Text(lang.t(summary.verdict.isAlert ? "summary.fraudRisk" : "summary.risk"))
                        .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    number(score)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(lang.t(summary.verdict.isAlert ? "summary.fraudRisk" : "summary.risk"))
                            .font(.subheadline.weight(.semibold))
                        Text("·").font(.subheadline)
                        number(score)
                    }
                }
                if summary.provisional {
                    Text(lang.t("summary.provisional")).font(.caption.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lang.t(summary.verdict.isAlert ? "meter.fraud" : "meter.label") + (summary.provisional ? ", " + lang.t("summary.provisional") : ""))
            .accessibilityValue(lang.t("a11y.meterValue", ["score": String(score)]))
        }
    }
    private func number(_ score: Int) -> some View {
        (Text(String(score)).font(.system(preset == .type ? .largeTitle : .title, design: preset == .current ? .rounded : .default, weight: .heavy))
            + Text("/100").font(.subheadline.weight(.semibold)))
            .monospacedDigit().fixedSize(horizontal: false, vertical: true)
    }
}
