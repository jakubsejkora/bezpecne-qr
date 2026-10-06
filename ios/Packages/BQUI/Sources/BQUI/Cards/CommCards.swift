import BQCore
import SwiftUI

/// `.price-tag`: a slightly tilted sticker with the price.
struct PriceTag: View {
    @Environment(\.bqDesign) private var design
    var text: String

    var body: some View {
        Text(text)
            .bqFont(18, .heavy, design: .rounded, relativeTo: .title3)
            .foregroundStyle(Tone.alert.panelInk(in: design))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Tone.alert.panel(in: design), in: .card(12))
            .rotationEffect(.degrees(-2))
            .padding(.top, 10)
    }
}

/// A phone number in the dial-pad style (`.dial .dnum`).
struct DialNumber: View {
    var number: String

    var body: some View {
        let long = number.count > 16
        Text(number)
            .bqFont(long ? 22 : 30, .bold, design: .rounded, relativeTo: .title)
            .tracking(long ? 0 : 0.5)
            .foregroundStyle(BQColor.label)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// SMS: recipient, premium price and the pre-filled message as a chat bubble.
struct SMSCard: View {
    var info: SMSInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 2) {
                CardLabel(text: lang.t("sms.to"))
                DialNumber(number: info.numberDisplay)
                if let premium = info.premium {
                    PriceTag(text: premium.price ?? "? Kč")
                } else if info.charity == true {
                    Chip(text: "DMS", icon: nil, tone: .info)
                        .padding(.top, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
            .accessibilityElement(children: .combine)

            VStack(spacing: 8) {
                Text("\(lang.t("sms.to")): \(info.numberDisplay)")
                    .bqFont(13, relativeTo: .footnote)
                    .foregroundStyle(BQColor.label2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                if !info.body.isEmpty {
                    ChatBubble(text: info.body)
                }
            }
            .padding(14)
            .background(BQColor.card2, in: .card(18))
            .padding(.top, 10)
            .accessibilityElement(children: .combine)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}

/// Phone number: number, kind, premium price, MMI service code.
struct PhoneCard: View {
    var info: PhoneInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(spacing: 4) {
            DialNumber(number: info.numberDisplay)
            if let kind = info.kind {
                Text(kind.resolve(lang))
                    .bqFont(17, relativeTo: .body)
                    .foregroundStyle(BQColor.label2)
                    .multilineTextAlignment(.center)
            }
            if let price = info.premium?.price {
                PriceTag(text: price)
            }
            if let mmi = info.mmi {
                Chip(text: Typo.prose([mmi.service.resolve(lang), mmi.target].compactMap { $0 }.joined(separator: " → "), lang),
                     icon: "phone.arrow.right", tone: .alert)
                    .multilineTextAlignment(.center)
                    .padding(.top, 10)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 2)
        .bqCard(radius: Metrics.typeCardRadius, padding: 18)
        .blockGap()
        .accessibilityElement(children: .combine)
    }
}

/// E-mail as an airmail envelope (`.envelope`).
struct MailCard: View {
    var info: EmailInfo
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            row(lang.t("mail.to")) {
                Text(recipient)
                    .bqFont(15, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let cc = info.cc, !cc.isEmpty {
                row(lang.t("mail.cc")) { value(cc) }
            }
            if let subject = info.subject, !subject.isEmpty {
                row(lang.t("mail.subject")) { value(subject) }
            }
            if let body = info.body, !body.isEmpty {
                Claim(caption: nil, text: body)
                    .padding(.top, -5)
            }
        }
        .padding(16)
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BQColor.card)
        .overlay(alignment: .top) { AirmailStripes().frame(height: 6) }
        .clipShape(.card(Metrics.cardRadius))
        .blockGap()
    }

    /// `user@` + host with the registrable domain in bold.
    private var recipient: AttributedString {
        let parts = info.to.split(separator: "@", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return AttributedString(info.to) }
        let split = HostFormat.split(parts[1], registrable: info.registrable)
        var main = AttributedString(split.registrable)
        main.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString(parts[0] + "@" + split.prefix) + main
    }

    private func value(_ text: String) -> some View {
        Text(text)
            .bqFont(15, .semibold, relativeTo: .subheadline)
            .foregroundStyle(BQColor.label)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func row<V: View>(_ key: String, @ViewBuilder _ value: () -> V) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 14))
        layout {
            Text(key)
                .bqFont(15, relativeTo: .subheadline)
                .foregroundStyle(BQColor.label2)
            value()
                .frame(maxWidth: .infinity, alignment: typeSize.isAccessibilitySize ? .leading : .trailing)
                .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Red–white–blue diagonal stripes along the top of the envelope.
struct AirmailStripes: View {
    var body: some View {
        Canvas { context, size in
            let colors: [Color] = [BQColor.hex(0xFF453A), .white, BQColor.hex(0x0A84FF), .white]
            let widths: [CGFloat] = [12, 8, 12, 8]
            var x: CGFloat = -size.height
            var index = 0
            while x < size.width + size.height {
                let w = widths[index % 4]
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height))
                p.addLine(to: CGPoint(x: x + size.height, y: 0))
                p.addLine(to: CGPoint(x: x + size.height + w, y: 0))
                p.addLine(to: CGPoint(x: x + w, y: size.height))
                p.closeSubpath()
                context.fill(p, with: .color(colors[index % 4]))
                x += w
                index += 1
            }
        }
        .accessibilityHidden(true)
    }
}
