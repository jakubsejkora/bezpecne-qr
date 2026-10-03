import Foundation

/// QR Platba (SPD/SCD), QR Faktura (SID), EPC/GiroCode, Swiss QR-bill, EMVCo and PAY by square.
struct PaymentParser {
    let rules: RuleSet

    // MARK: Short Payment Descriptor (SPD / SCD)

    /// Splits `SPD*1.0*KEY:VALUE*…` into header and key/value pairs (values percent-decoded).
    static func attributes(_ text: String) -> (header: [String], pairs: [(String, String)], duplicates: Bool) {
        let parts = text.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        let header = Array(parts.prefix(2))
        var pairs: [(String, String)] = []
        var seen: [String: String] = [:]
        var duplicates = false
        for part in parts.dropFirst(2) where !part.isEmpty {
            guard let colon = part.firstIndex(of: ":") else { continue }
            let key = String(part[..<colon]).uppercased()
            let value = String(part[part.index(after: colon)...]).percentDecoded
            if let previous = seen[key], previous != value { duplicates = true }
            seen[key] = value
            pairs.append((key, value))
        }
        return (header, pairs, duplicates)
    }

    static func isoDate(_ yyyymmdd: String?) -> String? {
        guard let s = yyyymmdd, s.count == 8, s.allSatisfy(\.isASCIIDigit) else { return nil }
        let c = Array(s)
        return "\(String(c[0...3]))-\(String(c[4...5]))-\(String(c[6...7]))"
    }

    /// "480.50" → "480.50", "1500" → "1500.00"; nil for anything that isn't a valid SPD amount.
    static func normalizedAmount(_ s: String) -> String? {
        guard s.matches("^[0-9]{1,10}(\\.[0-9]{1,2})?$") else { return nil }
        guard let d = Decimal(string: s, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "en_US_POSIX")
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        nf.usesGroupingSeparator = false
        return nf.string(from: d as NSDecimalNumber)
    }

    func bankName(_ code: String?) -> String? {
        guard let code else { return nil }
        return rules.banks[code]?.name
    }

