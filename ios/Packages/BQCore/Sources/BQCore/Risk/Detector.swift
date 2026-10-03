import Foundation

/// Turns parsed content, the link inspection and printed context into scored evidence,
/// consequences and checks. Rules come from shared/rules; see docs/risk-engine.md.
struct Detector {
    let rules: RuleSet
    let now: Date

    // MARK: - Hosts

    /// Lexical evidence about one host. `scanned` adds the scanned link's transport findings.
    func hostEvidence(host rawHost: String, scheme: String? = nil, port: Int? = nil, userinfo: String? = nil,
                      scanned: Bool = false) -> [Finding] {
        let host = rawHost.lowercased()
        var out: [Finding] = []
        let registrable = DomainKit.registrable(host, privateSuffixes: rules.freeHosts)
        let displayRegistrable = DomainKit.displayHost(registrable)

        if scanned, scheme == "http" { out.append(Finding("url.transport.http")) }
        if let ip = IPAddress(host) {
            out.append(Finding("url.transport.ip_literal", ["ip": .text(ip.description)]))
            return out
        }
        if scanned, let port, port != 80, port != 443 {
            out.append(Finding("url.transport.unusual_port", ["port": .text(String(port))]))
        }
        if scanned, let userinfo, !userinfo.isEmpty {
            out.append(Finding("url.identity.userinfo_trick", ["fake": .text(userinfo), "real": .text(host)]))
        }

        // Identity: confusable IDN first; a lexical brand match only on plain ASCII labels.
        let confusable = confusableIDN(host)
        if let confusable { out.append(confusable) }
        if confusable == nil, !isAllowlisted(host), let brand = brandMatch(host) {
            out.append(Finding("url.identity.brand_lookalike", [
                "brand": .text(brand.name), "domain": .text(displayRegistrable), "official": .text(brand.official.first ?? ""),
            ]))
        }

        // Weak provenance
        let tld = DomainKit.tld(host)
        if rules.tlds.commonLegit.tlds.contains(tld) {
            out.append(Finding(rules.tlds.commonLegit.signal, ["tld": .text(tld)]))
        } else if rules.tlds.abused.tlds.contains(tld) {
            out.append(Finding(rules.tlds.abused.signal, ["tld": .text(tld)]))
        }
        if let parent = rules.freeHosts.first(where: { DomainKit.host(host, isWithin: $0) && host != $0 }) {
            out.append(Finding("url.host.free_hosting", ["provider": .text(rules.freeHostProviders[parent] ?? parent)]))
        }
        if hasRandomLabel(host) { out.append(Finding("url.host.random_label")) }
        return out
    }

    func isAllowlisted(_ host: String) -> Bool {
        if parkingCity(host) != nil { return true }
        if DomainKit.host(host, isWithin: "gov.cz") { return true }
        if rules.shorteners.contains(host) || rules.qrRedirectors.contains(host) { return true }
        return false
    }

    func parkingCity(_ host: String) -> ParkingCity? {
        rules.parking.first { city in city.official.contains { DomainKit.host(host, isWithin: $0) } }
    }

    /// A brand whose token appears as a whole label or hyphen-separated part of a host that does
    /// not belong to the brand. Tokens of 7+ characters also match as substrings.
    func brandMatch(_ host: String) -> Brand? {
        let labels = DomainKit.labels(host)
        guard labels.count >= 2 else { return nil }
        let candidateLabels = labels.dropLast() // never the TLD
        let parts = Set(candidateLabels.flatMap { $0.split(separator: "-").map(String.init) } + candidateLabels)
        for brand in rules.brands {
            if brand.official.contains(where: { DomainKit.host(host, isWithin: $0) }) { continue }
            for token in brand.tokens {
                let t = token.lowercased()
                if parts.contains(t) { return brand }
                if t.count >= 7, candidateLabels.contains(where: { $0.contains(t) }) { return brand }
            }
        }
        return nil
    }

