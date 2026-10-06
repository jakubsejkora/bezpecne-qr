import BQCore
import SwiftUI

/// Plain text on a yellow note, with detected entities (accounts, "bezpečný účet"…) marked.
struct NoteCard: View {
    var info: TextInfo
    @State private var expanded = false
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(lang.t("text.label"))
                .bqFont(13, .semibold, relativeTo: .footnote)
                .opacity(0.7)
            Text(marked)
                .lineLimit(expanded || (info.text.count <= 180 && !info.text.contains("\n")) ? nil : 6)
                .bqFont(18, relativeTo: .body)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            if info.text.count > 180 || info.text.contains("\n") {
                Button(lang.t(expanded ? "text.less" : "text.full")) { expanded.toggle() }
                    .font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }
        }
        .foregroundStyle(BQColor.label)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BQColor.card, in: .card(Metrics.cardRadius))
        .shadow(color: .black.opacity(0.06), radius: 4, y: 2)
        .blockGap()
        .accessibilityElement(children: .combine)
    }

    private var marked: AttributedString {
        var text = AttributedString(info.text)
        for entity in info.entities where !entity.value.isEmpty {
            var searchStart = text.startIndex
            while searchStart < text.endIndex, let range = text[searchStart...].range(of: entity.value) {
                text[range].backgroundColor = BQColor.noteMark
                text[range].inlinePresentationIntent = .stronglyEmphasized
                searchStart = range.upperBound
            }
        }
        return text
    }
}

/// `data:` / `javascript:` content in a dark code block. Never executed.
struct CodeCard: View {
    var chip: String
    var code: String
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: chip, icon: Symbol.type(.jsURI))
            SubHeading(text: lang.t("code.content"))
            Text(code)
                .bqFont(13, design: .monospaced, relativeTo: .footnote)
                .foregroundStyle(BQColor.codeText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BQColor.codeBlock, in: .card(16))
                .padding(.top, 4)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}

/// EMVCo merchant-presented QR (Asia, …).
struct EMVCoCard: View {
    var info: EMVCoInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: "EMVCo", icon: Symbol.type(.emvco))
            if let merchant = info.merchant {
                Text(merchant)
                    .bqFont(22, .bold, relativeTo: .title2)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            KeyValueList(rows: rows)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }

    private var rows: [KeyValue] {
        var out: [KeyValue] = []
        let place = [info.city, info.country].compactMap { $0 }.joined(separator: ", ")
        if !place.isEmpty { out.append(KeyValue(key: lang.t("emv.city"), value: place)) }
        if let amount = info.amount {
            let currency = info.currencyCode.map { Self.iso4217[$0] ?? "(\($0))" }
            out.append(KeyValue(key: lang.t("emv.amount"), value: [amount, currency].compactMap { $0 }.joined(separator: " ")))
        }
        return out
    }

    /// EMVCo tag 53 carries the numeric ISO 4217 code.
    static let iso4217: [String: String] = [
        "156": "CNY", "203": "CZK", "344": "HKD", "356": "INR", "360": "IDR", "392": "JPY", "410": "KRW",
        "458": "MYR", "608": "PHP", "702": "SGD", "704": "VND", "764": "THB", "784": "AED", "826": "GBP",
        "840": "USD", "901": "TWD", "978": "EUR", "985": "PLN",
    ]
}