    func spd(_ text: String) -> Parsed {
        let (header, pairs, duplicates) = PaymentParser.attributes(text)
        let directDebit = header.first?.uppercased() == "SCD"
        var values: [String: String] = [:]
        for (k, v) in pairs where values[k] == nil { values[k] = v }

        let accField = values["ACC"] ?? ""
        let accParts = accField.split(separator: "+", maxSplits: 1).map(String.init)
        let iban = (accParts.first ?? "").filter { !$0.isWhitespace }.uppercased()
        var info = PaymentInfo(kind: directDebit ? "directDebit" : (values["FRQ"] != nil ? "standing" : "payment"), iban: iban)
        info.bic = accParts.count > 1 ? accParts[1] : nil
        info.currency = values["CC"]?.uppercased()
        info.vs = values["X-VS"]
        info.ss = values["X-SS"]
        info.ks = values["X-KS"]
        info.recipientName = values["RN"]
        info.paymentType = values["PT"]?.uppercased()
        info.message = values["MSG"]
        info.frequency = values["FRQ"]?.uppercased()
        info.dueDate = PaymentParser.isoDate(values["DT"])
        info.lastDate = PaymentParser.isoDate(values["DL"])
        info.reference = values["RF"]
        info.url = values["X-URL"]
        info.crc32 = values["CRC32"]?.uppercased()

        var parsed = Parsed(type: .spd, content: .payment(info))
        var problems: [LocalizedText] = []

        if let cz = Banking.czechAccount(fromIBAN: iban) {
            info.domestic = cz.domestic
            info.bankCode = cz.bankCode
            info.bankName = bankName(cz.bankCode)
        } else if iban.count >= 2 {
            info.country = String(iban.prefix(2))
        }

        if let am = values["AM"] {
            if let normalized = PaymentParser.normalizedAmount(am) {
                info.amount = normalized
            } else {
                info.amountRaw = am
                problems.append(LocalizedText(cs: "Částka „\(am)“ není číslo.", en: "The amount “\(am)” is not a number."))
            }
        }

        if iban.isEmpty {
            problems.append(LocalizedText(cs: "V kódu chybí číslo účtu.", en: "The code has no account number."))
        } else if Banking.isValidIBAN(iban) {
            parsed.checks.append(Finding("chk.iban_valid"))
            if let cz = Banking.czechAccount(fromIBAN: iban), !Banking.isValidCzechAccount(prefix: cz.prefix, number: cz.number) {
                problems.append(LocalizedText(cs: "Číslo účtu nemá platný kontrolní součet.", en: "The account number has an invalid checksum."))
            }
        } else {
            problems.append(LocalizedText(cs: "Číslo účtu (IBAN) nemá platný kontrolní součet.", en: "The account number (IBAN) has an invalid checksum."))
        }
        if duplicates {
            problems.append(LocalizedText(cs: "Kód obsahuje protichůdné údaje.", en: "The code contains conflicting fields."))
        }
        if let crc = info.crc32 {
            if !PaymentParser.crcMatches(text, crc: crc) {
                problems.append(LocalizedText(cs: "Kontrolní součet kódu (CRC32) nesedí.", en: "The code's CRC32 checksum doesn't match."))
            }
        }

        if let name = info.bankName, info.bankCode != nil, problems.isEmpty || Banking.isValidIBAN(iban) {
            parsed.checks.append(Finding("chk.bank_known", ["bank": .text(name)]))
        }
        if problems.isEmpty, Banking.isValidIBAN(iban) { parsed.checks.append(Finding("chk.format_only")) }
        if info.crc32 == nil, problems.isEmpty { parsed.checks.append(Finding("chk.crc_missing")) }

        // Platba+F: invoice data embedded in X-INV.
        if let inv = values["X-INV"], inv.uppercased().hasPrefix("SID*") {
            let (_, invPairs, _) = PaymentParser.attributes(inv)
            var v: [String: String] = [:]
            for (k, value) in invPairs where v[k] == nil { v[k] = value }
            info.invoice = InvoiceInfo(id: v["ID"], issued: PaymentParser.isoDate(v["DD"]), taxPoint: PaymentParser.isoDate(v["DUZP"]),
                                       issuerIco: v["INI"], issuerVat: v["VII"], base: v["TB0"].flatMap(PaymentParser.normalizedAmount),
                                       vat: v["T0"].flatMap(PaymentParser.normalizedAmount), total: v["AM"].flatMap(PaymentParser.normalizedAmount))
        }

        if !problems.isEmpty {
            parsed.invalid = true
            let reason = LocalizedText(cs: problems.map(\.cs).joined(separator: " "), en: problems.map(\.en).joined(separator: " "))
            parsed.consequences.append(Finding("csq.invalid_payment", ["reason": .localized(reason)]))
        } else {
            let money = Format.moneyText(info.amount, currency: info.currency ?? "CZK")
            if directDebit {
                var args: [String: ArgValue] = [:]
                if let money { args["amount"] = .localized(money) }
                let from = Format.shortDateText(info.dueDate), to = Format.shortDateText(info.lastDate)
                if let from, let to {
                    args["validity"] = .localized(LocalizedText(cs: "od \(from.cs) do \(to.cs)", en: "from \(from.en) to \(to.en)"))
                } else if let to {
                    args["validity"] = .localized(LocalizedText(cs: "do \(to.cs)", en: "until \(to.en)"))
                } else {
                    args["validity"] = .localized(LocalizedText(cs: "bez omezení", en: "without an end date"))
                }
                parsed.consequences.append(Finding("csq.direct_debit", args))
            } else if let frq = info.frequency {
                var args: [String: ArgValue] = ["frequency": .localized(PaymentParser.frequencyText(frq))]
                if let money { args["amount"] = .localized(money) }
                parsed.consequences.append(Finding("csq.recurring_payment", args))
            }
            if info.paymentType == "IP" { parsed.consequences.append(Finding("csq.instant_payment")) }
        }
        parsed.content = .payment(info)
        if let url = info.url { parsed.embeddedLinks.append(url) }
        return parsed
    }

    static func frequencyText(_ frq: String) -> LocalizedText {
        switch frq.uppercased() {
        case "1D": return LocalizedText(cs: "každý den", en: "every day")
        case "1M": return LocalizedText(cs: "každý měsíc", en: "every month")
        case "3M": return LocalizedText(cs: "každé čtvrtletí", en: "every quarter")
        case "6M": return LocalizedText(cs: "každého půl roku", en: "every six months")
        case "1Y": return LocalizedText(cs: "každý rok", en: "every year")
        default: return LocalizedText(cs: "opakovaně (\(frq))", en: "repeatedly (\(frq))")
        }
    }

    /// CRC32 over the payload without the CRC32 attribute, in the canonical (key-sorted) form or
    /// as written. Either match counts; the CRC never proves who created the code.
    static func crcMatches(_ text: String, crc: String) -> Bool {
        let parts = text.split(separator: "*", omittingEmptySubsequences: false).map(String.init)
        let header = parts.prefix(2).joined(separator: "*")
        let body = parts.dropFirst(2).filter { !$0.isEmpty && !$0.uppercased().hasPrefix("CRC32:") }
        let asWritten = ([header] + body).joined(separator: "*")
        let canonical = ([header] + body.sorted()).joined(separator: "*")
        return [asWritten, canonical].contains { Banking.crc32($0) == crc.uppercased() }
    }

