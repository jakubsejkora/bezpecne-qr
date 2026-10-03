import Foundation

/// Display formatting shared by the analyzer (finding arguments) and the UI.
public enum Format {
    static func locale(_ language: Language) -> Locale {
        Locale(identifier: language == .cs ? "cs_CZ" : "en_GB")
    }

    /// "1500.00" CZK → ("1 500", "Kč"); "480.5" → ("480,50", "Kč"); BTC keeps up to 8 decimals.
    public static func amount(_ value: String?, currency: String?, language: Language) -> (number: String, symbol: String)? {
        guard let value, let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let nf = NumberFormatter()
        nf.locale = locale(language)
        nf.numberStyle = .decimal
        let isCrypto = ["BTC", "ETH", "USDT", "USDC", "SAT"].contains(currency ?? "")
        let whole = (decimal as NSDecimalNumber).doubleValue.truncatingRemainder(dividingBy: 1) == 0
        nf.minimumFractionDigits = isCrypto ? 0 : (whole ? 0 : 2)
        nf.maximumFractionDigits = isCrypto ? 8 : 2
        if language == .cs { nf.groupingSeparator = "\u{00A0}" }
        let number = nf.string(from: decimal as NSDecimalNumber) ?? value
        return (number, symbol(currency))
    }

    public static func symbol(_ currency: String?) -> String {
        switch currency ?? "" {
        case "CZK": return "Kč"
        case "EUR": return "€"
        case "": return ""
        default: return currency ?? ""
        }
    }

    /// "1 500 Kč" / "€25".
    public static func money(_ value: String?, currency: String?, language: Language) -> String? {
        guard let a = amount(value, currency: currency, language: language) else { return nil }
        if a.symbol.isEmpty { return a.number }
        if language == .en, a.symbol == "€" { return "€\(a.number)" }
        return "\(a.number)\u{00A0}\(a.symbol)"
    }

    /// Localized money for finding arguments.
    static func moneyText(_ value: String?, currency: String?) -> LocalizedText? {
        guard let cs = money(value, currency: currency, language: .cs),
              let en = money(value, currency: currency, language: .en) else { return nil }
        return LocalizedText(cs: cs.replacingOccurrences(of: "\u{00A0}", with: " "), en: en.replacingOccurrences(of: "\u{00A0}", with: " "))
    }

    /// Groups an IBAN in blocks of four.
    public static func iban(_ iban: String) -> String {
        let compact = iban.filter { !$0.isWhitespace }
        var out = ""
        for (i, c) in compact.enumerated() {
            if i > 0, i % 4 == 0 { out.append(" ") }
            out.append(c)
        }
        return out
    }

    static let isoDate: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoDateTime: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm"
        return f
    }()

    public static func parseISODate(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        if iso.count == 10 { return isoDate.date(from: iso) }
        return isoDateTime.date(from: String(iso.prefix(16)))
    }

    /// "2026-10-15" → "15. října 2026" (cs) / "15 October 2026" (en). Unparseable text passes through.
    public static func longDate(_ iso: String?, language: Language) -> String {
        guard let iso else { return "" }
        guard let date = parseISODate(iso) else { return iso }
        let f = DateFormatter()
        f.locale = locale(language)
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.setLocalizedDateFormatFromTemplate("d MMMM y")
        return f.string(from: date)
    }

    /// "2026-09-27" → "27. 9. 2026" (cs) / "27 Sep 2026" (en).
    public static func shortDate(_ date: Date, language: Language) -> String {
        let f = DateFormatter()
        f.locale = locale(language)
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.dateFormat = language == .cs ? "d. M. yyyy" : "d MMM yyyy"
        return f.string(from: date)
    }

    static func shortDateText(_ iso: String?) -> LocalizedText? {
        guard let date = parseISODate(iso) else { return nil }
        return LocalizedText(cs: shortDate(date, language: .cs), en: shortDate(date, language: .en))
    }

    /// "2026-10-12T18:00" → "18:00".
    public static func time(_ iso: String?, language: Language) -> String? {
        guard let iso, iso.count >= 16, let date = parseISODate(iso) else { return nil }
        let f = DateFormatter()
        f.locale = locale(language)
        f.timeZone = TimeZone(identifier: "Europe/Prague")
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    /// Czech plural for days: 1 den, 2–4 dny, 5+ dní.
    static func days(_ n: Int) -> LocalizedText {
        let cs: String
        switch n {
        case 1: cs = "1 den"
        case 2...4: cs = "\(n) dny"
        default: cs = "\(n) dní"
        }
        return LocalizedText(cs: cs, en: n == 1 ? "1 day" : "\(n) days")
    }

    /// Two-letter initials of a name.
    public static func initials(_ name: String) -> String {
        let parts = name.split(whereSeparator: { $0.isWhitespace }).prefix(2)
        let letters = parts.compactMap { $0.first.map { String($0).uppercased() } }.joined()
        return letters.isEmpty ? "?" : letters
    }

    /// A stable hue (0–359) for a string, used for contact and bank colours.
    public static func hue(_ string: String) -> Int {
        var h = 0
        for scalar in string.unicodeScalars { h = (h * 31 + Int(scalar.value)) % 360 }
        return h
    }

    /// Chunks of four characters for long addresses ("bc1q w508 …").
    public static func chunked(_ s: String, size: Int = 4) -> String {
        var out = ""
        for (i, c) in s.enumerated() {
            if i > 0, i % size == 0 { out.append(" ") }
            out.append(c)
        }
        return out
    }
}

