import Foundation

/// Banking validators. They must give the same results as scripts/lib/banking.mjs.
public enum Banking {
    /// ISO 13616 mod-97 check. Accepts IBANs with or without spaces.
    public static func isValidIBAN(_ iban: String) -> Bool {
        let s = iban.filter { !$0.isWhitespace }.uppercased()
        guard s.matches("^[A-Z]{2}[0-9]{2}[A-Z0-9]{10,30}$") else { return false }
        return mod97(String(s.dropFirst(4)) + String(s.prefix(4))) == 1
    }

    static func mod97(_ s: String) -> Int {
        var rem = 0
        for ch in s {
            if let d = ch.wholeNumberValue, ch.isASCII {
                rem = (rem * 10 + d) % 97
            } else if let a = ch.asciiValue, (65...90).contains(a) {
                let v = Int(a) - 55
                rem = (rem * 100 + v) % 97
            }
        }
        return rem
    }

    private static let prefixWeights = [10, 5, 8, 4, 2, 1]
    private static let baseWeights = [6, 3, 7, 9, 10, 5, 8, 4, 2, 1]

    /// Czech domestic account check (Vyhláška 169/2011 Sb.).
    public static func isValidCzechAccount(prefix: String?, number: String) -> Bool {
        let p = String(repeating: "0", count: max(0, 6 - (prefix ?? "0").count)) + (prefix ?? "0")
        let n = String(repeating: "0", count: max(0, 10 - number.count)) + number
        guard p.count == 6, n.count == 10, p.allSatisfy(\.isASCIIDigit), n.allSatisfy(\.isASCIIDigit) else { return false }
        guard n.drop(while: { $0 == "0" }).count >= 2, n.filter({ $0 != "0" }).count >= 2 else { return false }
        func sum(_ digits: String, _ weights: [Int]) -> Int {
            zip(digits, weights).reduce(0) { $0 + ($1.0.wholeNumberValue ?? 0) * $1.1 }
        }
        return sum(p, prefixWeights) % 11 == 0 && sum(n, baseWeights) % 11 == 0
    }

    public struct CzechAccount: Sendable, Hashable {
        public var prefix: String
        public var number: String
        public var bankCode: String
        public var domestic: String { "\(prefix.isEmpty ? "" : prefix + "-")\(number)/\(bankCode)" }
    }

    /// CZ IBAN → domestic account. Nil for non-Czech or malformed IBANs.
    public static func czechAccount(fromIBAN iban: String) -> CzechAccount? {
        let s = iban.filter { !$0.isWhitespace }.uppercased()
        guard s.matches("^CZ[0-9]{22}$") else { return nil }
        let chars = Array(s)
        let bank = String(chars[4..<8])
        let prefix = String(String(chars[8..<14]).drop(while: { $0 == "0" }))
        let number = String(String(chars[14..<24]).drop(while: { $0 == "0" }))
        return CzechAccount(prefix: prefix, number: number, bankCode: bank)
    }

    /// Domestic account → CZ IBAN with computed check digits.
    public static func czechIBAN(prefix: String?, number: String, bankCode: String) -> String {
        func pad(_ s: String, _ n: Int) -> String { String(repeating: "0", count: max(0, n - s.count)) + s }
        let bban = pad(bankCode, 4) + pad(prefix ?? "", 6) + pad(number, 10)
        let check = 98 - mod97(bban + "CZ00")
        return "CZ" + pad(String(check), 2) + bban
    }

    /// Parses "19-2000145399/0800" or "1234567899/2010".
    public static func parseDomestic(_ s: String) -> CzechAccount? {
        guard let c = s.captures("^(?:([0-9]{1,6})-)?([0-9]{2,10})/([0-9]{4})$") else { return nil }
        return CzechAccount(prefix: c[1] ?? "", number: c[2] ?? "", bankCode: c[3] ?? "")
    }

    /// CRC32 (IEEE 802.3) as uppercase hex, as used by SPD/SID `CRC32` fields.
    public static func crc32(_ string: String) -> String {
        String(format: "%08X", crc32(Data(string.utf8)))
    }

    private static let crcTable: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 { c = c & 1 != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    public static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for b in data { crc = crcTable[Int((crc ^ UInt32(b)) & 0xFF)] ^ (crc >> 8) }
        return crc ^ 0xFFFF_FFFF
    }