    func hasRandomLabel(_ host: String) -> Bool {
        let labels = DomainKit.labels(host).dropLast()
        for label in labels where !label.hasPrefix("xn--") {
            if label.count >= 40 { return true }
            let compact = label.replacingOccurrences(of: "-", with: "")
            let digits = compact.filter(\.isNumber).count
            let letters = compact.filter(\.isLetter).count
            if compact.count >= 12, digits >= 3, letters >= 3, compact.entropy >= 3.3 { return true }
            if compact.count >= 16, compact.matches("^[0-9a-f]+$") { return true }
        }
        return false
    }

    // MARK: Confusable IDN

    static let confusables: [Character: Character] = [
        // Cyrillic
        "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s",
        "ԁ": "d", "ӏ": "l", "к": "k", "м": "m", "н": "h", "т": "t", "в": "b", "п": "n", "ь": "b", "ү": "y",
        "һ": "h", "ԛ": "q", "ԝ": "w", "ɡ": "g", "ɑ": "a", "ı": "i",
        // Greek
        "α": "a", "ο": "o", "ρ": "p", "ν": "v", "τ": "t", "ε": "e", "ι": "i", "κ": "k", "χ": "x", "υ": "u",
        "η": "n", "ω": "w",
    ]

    static func script(of scalar: Unicode.Scalar) -> String? {
        switch scalar.value {
        case 0x41...0x5A, 0x61...0x7A, 0xC0...0x24F: return "latin"
        case 0x370...0x3FF: return "greek"
        case 0x400...0x52F: return "cyrillic"
        default: return nil
        }
    }

    static func skeleton(_ label: String) -> String {
        String(label.lowercased().map { confusables[$0] ?? $0 }).folded
    }

    func confusableIDN(_ host: String) -> Finding? {
        let display = DomainKit.displayHost(host)
        guard display != host else { return nil }
        let labels = DomainKit.labels(display).dropLast()
        for label in labels where !label.allSatisfy(\.isASCII) {
            let scripts = Set(label.unicodeScalars.compactMap(Detector.script(of:)))
            let skeleton = Detector.skeleton(label)
            let skeletonParts = skeleton.split(separator: "-").map(String.init) + [skeleton]
            let brandToken = rules.brands.flatMap(\.tokens).first { skeletonParts.contains($0) }
            if scripts.count > 1 || brandToken != nil {
                let registrable = DomainKit.displayHost(DomainKit.registrable(host, privateSuffixes: rules.freeHosts))
                return Finding("url.identity.confusable_idn", [
                    "domain": .text(registrable), "looksLike": .text(brandToken ?? skeleton),
                ])
            }
        }
        return nil
    }

    // MARK: - Inspection (network) evidence

    struct InspectionResult {
        var evidence: [Finding] = []
        var consequences: [Finding] = []
        var checks: [Finding] = []
    }

