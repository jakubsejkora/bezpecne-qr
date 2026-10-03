import Foundation

/// SMS, phone and e-mail codes, with the Czech premium-rate rules (APMS Kodex 5.6).
struct CommParser {
    let rules: RuleSet

    // MARK: SMS

    func sms(_ text: String) -> Parsed {
        var number = ""
        var body = ""
        let lower = text.lowercased()
        if lower.hasPrefix("smsto:") || lower.hasPrefix("mmsto:") {
            // SMSTO:number:body
            let rest = String(text.dropFirst(6))
            if let colon = rest.firstIndex(of: ":") {
                number = String(rest[..<colon])
                body = String(rest[rest.index(after: colon)...])
            } else {
                number = rest
            }
        } else {
            // sms:number?body=… / sms:number;?&body=… / SMS:number:body
            let rest = String(text.dropFirst(4))
            if let q = rest.firstIndex(where: { $0 == "?" || $0 == ";" }) {
                number = String(rest[..<q])
                let query = rest[rest.index(after: q)...].drop(while: { $0 == "?" || $0 == "&" })
                for pair in query.split(separator: "&") {
                    let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                    if kv.first?.lowercased() == "body", kv.count > 1 { body = kv[1].percentDecoded }
                }
            } else if let colon = rest.firstIndex(of: ":") {
                number = String(rest[..<colon])
                body = String(rest[rest.index(after: colon)...])
            } else {
                number = rest
            }
        }
        number = number.percentDecoded.filter { !$0.isWhitespace }
        body = body.trimmingCharacters(in: .whitespacesAndNewlines)

        var info = SMSInfo(number: number, numberDisplay: PhoneFormat.display(number), body: body)
        var parsed = Parsed(type: .sms, content: .sms(info))
        let shortNumber = CommParser.shortCode(number)

        if shortNumber == rules.premium.sms.charity.number {
            info.charity = true
            info.numberDisplay = shortNumber
            let recurring = body.folded.contains(rules.premium.sms.charity.recurringKeyword.folded)
            parsed.consequences.append(Finding("csq.charity_sms", recurring ? ["recurring": .localized(LocalizedText(
                cs: "DMS ROK posílá dárcovskou SMS každý měsíc po celý rok.", en: "DMS ROK sends a donor SMS every month for a year."))] : [:]))
        } else if let premium = premiumSMS(shortNumber) {
            info.premium = premium
            info.numberDisplay = CommParser.premiumDisplay(shortNumber)
            let keyword = activationKeyword(body)
            let category = premium.category ?? LocalizedText("?")
            if premium.billing == "order" {
                parsed.consequences.append(Finding("csq.premium_sms_order", ["number": .text(info.numberDisplay), "category": .localized(category)]))
            } else {
                var detail = premium.billing == "received"
                    ? LocalizedText(cs: "Platíte za každou přijatou SMS.", en: "You pay for every SMS you receive.")
                    : LocalizedText(cs: "Platíte při odeslání.", en: "Charged when sent.")
                if let keyword {
                    detail = LocalizedText(cs: detail.cs + " Slovo \(keyword) může spustit předplatné.",
                                           en: detail.en + " The word \(keyword) may start a subscription.")
                }
                parsed.consequences.append(Finding("csq.premium_sms", [
                    "price": .text(premium.price ?? "?"), "number": .text(info.numberDisplay),
                    "category": .localized(category), "detail": .localized(detail),
                ]))
            }
        } else {
            parsed.checks.append(Finding("chk.no_premium"))
        }
        parsed.content = .sms(info)
        return parsed
    }

    /// The number without a +420 / 00420 prefix, digits only.
    static func shortCode(_ number: String) -> String {
        var n = number
        if n.hasPrefix("+420") { n = String(n.dropFirst(4)) } else if n.hasPrefix("00420") { n = String(n.dropFirst(5)) }
        return n.filter(\.isASCIIDigit).count == n.count ? n : number
    }

