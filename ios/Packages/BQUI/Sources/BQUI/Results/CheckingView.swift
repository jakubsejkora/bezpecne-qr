import BQCore
import SwiftUI

/// "Kontroluji…": the type, the destination, "Web zatím neotevíráme v prohlížeči." and honest
/// progress — only the steps seen so far, no denominator (screens.js `checking()`).
struct CheckingView: View {
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        let a = model.analysis
        let steps = CheckingView.visibleSteps(model.stepHistory)
        VStack(spacing: 14) {
            TypeChip(text: lang.t("type.\(a.type.rawValue)"), icon: Symbol.type(a.type))
                .padding(.bottom, 2)
            Text(lang.t("check.title"))
                .bqFont(24, .bold, relativeTo: .title2)
                .foregroundStyle(BQColor.label)
                .padding(.top, 4)
            if let host = Self.host(a) {
                Text(HostFormat.breakable(host))
                    .bqFont(17, .bold, relativeTo: .body)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(host)
            }
            Text(lang.t("check.sub"))
                .bqFont(15, relativeTo: .subheadline)
                .foregroundStyle(BQColor.label2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(text: Self.label(for: step, a, lang), active: index == steps.count - 1)
                }
            }
            .padding(.top, 10)
            .animation(.smooth(duration: 0.3), value: steps)
            Button {
                model.perform(.close)
            } label: {
                ButtonLabel(title: lang.t("check.cancel"), icon: nil)
            }
            .buttonStyle(BQButtonStyle(kind: .secondary))
            .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
    }

    /// Steps seen so far; the address is always checked first, even if the app didn't report it.
    static func visibleSteps(_ history: [CheckStep]) -> [CheckStep] {
        guard let first = history.first else { return [.address] }
        return first == .address ? history : [.address] + history
    }

    static func host(_ a: Analysis) -> String? {
        switch a.content {
        case .link(let l): HostFormat.display(l.hostDisplay ?? l.host)
        case .store(let s): s.host
        case .messenger(let m): m.host
        case .intent(let i): i.host
        default: nil
        }
    }

    static func label(for step: CheckStep, _ a: Analysis, _ lang: Language) -> String {
        switch step {
        case .address:
            if let host = host(a)?.lowercased(),
               RuleSet.bundled.shorteners.contains(host) || RuleSet.bundled.qrRedirectors.contains(host) {
                return lang.t("check.expand")
            }
            return lang.t("check.address")
        case .domain: return lang.t("check.domain")
        case .redirects(let n): return lang.t("check.redirects", ["n": String(n)])
        case .page: return lang.t("check.page")
        }
    }
}

/// One step: a green check when done, a spinner while active.
struct StepRow: View {
    var text: String
    var active: Bool
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if active {
                    Spinner()
                } else {
                    Image(systemName: Symbol.check)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Tone.safe.color)
                }
            }
            .frame(width: 22, height: 22)
            Text(text)
                .bqFont(15.5, relativeTo: .subheadline)
                .foregroundStyle(BQColor.label)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(BQColor.card, in: .card(14))
        .overlay {
            if active {
                RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(BQColor.tint, lineWidth: 2)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(lang.t(active ? "a11y.stepActive" : "a11y.stepDone"))
    }
}

/// `.spinner`: a quarter arc turning over a faint ring.
struct Spinner: View {
    var size: CGFloat = 18
    @Environment(\.bqSnapshot) private var snapshot

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: snapshot)) { context in
            let turn = snapshot ? 0.12 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.8) / 0.8
            ZStack {
                Circle().stroke(BQColor.fill2, lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: 0.25)
                    .stroke(BQColor.tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(turn * 360 - 90))
            }
            .frame(width: size, height: size)
        }
        .accessibilityHidden(true)
    }
}
