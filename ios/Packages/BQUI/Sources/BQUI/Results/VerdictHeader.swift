import BQCore
import SwiftUI

/// The compact verdict (`.verdict`): animated badge, kicker, band title, one-line reason, chip.
struct VerdictHeader: View {
    var verdict: Verdict
    @Environment(\.bqDesign) private var design
    var body: some View {
        VStack(alignment: .leading, spacing: design == .precision ? 8 : 12) {
            HStack(spacing: 8) {
                Image(systemName: verdict.icon).font(.system(size: design == .softContrast ? 28 : 17, weight: .semibold)).accessibilityHidden(true)
                if let kicker = verdict.kicker { Text(kicker).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.8) }
                Spacer(minLength: 0)
            }.foregroundStyle(verdict.tone.strong)
            Text(verdict.title)
                .bqFont(design == .signal ? 34 : design == .precision ? 25 : 30, design.headingWeight, relativeTo: .title)
                .tracking(-0.6).fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(design == .signal ? verdict.tone.strong : design.ink)
            if let subtitle = verdict.subtitle {
                Text(subtitle).bqFont(16, relativeTo: .body).foregroundStyle(BQColor.label2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let chip = verdict.chip { Chip(text: chip.text, icon: nil, tone: chip.tone) }
            if design == .precision { Divider().padding(.top, 4) }
        }
        .padding(design == .signal || design == .softContrast ? 18 : 0)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(design == .signal ? verdict.tone.background : design == .softContrast ? design.surface : .clear,
                    in: RoundedRectangle(cornerRadius: design.radius))
        .padding(.top, 8).padding(.bottom, 20)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }
}

/// `.verdict-badge`: a tinted rounded square with a bold symbol that pops in, then bounces,
/// wiggles (caution / consequences), breathes (danger) or draws itself (safe, iOS 26).
struct VerdictBadge: View {
    var verdict: Verdict
    var size: CGFloat = 68
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bqSnapshot) private var snapshot
    @State private var trigger = 0
    @State private var drawn = false
    /// The pop-in. A plain state change with a spring always settles at scale 1 (a keyframe
    /// animator left the badge enlarged on iOS 27).
    @State private var popped = false

    private var animated: Bool { !reduceMotion && !snapshot }

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
            .fill(verdict.tone.background)
            .frame(width: size, height: size)
            .overlay { symbol }
            .frame(width: size + 8, height: size + 8)
            .scaleEffect(popped || !animated ? 1 : 0.6)
            .opacity(popped || !animated ? 1 : 0)
            .onAppear {
                guard animated else { return }
                withAnimation(.bouncy(duration: 0.55, extraBounce: 0.15)) { popped = true }
                trigger += 1
                guard verdict.effect == .draw else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    withAnimation(.easeOut(duration: 0.6)) { drawn = true }
                }
            }
            .accessibilityHidden(true)
    }

    @ViewBuilder private var symbol: some View {
        let image = Image(systemName: verdict.icon)
            .font(.system(size: size * 0.53, weight: .semibold))
            .foregroundStyle(verdict.tone.color)
        switch verdict.effect {
        case .pulse:
            image.symbolEffect(.breathe.pulse, options: .repeat(.periodic(2, delay: 0.2)), value: trigger)
        case .wiggle:
            image.symbolEffect(.wiggle, options: .nonRepeating, value: trigger)
        case .draw:
            if #available(iOS 26, *), animated {
                // The shield draws itself in once the badge has popped.
                ZStack {
                    if drawn {
                        image.transition(.symbolEffect(.drawOn))
                    }
                }
            } else {
                image.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
            }
        case .none:
            image.symbolEffect(.bounce, options: .nonRepeating, value: trigger)
        }
    }

}

/// `.meter`: "Orientační skóre rizika" 0–100. Higher = riskier; explicitly not a percentage.
struct RiskMeter: View {
    var score: Int
    /// Muted (grey) when the inspection is incomplete: "12/100 — pouze dostupné kontroly".
    var muted: Bool
    /// "Riziko podvodu" when a critical consequence leads the header.
    var fraudLabel: Bool
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let label = lang.t(fraudLabel ? "meter.fraud" : "meter.label")
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 2) {
                        labelText(label)
                        scoreText
                    }
                } else {
                    HStack(alignment: .firstTextBaseline) {
                        labelText(label)
                        Spacer(minLength: 8)
                        scoreText
                    }
                }
            }
            .padding(.bottom, 9)

            MeterTrack(score: score, muted: muted)
                .animation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.15), value: score)

            HStack {
                Text(lang.t("meter.low"))
                Spacer(minLength: 4)
                if !typeSize.isAccessibilitySize {
                    Text(lang.t("meter.mid"))
                    Spacer(minLength: 4)
                }
                Text(lang.t("meter.high"))
            }
            .lineLimit(1)
            .bqFont(11.5, relativeTo: .caption2)
            .foregroundStyle(BQColor.label2)
            .padding(.top, 7)

            Text(Typo.prose(muted ? lang.t("meter.muted", ["score": String(score)]) : lang.t("meter.note"), lang))
                .bqFont(12.5, relativeTo: .caption)
                .foregroundStyle(BQColor.label2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BQColor.card, in: .card(Metrics.meterRadius))
        .blockGap()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(lang.t("a11y.meterValue", ["score": String(score)]))
        .accessibilityHint(muted ? lang.t("meter.muted", ["score": String(score)]) : lang.t("meter.note"))
    }

    private func labelText(_ label: String) -> some View {
        Text(label)
            .bqFont(13.5, relativeTo: .footnote)
            .foregroundStyle(BQColor.label2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var scoreText: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(String(score))
                .bqFont(20, .bold, design: .rounded, relativeTo: .title3)
                .foregroundStyle(BQColor.label)
            Text(verbatim: "/100")
                .bqFont(13, .semibold, design: .rounded, relativeTo: .footnote)
                .foregroundStyle(BQColor.label2)
        }
    }
}

/// The gradient track with the round marker (`.meter-track` / `.meter-marker`).
private struct MeterTrack: View {
    var score: Int
    var muted: Bool



    var body: some View {
        Capsule()
            .fill(SignalPalette.gradient)
            .frame(height: 10)
            .grayscale(muted ? 1 : 0)
            .opacity(muted ? 0.45 : 1)
            .frame(height: 22)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let fraction = min(0.97, max(0.03, Double(score) / 100))
                    Circle()
                        .fill(.white)
                        .overlay(Circle().strokeBorder(BQColor.label, lineWidth: 3))
                        .frame(width: 22, height: 22)
                        .shadow(color: .black.opacity(0.25), radius: 3, y: 2)
                        .position(x: geo.size.width * fraction, y: geo.size.height / 2)
                }
            }
    }
}
