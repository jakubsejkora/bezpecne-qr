import BQCore
import SwiftUI

// MARK: - Receipt chrome

/// A receipt: rounded top, zig-zag torn bottom edge (`.receipt` + `::after`).
struct ReceiptShape: Shape {
    var topRadius: CGFloat = 24
    var toothWidth: CGFloat = 14
    var toothDepth: CGFloat = 6

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(topRadius, rect.width / 2, rect.height / 2)
        let bottom = rect.maxY - toothDepth
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + r))
        p.addArc(center: CGPoint(x: rect.minX + r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        p.addArc(center: CGPoint(x: rect.maxX - r, y: rect.minY + r), radius: r,
                 startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom))
        let count = max(2, Int((rect.width / toothWidth).rounded()))
        let step = rect.width / CGFloat(count)
        var x = rect.maxX
        for _ in 0..<count {
            p.addLine(to: CGPoint(x: x - step / 2, y: rect.maxY))
            x -= step
            p.addLine(to: CGPoint(x: x, y: bottom))
        }
        p.closeSubpath()
        return p
    }
}

/// The receipt surface with the "print" reveal (top to bottom) when it appears.
struct Receipt<Content: View>: View {
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bqSnapshot) private var snapshot
    @State private var printed = false

    var body: some View {
        let animated = !reduceMotion && !snapshot
        let progress: CGFloat = (!animated || printed) ? 1 : 0
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.top, 18)
        .padding(.bottom, 22 + 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReceiptShape().fill(BQColor.card))
        .shadow(color: .black.opacity(0.04), radius: 1, y: 1)
        .mask(alignment: .top) {
            Rectangle().scaleEffect(x: 1, y: progress, anchor: .top)
        }
        .offset(y: progress == 1 ? 0 : -12)
        .onAppear {
            guard animated, !printed else { return }
            withAnimation(.timingCurve(0.2, 0.9, 0.3, 1, duration: 0.7)) { printed = true }
        }
        .padding(.bottom, 18)
    }
}

/// `.intent`: what the payment does, in a capsule.
struct IntentChip: View {
    @Environment(\.bqDesign) private var design
    var text: String
    var icon: String
    var tone: Tone = .info

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .imageScale(.small)
                .accessibilityHidden(true)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .bqFont(13.5, .bold, relativeTo: .footnote)
        .foregroundStyle(tone.panelInk(in: design))
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(tone.panel(in: design), in: .capsule)
    }
}

/// The big amount (`.amount`) — never wraps inside the number; shrinks a little instead.
struct AmountView: View {
    var number: String
    var symbol: String
    var size: CGFloat = 46

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(number)
                .bqFont(size, .heavy, design: .rounded, relativeTo: .largeTitle)
                .tracking(-1)
                .foregroundStyle(BQColor.label)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .layoutPriority(1)
            if !symbol.isEmpty {
                Text(symbol)
                    .bqFont(size * 0.45, .bold, design: .rounded, relativeTo: .title2)
                    .foregroundStyle(BQColor.label2)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .padding(.top, 10)
        .padding(.bottom, 2)
        .accessibilityElement(children: .combine)
    }
}

/// A missing or invalid amount (`.amount.missing`).
struct MissingAmount: View {
    var text: String

    var body: some View {
        Text(text)
            .bqFont(22, relativeTo: .title2)
            .foregroundStyle(BQColor.label2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
            .padding(.bottom, 2)
    }
}

/// Numbers split into unbreakable segments ("19-", "2000145399/", "0800") that wrap only between
/// segments, so an account number is never broken inside a digit group.
struct SegmentedNumber: View {
    var segments: [String]
    var size: CGFloat = 21
    var weight: Font.Weight = .bold
    var design: Font.Design = .rounded

