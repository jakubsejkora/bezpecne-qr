import Foundation

/// The result of parsing one payload, before any risk detection.
struct Parsed {
    var type: CodeType
    var content: CodeContent
    var subtype: LinkSubtype?
    var sensitivity: Sensitivity?
    /// The code is broken or inconsistent (blocks the hand-off).
    var invalid = false
    var decodeOnly = false
    /// Consequences and checks that follow from the format alone (invalid IBAN, standing order…).
    var consequences: [Finding] = []
    var checks: [Finding] = []
    /// Links found inside the payload (contact URLs, text entities, intent fallback…), analysed
    /// with the URL rules.
    var embeddedLinks: [String] = []
    /// The link the network inspector should look at.
    var inspectTarget: URL?
}

/// Decides what a payload is and dispatches to the type parsers. The order matters: specific
/// prefixes first, generic URL and text last.
struct Classifier {
    let rules: RuleSet

    func parse(_ code: ScannedCode) -> Parsed {
        let raw = code.text
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = text.uppercased()
        let lower = text.lowercased()

        // Payments and invoices
        if upper.hasPrefix("SPD*") || upper.hasPrefix("SCD*") { return PaymentParser(rules: rules).spd(text) }
        if upper.hasPrefix("SID*") { return PaymentParser(rules: rules).sid(text) }
        if firstLine(text).uppercased() == "BCD" { return PaymentParser(rules: rules).epc(raw) }
        if firstLine(text).uppercased() == "SPC" { return PaymentParser(rules: rules).swiss(raw) }
        for scheme in CryptoParser.schemes where lower.hasPrefix(scheme + ":") {
            return CryptoParser().parse(text, scheme: scheme)
        }
        if lower.hasPrefix("lnurl1") { return CryptoParser().parse("lightning:" + text, scheme: "lightning") }

        // Security-sensitive codes (the sensitivity gate is applied by the parsers themselves)
        if lower.hasPrefix("otpauth-migration://") { return SecurityParser().otpMigration(text) }
        if lower.hasPrefix("otpauth://") { return SecurityParser().otp(text) }
        if lower.hasPrefix("wc:") { return SecurityParser().walletConnect(text) }
        if upper.hasPrefix("FIDO:/") { return SecurityParser().fido(text) }
        if let login = SecurityParser().login(text) { return login }
        if let seed = SecurityParser().seedPhrase(text) { return seed }

        // Structured formats
        if upper.hasPrefix("WIFI:") { return DeviceParser().wifi(text) }
        if upper.hasPrefix("BEGIN:VCARD") || upper.hasPrefix("MECARD:") || upper.hasPrefix("BIZCARD:") {
            return ContactParser().parse(text)
        }
        if upper.hasPrefix("BEGIN:VEVENT") || upper.hasPrefix("BEGIN:VCALENDAR") { return DeviceParser().event(text) }
        if upper.hasPrefix("SMSTO:") || upper.hasPrefix("MMSTO:") || lower.hasPrefix("sms:") || lower.hasPrefix("smsto:") {
            return CommParser(rules: rules).sms(text)
        }
        if lower.hasPrefix("tel:") { return CommParser(rules: rules).tel(String(text.dropFirst(4))) }
        if lower.hasPrefix("mailto:") || upper.hasPrefix("MATMSG:") { return CommParser(rules: rules).mail(text, rules: rules) }
        if lower.hasPrefix("geo:") { return DeviceParser().geo(text) }
        if upper.hasPrefix("HC1:") { return DeviceParser().healthCertificate() }
        if let bcbp = DeviceParser().boardingPass(text) { return bcbp }
        if let emv = PaymentParser(rules: rules).emvco(text) { return emv }
        if PaymentParser.isPayBySquare(text) {
            return Parsed(type: .payBySquare, content: .payBySquare, decodeOnly: true)
        }

        // Schemes that must never be opened as normal links
        if lower.hasPrefix("javascript:") { return DeviceParser().script(text) }
        if lower.hasPrefix("data:") { return DeviceParser().dataURI(text) }
        if lower.hasPrefix("intent:") { return LinkParser(rules: rules).intent(text) }
        if lower.hasPrefix("itms-services:") { return LinkParser(rules: rules).appInstall(text) }
        if lower.hasPrefix("webcal:") { return LinkParser(rules: rules).webcal(text) }
        if lower.hasPrefix("market:") { return LinkParser(rules: rules).market(text) ?? DeviceParser().text(text, rules: rules) }

        // Links
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            return LinkParser(rules: rules).parse(text)
        }
        if lower.matches("^www\\.[a-z0-9-]+(\\.[a-z0-9-]+)+(/\\S*)?$") {
            return LinkParser(rules: rules).parse("https://" + text)
        }

        return DeviceParser().text(raw.trimmingCharacters(in: .whitespacesAndNewlines), rules: rules)
    }

    private func firstLine(_ s: String) -> String {
        String(s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r" }).first ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
}