    func premiumSMS(_ number: String) -> PremiumInfo? {
        guard number.allSatisfy(\.isASCIIDigit) else { return nil }
        for rule in rules.premium.sms.rules where number.count == rule.digits && number.matches(rule.pattern) {
            let prefix = String(number.prefix(3))
            var price: String?
            if rule.price == "last2" { price = "\(Int(number.suffix(2)) ?? 0) Kč" }
            if rule.price == "last3" { price = "\(Int(number.suffix(3)) ?? 0) Kč" }
            return PremiumInfo(prefix: prefix, digits: rule.digits, price: price, billing: rule.billing,
                               category: rules.premium.sms.categories[prefix])
        }
        return nil
    }

    /// "9021199" → "902 11 99", "90211999" → "902 11 999", "90206" → "902 06".
    static func premiumDisplay(_ n: String) -> String {
        let c = Array(n)
        switch c.count {
        case 5: return "\(String(c[0..<3])) \(String(c[3...]))"
        case 7, 8: return "\(String(c[0..<3])) \(String(c[3..<5])) \(String(c[5...]))"
        default: return n
        }
    }

    func activationKeyword(_ body: String) -> String? {
        rules.premium.sms.activationKeywords.first { body.containsFoldedPhrase($0.folded) }
    }

    // MARK: Phone

    func tel(_ rawNumber: String) -> Parsed {
        let number = rawNumber.percentDecoded.filter { !$0.isWhitespace && $0 != "-" && $0 != "(" && $0 != ")" && $0 != "." }
        var info = PhoneInfo(number: number, numberDisplay: PhoneFormat.display(number))
        var parsed = Parsed(type: .tel, content: .phone(info))

        // MMI / USSD codes (call forwarding etc.)
        if number.hasPrefix("*") || number.hasPrefix("#") {
            let mmi = mmiInfo(number)
            info.mmi = mmi
            info.numberDisplay = CommParser.mmiDisplay(number)
            if let mmi, mmi.action == "activation", mmi.target != nil {
                parsed.consequences.append(Finding("csq.call_forwarding", ["target": .text(mmi.target ?? "")]))
            }
            parsed.content = .phone(info)
            return parsed
        }

        if let national = PhoneFormat.czechNational(number) {
            info.country = "CZ"
            if let premium = premiumVoice(national) {
                info.premium = premium.info
                info.kind = LocalizedText(cs: "prémiová linka", en: "premium line")
                info.numberDisplay = premium.display
                parsed.consequences.append(Finding("csq.premium_call", [
                    "price": .localized(premium.priceText), "number": .text(premium.display),
                    "category": .localized(premium.info.category ?? LocalizedText("?")),
                ]))
            } else {
                info.kind = CommParser.czechKind(national)
                parsed.checks.append(Finding("chk.no_premium"))
            }
        } else if number.hasPrefix("+") || number.hasPrefix("00") {
            let digits = number.hasPrefix("+") ? String(number.dropFirst()) : String(number.dropFirst(2))
            let ccLen = PhoneFormat.countryCodeLength(digits)
            let cc = "+" + String(digits.prefix(ccLen))
            info.kind = LocalizedText(cs: "mezinárodní číslo", en: "international number")
            let country: LocalizedText
            if let w = rules.wangiri.first(where: { $0.cc == cc }) {
                country = LocalizedText(cs: w.cs, en: w.en)
                parsed.consequences.append(Finding("csq.international_call", ["country": .localized(country)]))
                info.country = CommParser.isoForCallingCode[cc]
            } else {
                country = CommParser.callingCodeCountries[cc] ?? LocalizedText(cc)
                info.country = CommParser.isoForCallingCode[cc]
                if cc != "+420" {
                    parsed.consequences.append(Finding("csq.international_call", ["country": .localized(country)]))
                }
            }
        } else {
            parsed.checks.append(Finding("chk.no_premium"))
        }
        parsed.content = .phone(info)
        return parsed
    }

    struct PremiumVoice {
        var info: PremiumInfo
        var display: String
        var priceText: LocalizedText
    }