    var body: some View {
        FlowLayout(spacing: 0, lineSpacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                Text(segment)
                    .bqFont(size, weight, design: design, relativeTo: .title2)
                    .tracking(0.2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(segments.joined())
    }

    /// "19-2000145399/0800" → ["19-", "2000145399/", "0800"]; IBANs → groups of four.
    static func split(_ s: String) -> [String] {
        if s.contains("/") || s.contains("-") {
            var out: [String] = []
            var current = ""
            for c in s {
                current.append(c)
                if c == "-" || c == "/" { out.append(current); current = "" }
            }
            if !current.isEmpty { out.append(current) }
            return out
        }
        let grouped = Format.iban(s).split(separator: " ").map(String.init)
        return grouped.enumerated().map { $0.offset < grouped.count - 1 ? $0.element + "\u{00A0}" : $0.element }
    }
}

/// A coloured square with the bank's initials (`.bank-logo`).
struct BankLogo: View {
    var code: String
    var name: String?

    private static let colors: [String: UInt32] = [
        "0800": 0x2870ED, "0100": 0xE2231A, "0300": 0x003E7E, "2010": 0x1C9E4B,
        "0600": 0x3C3C3C, "5500": 0xFEE600, "3030": 0x7AB928, "0710": 0x8A1538,
    ]

    var body: some View {
        let background = Self.colors[code].map { BQColor.hex($0) }
            ?? Color.hsl(Double(Format.hue(code.isEmpty ? (name ?? "?") : code)), 45, 42)
        Text(letters)
            .font(.system(size: 11, weight: .heavy))
            .foregroundStyle(code == "5500" ? Color.black : Color.white)
            .frame(width: 26, height: 26)
            .background(background, in: .card(8))
            .accessibilityHidden(true)
    }

    private var letters: String {
        let capitals = (name ?? "").filter { "ABCDEFGHIJKLMNOPQRSTUVWXYZČŘŠŽÁÉÍÓÚŮÝĎŤŇ".contains($0) }
        let result = String(capitals.prefix(2))
        return result.isEmpty ? "?" : result
    }
}

/// `.sym`: VS / SS / KS symbols.
struct SymbolChip: View {
    var label: String
    var value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
            Text(value)
                .fontWeight(.bold)
                .fontDesign(.rounded)
        }
        .bqFont(13, relativeTo: .footnote)
        .foregroundStyle(BQColor.label)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(BQColor.card2, in: .card(10))
        .accessibilityElement(children: .combine)
    }
}

/// The "Komu" block: account, bank, IBAN, recipient name taken from the code.
struct AccountBlock: View {
    var account: String
    var bankCode: String?
    var bankName: String
    var iban: String?
    var bic: String?
    var recipientName: String?
    var accountIsName = false
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CardLabel(text: lang.t("pay.to"))
                .padding(.bottom, 2)
            if accountIsName {
                Text(account)
                    .bqFont(22, .bold, design: .rounded, relativeTo: .title2)
                    .foregroundStyle(BQColor.label)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                SegmentedNumber(segments: SegmentedNumber.split(account))
                    .foregroundStyle(BQColor.label)
                HStack(spacing: 8) {
                    if let bankCode {
                        BankLogo(code: bankCode, name: bankName)
                    } else {
                        Image(systemName: "globe")
                            .font(.system(size: 22))
                            .foregroundStyle(BQColor.label2)
                            .frame(width: 26, height: 26)
                            .accessibilityHidden(true)
                    }
                    Text(bankName)
                        .bqFont(15, .semibold, relativeTo: .subheadline)
                        .foregroundStyle(BQColor.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 5)
            }
            if let iban {
                Text("IBAN " + Format.iban(iban) + (bic.map { " · BIC \($0)" } ?? ""))
                    .bqFont(12.5, design: .monospaced, relativeTo: .caption)
                    .foregroundStyle(BQColor.label2)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
                    .accessibilityLabel("IBAN " + iban + (bic.map { ", BIC \($0)" } ?? ""))
            }
            if let recipientName {
                Claim(caption: lang.t("pay.rn"), text: lang.quoted(recipientName))
            }
        }
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) {
            Line()
                .stroke(BQColor.separator, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(height: 1)
        }
        .padding(.top, 14)
    }

    private struct Line: Shape {
        func path(in rect: CGRect) -> Path {
            Path { p in
                p.move(to: CGPoint(x: rect.minX, y: rect.midY))
                p.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            }
        }
    }
}

// MARK: - QR Platba (SPD / SCD / Platba+F)

