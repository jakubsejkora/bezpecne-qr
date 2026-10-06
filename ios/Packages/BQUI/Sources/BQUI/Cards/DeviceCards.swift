import BQCore
import SwiftUI

/// Wi‑Fi network card: SSID, security badge, password hidden until "Ukázat".
struct WiFiCard: View {
    @Environment(\.bqDesign) private var design
    var info: WiFiInfo
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        let open = info.security == "open"
        let weak = open || info.security == "WEP"
        VStack(spacing: 0) {
            Image(systemName: "wifi")
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(design == .signal ? Tone.info.panelInk(in: design) : Tone.info.color)
                .frame(width: 70, height: 70)
                .background(Tone.info.panel(in: design), in: .card(22))
                .padding(.bottom, 8)
                .accessibilityHidden(true)
            Text(HostFormat.breakable(info.ssid))
                .bqFont(24, .heavy, relativeTo: .title2)
                .foregroundStyle(BQColor.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(info.ssid)
            FlowLayout(spacing: 6, lineSpacing: 6, alignment: .center) {
                Chip(text: "\(lang.t("wifi.security")): \(open ? lang.t("wifi.open") : info.security)",
                     icon: open ? "lock.open" : "lock", tone: weak ? .caution : .safe)
                if info.hidden {
                    Chip(text: lang.t("wifi.hidden"), icon: "eye.slash", tone: nil)
                }
            }
            .padding(.top, 8)
            if let password = info.password {
                PasswordRow(password: password, revealed: Binding(get: { model.revealPassword }, set: { model.revealPassword = $0 }))
                    .padding(.top, 12)
            }
            FinePrint(icon: Symbol.info, text: lang.t("wifi.operator"), centered: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .bqCard(radius: Metrics.typeCardRadius, padding: 16)
        .blockGap()
    }
}

/// `.pw`: dots until the user taps "Ukázat"; never shown by default.
struct PasswordRow: View {
    var password: String
    @Binding var revealed: Bool
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(spacing: 6) { secret; toggle }
            } else {
                HStack(spacing: 10) { secret; toggle }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(BQColor.card2, in: .card(14))
    }

    private var secret: some View {
        Text(revealed ? password : "••••••••")
            .bqFont(18, design: .monospaced, relativeTo: .body)
            .foregroundStyle(BQColor.label)
            .textSelection(.disabled)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(revealed ? password : lang.t("a11y.passwordHidden"))
    }

    private var toggle: some View {
        Button {
            revealed.toggle()
        } label: {
            Text(lang.t(revealed ? "wifi.hide" : "wifi.show"))
                .bqFont(14, .bold, relativeTo: .subheadline)
                .foregroundStyle(BQColor.tintText)
                .frame(minWidth: Metrics.minTouch, minHeight: Metrics.minTouch)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(lang.t(revealed ? "wifi.hide" : "wifi.show")) — \(lang.t("wifi.password"))")
    }
}

/// The restrained key / device card of sensitive codes (`.secure-card`). Secrets never appear.
struct SecureCard<Content: View>: View {
    var icon: String
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(BQColor.label)
                .frame(width: 70, height: 70)
                .background(BQColor.card2, in: .card(22))
                .padding(.bottom, 10)
                .accessibilityHidden(true)
            Text(title)
                .bqFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(BQColor.label)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            content
                .bqFont(15, relativeTo: .subheadline)
                .foregroundStyle(BQColor.label2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .bqCard(radius: Metrics.typeCardRadius, padding: 16)
        .blockGap()
    }
}

/// `.hidden-secret`: dots standing in for a secret that is never shown.
struct HiddenSecretDots: View {
    var count = 8

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { _ in
                Circle().fill(BQColor.label3).frame(width: 10, height: 10)
            }
        }
        .padding(.top, 10)
        .accessibilityHidden(true)
    }
}