    /// Czech premium voice numbers: 900/906/909 = AB Kč per minute, 905 = 10×AB per call,
    /// 908 = AB per call, 976 = internet access.
    func premiumVoice(_ national: String) -> PremiumVoice? {
        guard national.count == 9 else { return nil }
        let prefix = String(national.prefix(3))
        guard let rule = rules.premium.voice[prefix] else { return nil }
        let c = Array(national)
        let ab = Int(String(c[3..<5])) ?? 0
        let display = "\(prefix) \(String(c[3..<5])) \(String(c[5...]))"
        let price: String?
        let text: LocalizedText
        switch rule.pricing {
        case "perMinute":
            price = "\(ab) Kč/min"
            text = LocalizedText(cs: "\(ab) Kč za minutu", en: "\(ab) CZK per minute")
        case "perCall":
            let amount = rule.price == "10xAB" ? ab * 10 : ab
            price = "\(amount) Kč/hovor"
            text = LocalizedText(cs: "\(amount) Kč za hovor", en: "\(amount) CZK per call")
        default:
            price = nil
            text = LocalizedText(cs: "cenu z čísla nepoznáme", en: "the price isn't encoded in the number")
        }
        let info = PremiumInfo(prefix: prefix, price: price, billing: rule.pricing, category: LocalizedText(cs: rule.cs, en: rule.en))
        return PremiumVoice(info: info, display: display, priceText: text)
    }

    static func czechKind(_ national: String) -> LocalizedText {
        guard let first = national.first else { return LocalizedText(cs: "telefonní číslo", en: "phone number") }
        let two = String(national.prefix(2)), three = String(national.prefix(3))
        if first == "2" { return LocalizedText(cs: "pevná linka · Praha", en: "landline · Prague") }
        if ["31", "32", "35", "37", "38", "39", "41", "46", "47", "48", "49", "51", "53", "54", "55", "56", "57", "58", "59"].contains(two) {
            return LocalizedText(cs: "pevná linka", en: "landline")
        }
        if first == "6" || first == "7" { return LocalizedText(cs: "mobilní číslo", en: "mobile number") }
        if three == "800" { return LocalizedText(cs: "bezplatná linka", en: "free-phone number") }
        if ["810", "811", "812", "813", "814", "815", "816", "817", "818", "819", "840", "841", "842", "843", "844", "845", "846", "847", "848", "849"].contains(three) {
            return LocalizedText(cs: "linka se sdílenými náklady", en: "shared-cost number")
        }
        return LocalizedText(cs: "telefonní číslo", en: "phone number")
    }

    func mmiInfo(_ code: String) -> MMIInfo? {
        let services: [String: LocalizedText] = [
            "21": LocalizedText(cs: "přesměrování všech hovorů", en: "forward all calls"),
            "61": LocalizedText(cs: "přesměrování nepřijatých hovorů", en: "forward unanswered calls"),
            "62": LocalizedText(cs: "přesměrování při nedostupnosti", en: "forward when unreachable"),
            "67": LocalizedText(cs: "přesměrování při obsazení", en: "forward when busy"),
            "002": LocalizedText(cs: "přesměrování všech hovorů (všechny typy)", en: "forward all calls (all types)"),
            "004": LocalizedText(cs: "podmíněné přesměrování hovorů", en: "conditional call forwarding"),
        ]
        if rules.premium.mmi.activation.contains(where: { code.matches($0) }) {
            let caps = code.captures("^\\*{1,2}([0-9]{2,3})\\*([^*#]+)")
            let service = caps?[1].flatMap { services[$0] } ?? LocalizedText(cs: "změna nastavení hovorů", en: "call settings change")
            let target = caps?[2].map { PhoneFormat.display($0) }
            return MMIInfo(action: "activation", service: service, target: target)
        }
        if rules.premium.mmi.status.contains(where: { code.matches($0) }) {
            let caps = code.captures("^\\*#([0-9]{2,3})#")
            let service = caps?[1].flatMap { services[$0] } ?? LocalizedText(cs: "dotaz na stav", en: "status query")
            return MMIInfo(action: "status", service: service)
        }
        return MMIInfo(action: "status", service: LocalizedText(cs: "servisní kód operátora", en: "operator service code"))
    }