struct PaymentReceipt: View {
    var info: PaymentInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        Receipt {
            FlowLayout(spacing: 6, lineSpacing: 6) {
                IntentChip(text: intent.text, icon: intent.icon, tone: intent.tone)
                if info.paymentType == "IP" {
                    IntentChip(text: lang.t("pay.instant"), icon: "bolt.fill")
                }
            }
            amount
            // Without a domestic form the IBAN is the account line itself; don't repeat it.
            AccountBlock(account: info.domestic ?? Format.iban(info.iban), bankCode: info.bankCode, bankName: bankName,
                         iban: info.domestic == nil ? nil : info.iban, recipientName: info.recipientName)
            let symbols = [("VS", info.vs), ("SS", info.ss), ("KS", info.ks)].compactMap { k, v in v.map { (k, $0) } }
            if !symbols.isEmpty {
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(symbols, id: \.0) { SymbolChip(label: $0.0, value: $0.1) }
                }
                .padding(.top, 10)
            }
            if !rows.isEmpty {
                KeyValueList(rows: rows)
            }
            if let invoice = info.invoice {
                SubHeading(text: lang.t("pay.invoice"))
                KeyValueList(rows: invoiceRows(invoice), top: 4)
            }
            FinePrint(icon: Symbol.info, text: lang.t("pay.formatOnly"))
        }
    }

    private var intent: (text: String, icon: String, tone: Tone) {
        switch info.kind {
        case "standing":
            let text = info.frequency.flatMap { L10n.has("freq.\($0)") ? lang.t("pay.standingEvery", ["freq": lang.t("freq.\($0)")]) : nil }
                ?? (info.frequency.map { "\(lang.t("pay.standingOnly")) · \($0)" } ?? lang.t("pay.standingOnly"))
            return (text, "repeat", .caution)
        case "directDebit":
            return (lang.t("pay.debit"), "repeat", .caution)
        default:
            if info.invoice != nil { return ("\(lang.t("pay.oneoff")) · \(lang.t("pay.invoice"))", "doc.text", .info) }
            return (lang.t("pay.oneoff"), "banknote", .info)
        }
    }

    @ViewBuilder private var amount: some View {
        if let raw = info.amountRaw {
            MissingAmount(text: "\(lang.t("pay.invalidAmount")): \(lang.quoted(raw))")
        } else if let a = Format.amount(info.amount, currency: info.currency, language: lang) {
            AmountView(number: a.number, symbol: a.symbol)
        } else {
            MissingAmount(text: lang.t("pay.noAmount"))
        }
    }

    private var bankName: String {
        if let name = info.bankName { return name }
        if let country = info.country { return "\(lang.t("pay.foreign")) (\(country))" }
        return lang.t("pay.bankUnknown")
    }

    private var rows: [KeyValue] {
        var out: [KeyValue] = []
        if info.kind == "standing", let due = info.dueDate {
            out.append(KeyValue(key: lang.t("pay.first"), value: Format.longDate(due, language: lang)))
        } else if info.kind == "directDebit" {
            let limit = Format.money(info.amount, currency: info.currency, language: lang) ?? "—"
            out.append(KeyValue(key: lang.t("pay.limit"), value: limit))
            if let last = info.lastDate {
                out.append(KeyValue(key: lang.t("pay.until"), value: Format.longDate(last, language: lang)))
            }
        } else if let due = info.dueDate {
            out.append(KeyValue(key: lang.t("pay.due"), value: Format.longDate(due, language: lang)))
        }
        if let message = info.message, !message.isEmpty {
            out.append(KeyValue(key: lang.t("pay.msg"), value: message))
        }
        return out
    }

    private func invoiceRows(_ i: InvoiceInfo) -> [KeyValue] {
        var out: [KeyValue] = []
        if let id = i.id { out.append(KeyValue(key: lang.t("inv.number"), value: id)) }
        if let issued = i.issued { out.append(KeyValue(key: lang.t("inv.issued"), value: Format.longDate(issued, language: lang))) }
        if let issuer = Self.issuer(i.issuerIco, i.issuerVat) { out.append(KeyValue(key: lang.t("inv.issuer"), value: issuer)) }
        if let base = Format.money(i.base, currency: "CZK", language: lang) { out.append(KeyValue(key: lang.t("inv.base"), value: base)) }
        if let vat = Format.money(i.vat, currency: "CZK", language: lang) { out.append(KeyValue(key: lang.t("inv.vat"), value: vat)) }
        return out
    }

    static func issuer(_ ico: String?, _ vat: String?) -> String? {
        let parts = [ico, vat].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: " / ")
    }
}