    // MARK: QR Faktura (SID)

    func sid(_ text: String) -> Parsed {
        let (_, pairs, _) = PaymentParser.attributes(text)
        var v: [String: String] = [:]
        for (k, value) in pairs where v[k] == nil { v[k] = value }
        let acc = (v["ACC"] ?? "").split(separator: "+").first.map(String.init)?.uppercased()
        var info = InvoiceDocInfo(id: v["ID"], issued: PaymentParser.isoDate(v["DD"]), due: PaymentParser.isoDate(v["DT"]),
                                  taxPoint: PaymentParser.isoDate(v["DUZP"]), total: v["AM"].flatMap(PaymentParser.normalizedAmount),
                                  currency: v["CC"]?.uppercased() ?? "CZK", vs: v["VS"], issuerIco: v["INI"], issuerVat: v["VII"],
                                  base: v["TB0"].flatMap(PaymentParser.normalizedAmount), vat: v["T0"].flatMap(PaymentParser.normalizedAmount),
                                  iban: acc)
        var parsed = Parsed(type: .sid, content: .invoice(info))
        if let acc, !acc.isEmpty {
            if Banking.isValidIBAN(acc) {
                parsed.checks.append(Finding("chk.iban_valid"))
                if let cz = Banking.czechAccount(fromIBAN: acc) {
                    info.domestic = cz.domestic
                    info.bankCode = cz.bankCode
                    info.bankName = bankName(cz.bankCode)
                }
            } else {
                parsed.invalid = true
                parsed.consequences.append(Finding("csq.invalid_payment", ["reason": .localized(LocalizedText(
                    cs: "Číslo účtu (IBAN) nemá platný kontrolní součet.", en: "The account number (IBAN) has an invalid checksum."))]))
            }
        }
        parsed.content = .invoice(info)
        return parsed
    }

    // MARK: EPC / GiroCode

    func epc(_ raw: String) -> Parsed {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func line(_ i: Int) -> String? { i < lines.count && !lines[i].isEmpty ? lines[i] : nil }
        let iban = (line(6) ?? "").filter { !$0.isWhitespace }.uppercased()
        var info = TransferInfo(standard: "epc", version: line(1), bic: line(4), name: line(5), iban: iban)
        if let amountField = line(7), amountField.count > 3 {
            info.currency = String(amountField.prefix(3)).uppercased()
            info.amount = PaymentParser.normalizedAmount(String(amountField.dropFirst(3)))
        }
        info.purpose = line(8)
        if let ref = line(9) {
            info.reference = ref
            info.referenceType = ref.uppercased().hasPrefix("RF") ? "RF" : "REF"
        }
        info.text = line(10)
        var parsed = Parsed(type: .epc, content: .transfer(info))
        validateTransfer(&parsed, iban: iban, amountRaw: line(7).map { String($0.dropFirst(3)) }, amount: info.amount)
        if info.referenceType == "RF", let ref = info.reference, !Banking.isValidCreditorReference(ref) {
            markInvalid(&parsed, LocalizedText(cs: "Referenční číslo nemá platný kontrolní součet.", en: "The reference has an invalid checksum."))
        }
        return parsed
    }

    // MARK: Swiss QR-bill

    func swiss(_ raw: String) -> Parsed {
        let lines = raw.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func line(_ i: Int) -> String? { i < lines.count && !lines[i].isEmpty ? lines[i] : nil }
        func address(_ start: Int) -> (name: String?, summary: String?) {
            guard let name = line(start + 1) else { return (nil, nil) }
            let type = line(start) ?? "S"
            var parts = [name]
            if type == "S" {
                let street = [line(start + 2), line(start + 3)].compactMap { $0 }.joined(separator: " ")
                let town = [line(start + 4), line(start + 5)].compactMap { $0 }.joined(separator: " ")
                parts += [street, town].filter { !$0.isEmpty }
            } else {
                parts += [line(start + 2), line(start + 3)].compactMap { $0 }
            }
            return (name, parts.joined(separator: ", "))
        }
        let iban = (line(3) ?? "").filter { !$0.isWhitespace }.uppercased()
        let creditor = address(4)
        var info = TransferInfo(standard: "spc", version: line(1), name: creditor.name, creditor: creditor.summary, iban: iban)
        info.amount = line(18).flatMap(PaymentParser.normalizedAmount)
        info.currency = line(19)?.uppercased()
        if let debtorName = line(21) {
            let town = line(25)
            info.debtor = [debtorName, town].compactMap { $0 }.joined(separator: ", ")
        }
        info.referenceType = line(27)
        info.reference = line(28)
        info.message = line(29)
        var parsed = Parsed(type: .spc, content: .transfer(info))
        validateTransfer(&parsed, iban: iban, amountRaw: line(18), amount: info.amount)
        if info.referenceType == "QRR", let ref = info.reference, !Banking.isValidQRR(ref) {
            markInvalid(&parsed, LocalizedText(cs: "Referenční číslo QR faktury nemá platný kontrolní součet.", en: "The QR reference has an invalid checksum."))
        }
        if info.referenceType == "SCOR", let ref = info.reference, !Banking.isValidCreditorReference(ref) {
            markInvalid(&parsed, LocalizedText(cs: "Referenční číslo nemá platný kontrolní součet.", en: "The reference has an invalid checksum."))
        }
        return parsed
    }