/// GS1 Digital Link on a product.
struct GS1Card: View {
    var info: GS1Info
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductCardLayout(icon: "shippingbox.fill", gradient: [BQColor.hex(0xFFD166), BQColor.hex(0xEF8354)], card: false) {
                CardLabel(text: lang.t("gs1.gtin"))
                Text(info.gtin)
                    .bqFont(22, .bold, design: .rounded, relativeTo: .title2)
                    .foregroundStyle(BQColor.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            KeyValueList(rows: rows, top: 12)
            MonoText(text: info.host)
                .padding(.top, 8)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }

    private var rows: [KeyValue] {
        var out: [KeyValue] = []
        if let batch = info.batch { out.append(KeyValue(key: lang.t("gs1.batch"), value: batch)) }
        if let expiry = info.expiry { out.append(KeyValue(key: lang.t("gs1.expiry"), value: Format.longDate(expiry, language: lang))) }
        return out
    }
}

/// IATA boarding pass. The passenger name and PNR are personal data and stay hidden.
struct BoardingPassCard: View {
    var info: BoardingPassInfo
    @Environment(\.bqLanguage) private var lang
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        VStack(spacing: 0) {
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())) {
                Text("\(info.carrier) \(info.flight)")
                if !stacked { Spacer() }
                if let date = info.date?.resolve(lang) { Text(date) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .bqFont(17, .bold, relativeTo: .headline)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(LinearGradient(colors: [BQColor.hex(0x00A1DE), BQColor.hex(0x1A5BB8)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))
            HStack {
                iata(info.from)
                Spacer(minLength: 8)
                Image(systemName: "airplane")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(BQColor.hex(0x00A1DE))
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                iata(info.to)
            }
            .padding(16)
            (stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(alignment: .top, spacing: 8))) {
                field(lang.t("bcbp.seat"), info.seat)
                field(lang.t("bcbp.flight"), info.carrier + info.flight)
                field("PNR", "••••••")
                    .accessibilityLabel("PNR")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(BQColor.card)
        .clipShape(.card(Metrics.typeCardRadius))
        .blockGap()
        .accessibilityElement(children: .combine)
    }

    private func iata(_ code: String) -> some View {
        Text(code)
            .bqFont(36, .heavy, design: .rounded, relativeTo: .largeTitle)
            .foregroundStyle(BQColor.label)
    }

    private func field(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .bqFont(13, relativeTo: .footnote)
                .foregroundStyle(BQColor.label2)
            Text(value)
                .bqFont(16, .bold, relativeTo: .callout)
                .foregroundStyle(BQColor.label)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Picks the card for a code type (cards.js `typeCard`).
struct TypeCard: View {
    var analysis: Analysis
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        switch analysis.content {
        case .link(let info):
            if analysis.type == .webcal { WebcalCard(info: info) } else { LinkCard(analysis: analysis, info: info) }
        case .appInstall(let info): AppInstallCard(info: info)
        case .store(let info): StoreCard(info: info)
        case .messenger(let info): MessengerCard(info: info)
        case .payment(let info): PaymentReceipt(info: info)
        case .invoice(let info): InvoiceReceipt(info: info)
        case .transfer(let info): TransferReceipt(info: info)
        case .crypto(let info): CryptoCard(info: info)
        case .payBySquare:
            SecureCard(icon: "banknote", title: "PAY by square") { Text(lang.t("pbs.text")) }
        case .sms(let info): SMSCard(info: info)
        case .phone(let info): PhoneCard(info: info)
        case .email(let info): MailCard(info: info)
        case .contact(let info): ContactCard(info: info, model: model)
        case .wifi(let info): WiFiCard(info: info, model: model)
        case .otp(let info):
            SecureCard(icon: "key", title: info.issuer) {
                VStack(spacing: 0) {
                    Text(otpLine(info))
                    HiddenSecretDots()
                    Text(lang.t("otp.secretHidden")).padding(.top, 8)
                }
            }
        case .otpMigration(let info):
            SecureCard(icon: "key", title: lang.t("mig.accounts")) {
                VStack(spacing: 0) {
                    FlowLayout(spacing: 6, lineSpacing: 6, alignment: .center) {
                        ForEach(info.issuers, id: \.self) { Chip(text: $0, icon: nil, tone: nil) }
                    }
                    HiddenSecretDots()
                    Text(lang.t("otp.secretHidden")).padding(.top, 8)
                }
            }
        case .login(let info):
            SecureCard(icon: Symbol.type(.login), title: info.service) { Text(lang.t("type.login")) }
        case .fido:
            SecureCard(icon: Symbol.type(.fido), title: "Passkey") { Text(verbatim: "FIDO · hybrid") }
        case .seed(let info):
            SecureCard(icon: "key", title: lang.t("seed.words", ["n": String(info.words)])) { HiddenSecretDots(count: 12) }
        case .walletConnect(let info):
            SecureCard(icon: "link", title: "WalletConnect") {
                Text(["v\(info.version)", info.relay.map { "relay \($0)" }].compactMap { $0 }.joined(separator: " · "))
            }
        case .event(let info): EventCard(info: info)
        case .geo(let info): GeoCard(info: info)
        case .text(let info): NoteCard(info: info)
        case .dataURI(let info): CodeCard(chip: info.mime, code: info.preview)
        case .script(let info): CodeCard(chip: "javascript:", code: info.code)
        case .intent(let info): IntentCard(info: info)
        case .emvco(let info): EMVCoCard(info: info)
        case .gs1(let info): GS1Card(info: info)
        case .boardingPass(let info): BoardingPassCard(info: info)
        case .healthCertificate:
            SecureCard(icon: Symbol.type(.hc1), title: lang.t("type.hc1")) { Text(lang.t("hc1.text")) }
        }
    }

    /// "Účet: jakub · TOTP · 6 číslic".
    private func otpLine(_ info: OTPInfo) -> AttributedString {
        var account = AttributedString(info.account)
        account.inlinePresentationIntent = .stronglyEmphasized
        let digitsKey = (2...4).contains(info.digits) ? "otp.digitsFew" : "otp.digits"
        let rest = " · \(info.kind) · \(lang.t(digitsKey, ["n": String(info.digits)]))"
        return AttributedString("\(lang.t("otp.account")): ") + account + AttributedString(rest)
    }
}