    func inspectionFindings(_ inspection: Inspection, scannedHost: String?) -> InspectionResult {
        var r = InspectionResult()
        let finalHost = inspection.final?.host ?? scannedHost ?? ""
        let finalRegistrable = inspection.final?.registrable ?? DomainKit.registrable(finalHost, privateSuffixes: rules.freeHosts)

        // Domain checks
        if let domain = inspection.domain {
            let name = DomainKit.displayHost(domain.name ?? finalRegistrable)
            if domain.quad9 == .blocked {
                r.evidence.append(Finding("intel.quad9_block", ["domain": .text(name)]))
            } else if domain.quad9 == .ok {
                r.checks.append(Finding("chk.quad9_ok"))
            }
            if let registered = Format.parseISODate(domain.registered) {
                let days = Calendar(identifier: .gregorian).dateComponents([.day], from: registered, to: now).day ?? Int.max
                let registry = Detector.shortRegistry(domain.registry)
                let date = Format.shortDateText(domain.registered) ?? LocalizedText(domain.registered ?? "")
                if days >= 0, days < 7 {
                    r.evidence.append(Finding("url.domain.age_lt7d", [
                        "days": .localized(Format.days(days)), "domain": .text(name), "date": .localized(date), "registry": .text(registry),
                    ]))
                } else if days >= 0, days < 30 {
                    r.evidence.append(Finding("url.domain.age_lt30d", ["domain": .text(name), "date": .localized(date)]))
                } else if days >= 30 {
                    r.checks.append(Finding("chk.domain_age", ["date": .localized(date), "registry": .text(registry)]))
                }
            }
        }

        // The observed chain
        let chain = inspection.chain
        if let first = chain.first, first.kind == .httpsUpgrade { r.checks.append(Finding("chk.https_upgraded")) }
        if let firstHost = chain.first.flatMap({ URL(string: $0.url)?.asciiHost }),
           rules.shorteners.contains(firstHost) || rules.qrRedirectors.contains(firstHost), inspection.final != nil, chain.count > 1 {
            r.checks.append(Finding("chk.shortener_resolved", ["host": .text(firstHost)]))
        }
        if let city = parkingCity(finalHost) ?? scannedHost.flatMap(parkingCity) {
            r.checks.append(Finding("chk.allowlisted_parking", ["city": .text(city.name)]))
        } else if DomainKit.host(finalHost, isWithin: "gov.cz") {
            r.checks.append(Finding("chk.allowlisted_gov"))
        }
        let redirects = chain.filter { ($0.status ?? 0) >= 300 && ($0.status ?? 0) < 400 || $0.kind == .openRedirect || $0.kind == .metaRefresh }.count
        if redirects > 0 { r.checks.append(Finding("chk.redirects", ["count": .number(Double(redirects))])) }
        if let stop = chain.first(where: { $0.stopped == .billing }), let host = URL(string: stop.url)?.asciiHost {
            r.consequences.append(Finding("csq.billing_gateway", ["host": .text(host)]))
        }
        if let final = inspection.final, final.url.lowercased().hasPrefix("https://") {
            r.checks.append(Finding("chk.https_ok"))
        }

        // The page
        if let page = inspection.page {
            pageFindings(page, host: finalHost, registrable: finalRegistrable, into: &r)
        }
        return r
    }

    static func shortRegistry(_ registry: String?) -> String {
        guard let registry else { return "?" }
        if let paren = registry.range(of: " (") { return String(registry[..<paren.lowerBound]) }
        return registry
    }

    func pageFindings(_ page: PageFacts, host: String, registrable: String, into r: inout InspectionResult) {
        let display = DomainKit.displayHost(registrable)
        let asks = Set(page.asks)

        // A page that presents itself as a brand on a domain the brand doesn't own.
        if let claim = page.brandClaim,
           let brand = rules.brands.first(where: { $0.name.folded == claim.folded || $0.tokens.contains(claim.folded) }),
           !brand.official.contains(where: { DomainKit.host(host, isWithin: $0) }), !isAllowlisted(host) {
            r.evidence.append(Finding("url.identity.false_official", [
                "brand": .text(brand.name), "domain": .text(display), "official": .text(brand.official.first ?? ""),
            ]))
            if asks.contains(.card) {
                r.evidence.append(Finding("page.solicit.card_false_identity", ["brand": .text(brand.name)]))
            }
        }

        if asks.contains(.recoverySecret) {
            r.evidence.append(Finding("page.solicit.recovery_secret"))
        }

        // A recurring charge matters when it can land on the phone bill: the page signs you up with
        // a phone number / SMS code, or says it is billed by the operator or via premium SMS.
        // Then it is always a consequence; with an independent deceptive promise it is scored (§4.3b).
        if let offer = page.offer {
            let activation = asks.contains(.phone) || asks.contains(.otp)
                || page.extract.contains { $0.folded.matches(rules.dcb.patterns.activation) }
            let pageText = ([offer.text] + page.extract).map(\.folded)
            let operatorBilled = pageText.contains { $0.matches(rules.dcb.patterns.operatorBilling) || $0.matches(rules.dcb.patterns.premiumNumber) }
            if activation || operatorBilled {
                r.consequences.append(Finding("csq.subscription_charge", ["offer": .text(offer.text)]))
            }
            if let promise = offer.promise, activation {
                r.evidence.append(Finding("page.solicit.deceptive_subscription", ["promise": .text(promise), "offer": .text(offer.text)]))
            }
        }

        // Credentials on a prize / gift page.
        let sensitive = asks.intersection([.card, .password, .otp])
        if !sensitive.isEmpty, !r.evidence.contains(where: { $0.id == "page.solicit.card_false_identity" }), !isAllowlisted(host) {
            let context = ((page.title ?? "") + " " + page.extract.prefix(8).joined(separator: " ")).folded
            let prizeWords = ["vyhra", "vyhral", "vyhrajte", "darek", "gratulujeme", "zdarma"]
            if prizeWords.contains(where: { context.contains($0) }) {
                r.evidence.append(Finding("page.solicit.credentials_unrelated", ["fields": .localized(Detector.askList(sensitive))]))
            }
        }

        // What we read
        var summary = Detector.askList(asks)
        if asks.isEmpty { summary = LocalizedText(cs: "nic nevyžaduje", en: "nothing") }
        if let offer = page.offer {
            summary = LocalizedText(cs: summary.cs + " + „\(offer.text)“", en: summary.en + " + “\(offer.text)”")
        }
        r.checks.append(Finding("chk.page_extract", ["summary": .localized(summary)]))
    }