// MARK: - QR Faktura (SID)

struct InvoiceReceipt: View {
    var info: InvoiceDocInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        Receipt {
            IntentChip(text: lang.t("pay.invoice"), icon: "doc.text")
            if let a = Format.amount(info.total, currency: info.currency ?? "CZK", language: lang) {
                AmountView(number: a.number, symbol: a.symbol)
            } else {
                MissingAmount(text: lang.t("pay.noAmount"))
            }
            KeyValueList(rows: rows)
            if let iban = info.iban {
                FinePrint(icon: Symbol.info, text: "IBAN " + Format.iban(iban))
            }
        }
    }

    private var rows: [KeyValue] {
        var out: [KeyValue] = []
        if let id = info.id { out.append(KeyValue(key: lang.t("inv.number"), value: id)) }
        if let v = info.issued { out.append(KeyValue(key: lang.t("inv.issued"), value: Format.longDate(v, language: lang))) }
        if let v = info.due { out.append(KeyValue(key: lang.t("pay.due"), value: Format.longDate(v, language: lang))) }
        if let v = info.taxPoint { out.append(KeyValue(key: lang.t("inv.taxPoint"), value: Format.longDate(v, language: lang))) }
        if let v = PaymentReceipt.issuer(info.issuerIco, info.issuerVat) { out.append(KeyValue(key: lang.t("inv.issuer"), value: v)) }
        if let v = Format.money(info.base, currency: info.currency ?? "CZK", language: lang) { out.append(KeyValue(key: lang.t("inv.base"), value: v)) }
        if let v = Format.money(info.vat, currency: info.currency ?? "CZK", language: lang) { out.append(KeyValue(key: lang.t("inv.vat"), value: v)) }
        if let v = info.vs { out.append(KeyValue(key: "VS", value: v)) }
        return out
    }
}

// MARK: - EPC / GiroCode and Swiss QR-bill

struct TransferReceipt: View {
    var info: TransferInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        let name = info.name ?? info.creditor ?? "—"
        Receipt {
            IntentChip(text: "\(lang.t("pay.oneoff")) · \(info.standard == "spc" ? "QR-bill" : "SEPA")", icon: "banknote")
            if let a = Format.amount(info.amount, currency: info.currency, language: lang) {
                AmountView(number: a.number, symbol: a.symbol)
            } else {
                MissingAmount(text: lang.t("pay.noAmount"))
            }
            AccountBlock(account: name, bankCode: nil, bankName: "", iban: info.iban, bic: info.bic,
                         recipientName: name, accountIsName: true)
            if let reference = info.reference {
                FlowLayout {
                    SymbolChip(label: info.referenceType ?? "REF", value: reference)
                }
                .padding(.top, 10)
            }
            if let message = info.text ?? info.message, !message.isEmpty {
                KeyValueList(rows: [KeyValue(key: lang.t("pay.msg"), value: message)])
            }
            FinePrint(icon: Symbol.info, text: lang.t("pay.formatOnly"))
        }
    }
}

// MARK: - Crypto

struct CryptoCard: View {
    var info: CryptoInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: info.network, icon: Symbol.type(.crypto))
            if let amount = info.amount {
                let formatted = Format.amount(amount, currency: info.unit, language: lang)
                AmountView(number: formatted?.number ?? amount, symbol: info.unit ?? formatted?.symbol ?? "", size: 38)
            }
            if let label = info.label ?? info.description, !label.isEmpty {
                CardLabel(text: lang.quoted(label))
            }
            if let address = info.recipient ?? info.address {
                SubHeading(text: lang.t(info.recipient != nil ? "crypto.recipient" : "crypto.address"))
                MonoText(text: Format.chunked(address), size: 15, color: BQColor.label)
            }
            if let contract = info.contract {
                SubHeading(text: lang.t("crypto.token"))
                MonoText(text: [info.token, contract].compactMap { $0 }.joined(separator: " · "))
            }
            if let invoice = info.invoice {
                SubHeading(text: "Lightning")
                MonoText(text: invoice)
            }
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}