// MARK: - Phone numbers

public enum PhoneFormat {
    /// Length of the country calling code at the start of `digits` (ITU zone rules).
    static func countryCodeLength(_ digits: String) -> Int {
        let d = Array(digits)
        guard let first = d.first else { return 0 }
        let two = d.count >= 2 ? String(d[0...1]) : String(first)
        switch first {
        case "1", "7": return 1
        case "2": return ["20", "27"].contains(two) ? 2 : 3
        case "3": return ["30", "31", "32", "33", "34", "36", "39"].contains(two) ? 2 : 3
        case "4": return two == "42" ? 3 : 2
        case "5": return ["50", "59"].contains(two) ? 3 : 2
        case "6": return ["67", "68", "69"].contains(two) ? 3 : 2
        case "8": return ["81", "82", "84", "86"].contains(two) ? 2 : 3
        case "9": return ["96", "97", "99"].contains(two) ? 3 : 2
        default: return 2
        }
    }

    /// Splits national digits into readable groups: 3-3-3 for Czech numbers, otherwise groups of
    /// three with a last group of up to four.
    static func group(_ digits: String, czech: Bool) -> String {
        let chars = Array(digits)
        if czech, chars.count == 9 {
            return "\(String(chars[0..<3])) \(String(chars[3..<6])) \(String(chars[6..<9]))"
        }
        guard chars.count > 4 else { return digits }
        var groups: [String] = []
        var i = 0
        while chars.count - i > 4 {
            let remaining = chars.count - i
            if remaining == 5 { break }
            groups.append(String(chars[i..<i + 3]))
            i += 3
        }
        let rest = chars.count - i
        if rest == 5 {
            groups.append(String(chars[i..<i + 3]))
            groups.append(String(chars[(i + 3)...]))
        } else {
            groups.append(String(chars[i...]))
        }
        return groups.joined(separator: " ")
    }

    /// "+420777123456" → "+420 777 123 456"; "+2475551234" → "+247 555 1234"; "777123456" → "777 123 456".
    public static func display(_ number: String) -> String {
        let trimmed = number.filter { !$0.isWhitespace && $0 != "-" && $0 != "(" && $0 != ")" && $0 != "/" }
        if trimmed.hasPrefix("+") || trimmed.hasPrefix("00") {
            let digits = trimmed.hasPrefix("+") ? String(trimmed.dropFirst()) : String(trimmed.dropFirst(2))
            guard digits.allSatisfy(\.isASCIIDigit), !digits.isEmpty else { return number }
            let ccLen = min(countryCodeLength(digits), digits.count)
            let cc = String(digits.prefix(ccLen))
            let national = String(digits.dropFirst(ccLen))
            return national.isEmpty ? "+\(cc)" : "+\(cc) \(group(national, czech: cc == "420" || cc == "421"))"
        }
        guard trimmed.allSatisfy(\.isASCIIDigit) else { return number }
        return group(trimmed, czech: trimmed.count == 9)
    }

    /// Czech national significant number (9 digits) for +420 / 00420 / plain 9-digit input.
    static func czechNational(_ number: String) -> String? {
        let t = number.filter { !$0.isWhitespace && $0 != "-" }
        if t.hasPrefix("+420") { return String(t.dropFirst(4)) }
        if t.hasPrefix("00420") { return String(t.dropFirst(5)) }
        if t.count == 9, t.allSatisfy(\.isASCIIDigit) { return t }
        return nil
    }
}