    static let askNames: [AskKind: LocalizedText] = [
        .card: LocalizedText(cs: "číslo karty", en: "a card number"),
        .phone: LocalizedText(cs: "telefonní číslo", en: "a phone number"),
        .password: LocalizedText(cs: "heslo", en: "a password"),
        .otp: LocalizedText(cs: "kód z SMS", en: "an SMS code"),
        .email: LocalizedText(cs: "e-mail", en: "an e-mail address"),
        .licencePlate: LocalizedText(cs: "SPZ", en: "a number plate"),
        .recoverySecret: LocalizedText(cs: "obnovovací frázi", en: "a recovery phrase"),
        .personalID: LocalizedText(cs: "rodné číslo", en: "a birth number"),
    ]

    static func askList(_ asks: Set<AskKind>) -> LocalizedText {
        let ordered = AskKind.allCases.filter { asks.contains($0) }.compactMap { askNames[$0] }
        return LocalizedText(cs: ordered.map(\.cs).joined(separator: ", "), en: ordered.map(\.en).joined(separator: ", "))
    }

    // MARK: - Printed text next to the code (OCR)

    func printedFindings(_ printed: PrintedContext, scannedRegistrable: String?, finalRegistrable: String?) -> [Finding] {
        guard let p = printed.printed?.lowercased(), p.contains("."),
              let printedHost = URL(string: p.hasPrefix("http") ? p : "https://\(p)")?.asciiHost else { return [] }
        let printedRegistrable = DomainKit.registrable(printedHost, privateSuffixes: rules.freeHosts)
        let actual = [scannedRegistrable, finalRegistrable].compactMap { $0 }
        guard !actual.isEmpty, !actual.contains(printedRegistrable) else { return [] }
        // Curated relationships (parking.praha.eu → zpspraha.cz) are not a mismatch.
        if let city = parkingCity(printedHost), actual.allSatisfy({ a in city.official.contains { DomainKit.host(a, isWithin: $0) || DomainKit.host($0, isWithin: a) } }) {
            return []
        }
        return [Finding("ocr.domain_mismatch", ["printed": .text(printedHost), "actual": .text(actual.last ?? "")])]
    }

    // MARK: - Payments