    /// "**21*+420606000000#" → "**21*+420 606 000 000#".
    static func mmiDisplay(_ code: String) -> String {
        guard let caps = code.captures("^(\\*{1,2}[0-9]{2,3}\\*)([^*#]+)(.*)$"), let head = caps[1], let target = caps[2] else { return code }
        return head + PhoneFormat.display(target) + (caps[3] ?? "")
    }

    static let callingCodeCountries: [String: LocalizedText] = [
        "+420": LocalizedText(cs: "Česko", en: "Czechia"), "+421": LocalizedText(cs: "Slovensko", en: "Slovakia"),
        "+49": LocalizedText(cs: "Německo", en: "Germany"), "+43": LocalizedText(cs: "Rakousko", en: "Austria"),
        "+48": LocalizedText(cs: "Polsko", en: "Poland"), "+36": LocalizedText(cs: "Maďarsko", en: "Hungary"),
        "+44": LocalizedText(cs: "Spojené království", en: "United Kingdom"), "+1": LocalizedText(cs: "USA / Kanada", en: "USA / Canada"),
        "+33": LocalizedText(cs: "Francie", en: "France"), "+39": LocalizedText(cs: "Itálie", en: "Italy"),
        "+34": LocalizedText(cs: "Španělsko", en: "Spain"), "+31": LocalizedText(cs: "Nizozemsko", en: "Netherlands"),
        "+380": LocalizedText(cs: "Ukrajina", en: "Ukraine"), "+7": LocalizedText(cs: "Rusko / Kazachstán", en: "Russia / Kazakhstan"),
        "+90": LocalizedText(cs: "Turecko", en: "Turkey"), "+41": LocalizedText(cs: "Švýcarsko", en: "Switzerland"),
    ]

    static let isoForCallingCode: [String: String] = [
        "+420": "CZ", "+421": "SK", "+49": "DE", "+43": "AT", "+48": "PL", "+36": "HU", "+44": "GB", "+1": "US",
        "+33": "FR", "+39": "IT", "+34": "ES", "+31": "NL", "+380": "UA", "+7": "RU", "+90": "TR", "+41": "CH",
        "+94": "LK", "+211": "SS", "+216": "TN", "+225": "CI", "+247": "AC", "+251": "ET", "+265": "MW", "+678": "VU",
    ]

    // MARK: E-mail

    func mail(_ text: String, rules: RuleSet) -> Parsed {
        var to = "", subject: String?, body: String?, cc: String?
        if text.uppercased().hasPrefix("MATMSG:") {
            for field in DeviceParser.splitEscaped(String(text.dropFirst(7)), separator: ";") {
                guard let colon = field.firstIndex(of: ":") else { continue }
                let key = field[..<colon].uppercased(), value = String(field[field.index(after: colon)...])
                switch key {
                case "TO": to = value
                case "SUB": subject = value
                case "BODY": body = value
                default: break
                }
            }
        } else {
            let rest = String(text.dropFirst("mailto:".count))
            let parts = rest.split(separator: "?", maxSplits: 1).map(String.init)
            to = (parts.first ?? "").percentDecoded
            for pair in parts.count > 1 ? parts[1].split(separator: "&") : [] {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                switch kv[0].lowercased() {
                case "subject": subject = kv[1].percentDecoded
                case "body": body = kv[1].percentDecoded
                case "cc": cc = kv[1].percentDecoded
                case "to": to = to.isEmpty ? kv[1].percentDecoded : to
                default: break
                }
            }
        }
        to = to.trimmingCharacters(in: .whitespaces)
        let domain = to.split(separator: "@").last.map { String($0).lowercased() } ?? ""
        let host = DomainKit.asciiHost(domain)
        let info = EmailInfo(to: to, cc: cc, subject: subject, body: body, host: host,
                             registrable: DomainKit.registrable(host, privateSuffixes: rules.freeHosts))
        var parsed = Parsed(type: .mailto, content: .email(info))
        if !host.isEmpty { parsed.embeddedLinks.append("https://\(host)/") }
        return parsed
    }
}
