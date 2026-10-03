import BQCore
import SwiftUI

// Liquid Glass is used for chrome only (close/back buttons). Facts — verdicts, domains, amounts —
// always sit on opaque surfaces. iOS 18 gets a material; Reduce Transparency gets an opaque fill.

/// A round 44 pt chrome button (close ✕, back ‹).
struct ChromeButton: View {
    var systemImage: String
    var label: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BQColor.label)
                .frame(width: Metrics.minTouch, height: Metrics.minTouch)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .modifier(ChromeGlass())
        .accessibilityLabel(label)
    }
}

/// Glass on iOS 26+, a thin material on iOS 18, an opaque fill with Reduce Transparency.
struct ChromeGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.bqSnapshot) private var snapshot

    func body(content: Content) -> some View {
        if reduceTransparency || snapshot {
            // ImageRenderer can't draw glass or materials; snapshots use the opaque variant.
            content.background(BQColor.fill2, in: Circle())
        } else if #available(iOS 26, *) {
            content.glassEffect(.regular.interactive(), in: Circle())
        } else {
            content.background(.ultraThinMaterial, in: Circle())
                .overlay(Circle().strokeBorder(BQColor.separator, lineWidth: 0.5))
        }
    }
}

/// The bar above the sheet content: optional back button, optional title, close button.
struct SheetChrome: View {
    var title: String?
    var back: (() -> Void)?
    var close: (() -> Void)?
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let back {
                    ChromeButton(systemImage: "chevron.left", label: lang.t("common.back"), action: back)
                } else {
                    Color.clear.frame(width: Metrics.minTouch, height: Metrics.minTouch)
                }
            }
            Spacer(minLength: 0)
            if let title {
                Text(title)
                    .bqFont(16, .bold, relativeTo: .headline)
                    .foregroundStyle(BQColor.label)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .accessibilityAddTraits(.isHeader)
            }
            Spacer(minLength: 0)
            Group {
                if let close {
                    ChromeButton(systemImage: "xmark", label: lang.t("act.close"), action: close)
                } else {
                    Color.clear.frame(width: Metrics.minTouch, height: Metrics.minTouch)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }
}

// MARK: - Buttons (`.btn-primary`, `.btn-secondary`, `.btn-plain`)

struct BQButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, plain, compact }
    var kind: Kind
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .bqFont(kind == .compact ? 15 : 17, .bold, relativeTo: .body)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .compact ? 12 : 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: kind == .plain ? Metrics.minTouch : 52)
            .background { background }
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.45)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary: .white
        case .secondary, .compact, .plain: BQColor.tintText
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary:
            if #available(iOS 26, *) {
                // The prototype's iOS 26 look: a lit gradient with a specular top edge.
                Capsule()
                    .fill(LinearGradient(colors: [BQColor.hex(0x2B95FF), BQColor.hex(0x0A78F0)], startPoint: .top, endPoint: .bottom))
                    .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center), lineWidth: 1.5))
                    .shadow(color: BQColor.hex(0x0A84FF, 0.35), radius: 9, y: 8)
            } else {
                Capsule().fill(BQColor.tint)
            }
        case .secondary, .compact:
            Capsule().fill(BQColor.fill)
        case .plain:
            Color.clear
        }
    }
}

/// Icon + title used inside buttons.
struct ButtonLabel: View {
    var title: String
    var icon: String?

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .accessibilityHidden(true)
            }
            Text(title)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