    /// IČO check digit (weights 8…2).
    public static func isValidICO(_ ico: String) -> Bool {
        let s = String(repeating: "0", count: max(0, 8 - ico.count)) + ico
        guard s.count == 8, s.allSatisfy(\.isASCIIDigit) else { return false }
        let digits = s.compactMap(\.wholeNumberValue)
        let sum = (0..<7).reduce(0) { $0 + digits[$1] * (8 - $1) }
        return (11 - sum % 11) % 10 == digits[7]
    }

    /// Swiss QR reference (QRR): 27 digits, recursive mod-10 check digit.
    public static func isValidQRR(_ ref: String) -> Bool {
        let s = ref.filter { !$0.isWhitespace }
        guard s.count == 27, s.allSatisfy(\.isASCIIDigit) else { return false }
        let table = [0, 9, 4, 6, 8, 2, 7, 1, 3, 5]
        var carry = 0
        for c in s.dropLast() { carry = table[(carry + (c.wholeNumberValue ?? 0)) % 10] }
        return (10 - carry) % 10 == s.last?.wholeNumberValue
    }

    /// ISO 11649 creditor reference ("RF18…"): mod-97 like an IBAN.
    public static func isValidCreditorReference(_ ref: String) -> Bool {
        let s = ref.filter { !$0.isWhitespace }.uppercased()
        guard s.matches("^RF[0-9]{2}[A-Z0-9]{1,21}$") else { return false }
        return mod97(String(s.dropFirst(4)) + String(s.prefix(4))) == 1
    }

    /// Country names for IBAN country codes we expect to see.
    static let countryNames: [String: LocalizedText] = [
        "CZ": LocalizedText(cs: "Česko", en: "Czechia"), "SK": LocalizedText(cs: "Slovensko", en: "Slovakia"),
        "DE": LocalizedText(cs: "Německo", en: "Germany"), "AT": LocalizedText(cs: "Rakousko", en: "Austria"),
        "PL": LocalizedText(cs: "Polsko", en: "Poland"), "HU": LocalizedText(cs: "Maďarsko", en: "Hungary"),
        "LT": LocalizedText(cs: "Litva", en: "Lithuania"), "LV": LocalizedText(cs: "Lotyšsko", en: "Latvia"),
        "EE": LocalizedText(cs: "Estonsko", en: "Estonia"), "GB": LocalizedText(cs: "Spojené království", en: "United Kingdom"),
        "IE": LocalizedText(cs: "Irsko", en: "Ireland"), "FR": LocalizedText(cs: "Francie", en: "France"),
        "ES": LocalizedText(cs: "Španělsko", en: "Spain"), "IT": LocalizedText(cs: "Itálie", en: "Italy"),
        "NL": LocalizedText(cs: "Nizozemsko", en: "Netherlands"), "BE": LocalizedText(cs: "Belgie", en: "Belgium"),
        "CH": LocalizedText(cs: "Švýcarsko", en: "Switzerland"), "LU": LocalizedText(cs: "Lucembursko", en: "Luxembourg"),
        "PT": LocalizedText(cs: "Portugalsko", en: "Portugal"), "RO": LocalizedText(cs: "Rumunsko", en: "Romania"),
        "BG": LocalizedText(cs: "Bulharsko", en: "Bulgaria"), "HR": LocalizedText(cs: "Chorvatsko", en: "Croatia"),
        "SI": LocalizedText(cs: "Slovinsko", en: "Slovenia"), "CY": LocalizedText(cs: "Kypr", en: "Cyprus"),
        "MT": LocalizedText(cs: "Malta", en: "Malta"), "GR": LocalizedText(cs: "Řecko", en: "Greece"),
        "DK": LocalizedText(cs: "Dánsko", en: "Denmark"), "SE": LocalizedText(cs: "Švédsko", en: "Sweden"),
        "FI": LocalizedText(cs: "Finsko", en: "Finland"), "NO": LocalizedText(cs: "Norsko", en: "Norway"),
        "UA": LocalizedText(cs: "Ukrajina", en: "Ukraine"), "TR": LocalizedText(cs: "Turecko", en: "Turkey"),
        "AE": LocalizedText(cs: "Spojené arabské emiráty", en: "United Arab Emirates"),
    ]

    public static func countryName(_ code: String) -> LocalizedText {
        countryNames[code.uppercased()] ?? LocalizedText(code.uppercased())
    }
}
