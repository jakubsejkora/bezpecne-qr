import BQCore
import SwiftUI

/// The action stack of the result sheet (`.actions`).
struct ActionsView: View {
    var plan: ActionPlan
    var model: ResultModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 10) {
            ForEach(plan.items) { item in
                switch item {
                case .button(let spec):
                    ActionButton(spec: spec, model: model)
                case .row(let specs):
                    if typeSize.isAccessibilitySize || specs.count == 1 {
                        ForEach(specs) { ActionButton(spec: $0, model: model) }
                    } else {
                        HStack(spacing: 10) {
                            ForEach(specs) { ActionButton(spec: $0, model: model, compact: true) }
                        }
                    }
                case .hold(let hold):
                    HoldAction(hold: hold, model: model)
                case .hint(let text):
                    Text(text)
                        .bqFont(13, relativeTo: .footnote)
                        .foregroundStyle(BQColor.label2)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.top, -4)
                }
            }
        }
        .padding(.top, 4)
        .padding(.bottom, 6)
    }
}

struct ActionButton: View {
    var spec: ActionPlan.Button
    var model: ResultModel
    var compact = false

    var body: some View {
        Button {
            switch spec.behavior {
            case .perform(let action): model.perform(action)
            case .pageExtract: model.route = .pageExtract
            case .none: break
            }
        } label: {
            ButtonLabel(title: spec.title, icon: spec.icon)
        }
        .buttonStyle(BQButtonStyle(kind: kind))
        .disabled(spec.style == .disabled || isBusy)
    }

    private var kind: BQButtonStyle.Kind {
        switch spec.style {
        case .primary: .primary
        case .secondary, .disabled: compact ? .compact : .secondary
        case .plain: .plain
        }
    }

    /// Another action is in flight (closing always works).
    private var isBusy: Bool {
        guard model.inFlight != nil else { return false }
        if case .perform(let action) = spec.behavior, action == .close || action == .backToScanning { return false }
        return true
    }
}

/// A hold-to-confirm button with its accessible alternative underneath.
struct HoldAction: View {
    var hold: ActionPlan.Hold
    var model: ResultModel
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 2) {
            HoldToConfirmButton(title: hold.title) {
                model.perform(hold.action)
            } confirmInstead: {
                askForConfirmation()
            }
            Button(action: askForConfirmation) {
                Text(hold.alternativeTitle)
                    .bqFont(13, .semibold, relativeTo: .footnote)
                    .foregroundStyle(BQColor.tintText)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: Metrics.minTouch)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, typeSize.isAccessibilitySize ? 4 : -10)
        }
    }

    private func askForConfirmation() {
        model.confirmation = ResultModel.Confirmation(title: hold.confirmTitle, message: hold.confirmMessage,
                                                      confirmTitle: hold.confirmButton, action: hold.action)
    }
}

/// "Podržet 2 s a otevřít přesto": the fill grows while pressed; releasing early cancels.
/// VoiceOver / Switch Control activation opens the deliberate confirmation instead.
struct HoldToConfirmButton: View {
    var title: String
    var duration: Double = 2
    var onComplete: () -> Void
    var confirmInstead: () -> Void
    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var completions = 0
    @State private var justCompleted = false
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .accessibilityHidden(true)
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bqFont(15.5, .bold, relativeTo: .body)
        .foregroundStyle(Tone.danger.color)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: Metrics.minTouch + 4)
        .background(alignment: .leading) {
            GeometryReader { geo in
                Tone.danger.background
                    .frame(width: geo.size.width * progress)
            }
        }
        .clipShape(.capsule)
        .overlay {
            Capsule().strokeBorder(Tone.danger.color.opacity(pressing ? 0.35 : 0), lineWidth: 1.5)
        }
        .contentShape(.capsule)
        .onLongPressGesture(minimumDuration: duration, maximumDistance: 40) {
            justCompleted = true
            completions += 1
            onComplete()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
                justCompleted = false
            }
        } onPressingChanged: { isPressing in
            pressing = isPressing
            if isPressing {
                withAnimation(.linear(duration: duration)) { progress = 1 }
            } else if !justCompleted {
                withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: pressing) { _, new in new }
        .sensoryFeedback(.impact(weight: .heavy), trigger: completions)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(lang.t("a11y.holdHint"))
        .accessibilityAction { confirmInstead() }
    }
}