    func paymentEvidence(_ info: PaymentInfo) -> [Finding] {
        var out: [Finding] = []
        let texts = [info.message, info.recipientName].compactMap { $0 }
        if let phrase = safeAccountMatch(texts) {
            out.append(Finding("pay.safe_account_instruction", ["text": .text(phrase)]))
        }
        if let institution = stateInstitution(texts) {
            if info.bankCode != rules.stateAccounts.bankCode {
                let bank = info.bankName.map(Detector.shortBankName)
                    ?? (info.country.map { "zahraniční banka (\($0))" } ?? "?")
                out.append(Finding("pay.state_claim_bank_mismatch", [
                    "institution": .localized(institution.name), "bank": .text(bank), "bankCode": .text(info.bankCode ?? info.country ?? "?"),
                ]))
            }
        }
        if let country = info.country, country != "CZ" {
            let context = (info.message ?? info.recipientName ?? "")
            let czechContext = ["parkovne", "parkovani", "pokuta", "dalnice", "edalnice", "poplatek", "doplatek", "zasilka", "praha", "brno", "ostrava"]
                .contains { context.containsFoldedPhrase($0) }
            if (info.currency ?? "CZK") == "CZK" || czechContext {
                out.append(Finding("pay.context_mismatch", ["text": .text(context), "country": .localized(Banking.countryName(country))]))
            }
        }
        return out
    }

    static func shortBankName(_ name: String) -> String {
        name.replacingOccurrences(of: ", a.s.", with: "").replacingOccurrences(of: " a.s.", with: "")
            .replacingOccurrences(of: ", spořitelní družstvo", with: "").trimmed()
    }

    func safeAccountMatch(_ texts: [String]) -> String? {
        for text in texts {
            for phrase in rules.keywords.safeAccountPhrases where text.containsFoldedPhrase(phrase) {
                return text.sentence(containingFolded: phrase) ?? text
            }
        }
        return nil
    }

    func stateInstitution(_ texts: [String]) -> StateAccountRules.Institution? {
        for text in texts {
            if rules.stateAccounts.excluded.contains(where: { text.containsFoldedPhrase($0) }) { continue }
            if let inst = rules.stateAccounts.institutions.first(where: { i in i.patterns.contains { text.containsFoldedPhrase($0) } }) {
                return inst
            }
        }
        return nil
    }

    // MARK: - SMS and phone

    func smsEvidence(_ info: SMSInfo) -> [Finding] {
        guard info.premium != nil, !info.body.isEmpty else { return [] }
        var out = [Finding("sms.prefilled_premium", ["number": .text(info.numberDisplay)])]
        if let keyword = rules.premium.sms.activationKeywords.first(where: { info.body.containsFoldedPhrase($0.folded) }) {
            out.append(Finding("sms.activation_keyword", ["keyword": .text(keyword), "body": .text(info.body)]))
        }
        return out
    }

    func phoneEvidence(_ info: PhoneInfo) -> [Finding] {
        guard info.mmi == nil, info.number.hasPrefix("+") || info.number.hasPrefix("00") else { return [] }
        let digits = info.number.hasPrefix("+") ? String(info.number.dropFirst()) : String(info.number.dropFirst(2))
        let cc = "+" + digits.prefix(PhoneFormat.countryCodeLength(digits))
        guard let w = rules.wangiri.first(where: { $0.cc == cc }) else { return [] }
        return [Finding("phone.foreign_prefix", ["cc": .text(cc), "country": .localized(LocalizedText(cs: w.cs, en: w.en))])]
    }

    // MARK: - Embedded HTML (data: URIs)

    func embeddedHTMLEvidence(_ info: DataURIInfo) -> [Finding] {
        let html = info.preview.lowercased()
        guard html.contains("<input") || html.contains("<form") else { return [] }
        var fields: [LocalizedText] = []
        if html.contains("card") || html.contains("karta") || html.contains("cc-number") || html.contains("cvv") {
            fields.append(LocalizedText(cs: "číslo karty", en: "a card number"))
        }
        if html.contains("password") || html.contains("heslo") || html.contains("pin") {
            fields.append(LocalizedText(cs: "heslo", en: "a password"))
        }
        guard !fields.isEmpty else { return [] }
        return [Finding("page.solicit.credentials_unrelated", ["fields": .localized(LocalizedText(
            cs: fields.map(\.cs).joined(separator: " a "), en: fields.map(\.en).joined(separator: " and ")))])]
    }
}