    private func validateTransfer(_ parsed: inout Parsed, iban: String, amountRaw: String?, amount: String?) {
        if Banking.isValidIBAN(iban) {
            parsed.checks.append(Finding("chk.iban_valid"))
            parsed.checks.append(Finding("chk.format_only"))
        } else {
            markInvalid(&parsed, LocalizedText(cs: "Číslo účtu (IBAN) nemá platný kontrolní součet.", en: "The account number (IBAN) has an invalid checksum."))
        }
        if let amountRaw, !amountRaw.isEmpty, amount == nil {
            markInvalid(&parsed, LocalizedText(cs: "Částka „\(amountRaw)“ není číslo.", en: "The amount “\(amountRaw)” is not a number."))
        }
    }

    private func markInvalid(_ parsed: inout Parsed, _ reason: LocalizedText) {
        parsed.invalid = true
        if let i = parsed.consequences.firstIndex(where: { $0.id == "csq.invalid_payment" }),
           case .localized(let existing) = parsed.consequences[i].args["reason"] {
            parsed.consequences[i].args["reason"] = .localized(LocalizedText(cs: existing.cs + " " + reason.cs, en: existing.en + " " + reason.en))
        } else {
            parsed.consequences.append(Finding("csq.invalid_payment", ["reason": .localized(reason)]))
        }
        parsed.checks.removeAll { $0.id == "chk.format_only" }
    }

    // MARK: EMVCo merchant-presented QR

    func emvco(_ text: String) -> Parsed? {
        guard text.hasPrefix("000201"), text.count > 20 else { return nil }
        var fields: [String: String] = [:]
        var i = text.startIndex
        while i < text.endIndex {
            guard let tagEnd = text.index(i, offsetBy: 2, limitedBy: text.endIndex),
                  let lenEnd = text.index(tagEnd, offsetBy: 2, limitedBy: text.endIndex),
                  let len = Int(text[tagEnd..<lenEnd]),
                  let valueEnd = text.index(lenEnd, offsetBy: len, limitedBy: text.endIndex) else { return nil }
            fields[String(text[i..<tagEnd])] = String(text[lenEnd..<valueEnd])
            i = valueEnd
        }
        guard fields["00"] == "01", let crc = fields["63"], crc.count == 4 else { return nil }
        let info = EMVCoInfo(merchant: fields["59"], city: fields["60"], country: fields["58"], amount: fields["54"], currencyCode: fields["53"])
        var parsed = Parsed(type: .emvco, content: .emvco(info))
        let signed = text.dropLast(4)
        if String(format: "%04X", PaymentParser.crc16(Data(signed.utf8))) != crc.uppercased() {
            parsed.invalid = true
            parsed.consequences.append(Finding("csq.invalid_payment", ["reason": .localized(LocalizedText(
                cs: "Kontrolní součet kódu nesedí.", en: "The code's checksum doesn't match."))]))
        }
        return parsed
    }

    /// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF), as required by EMVCo.
    static func crc16(_ data: Data) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for byte in data {
            crc ^= UInt16(byte) << 8
            for _ in 0..<8 { crc = crc & 0x8000 != 0 ? (crc << 1) ^ 0x1021 : crc << 1 }
        }
        return crc
    }

    // MARK: PAY by square (detect only)

    /// Base32hex payload whose first 4 bits are the by square type 0 (PAY), version 0.
    static func isPayBySquare(_ text: String) -> Bool {
        guard text.count >= 40, text.allSatisfy({ ($0 >= "0" && $0 <= "9") || ($0 >= "A" && $0 <= "V") }) else { return false }
        return text.hasPrefix("0")
    }
}
