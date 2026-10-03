import BQCore
import Foundation

/// Decides what a form field — or an instruction in the page text — asks the visitor to enter.
enum AskClassifier {
    private struct Rule {
        var kind: AskKind
        /// Whole-word phrases in the folded text ("cislo karty").
        var phrases: [String]
        /// Single words from identifiers and labels ("cvv", "msisdn").
        var words: Set<String>
    }

    /// Checked in this order; the first match wins (an SMS-code field that mentions the phone
    /// number is an OTP field, a card PIN is card data).
    private static let fieldRules: [Rule] = [
        Rule(kind: .otp,
             phrases: ["kod z sms", "sms kod", "overovaci kod", "jednorazovy kod", "jednorazove heslo", "autorizacni kod",
                       "potvrzovaci kod", "verification code", "one time code", "one time password", "sms code", "security code"],
             words: ["otp", "smscode", "smskod", "totp", "2fa", "mfa", "onetimecode"]),
        Rule(kind: .card,
             phrases: ["cislo karty", "cislo platebni karty", "platebni karta", "card number", "credit card", "debit card", "platnost karty",
                       "drzitel karty", "cardholder", "datum expirace", "expiration date", "expiry date", "kod cvv", "cvv kod"],
             words: ["card", "cardnumber", "cc", "ccnumber", "ccnum", "cvv", "cvc", "cvv2", "cvc2", "csc", "karta", "karty", "kartu",
                     "kartou", "expiry", "expiration", "creditcard"]),
        Rule(kind: .recoverySecret,
             phrases: ["seed phrase", "recovery phrase", "secret phrase", "obnovovaci fraze", "zalozni fraze", "tajna fraze", "12 slov",
                       "24 slov", "12 words", "24 words", "private key", "soukromy klic", "zalozni kody", "backup code"],
             words: ["seed", "mnemonic", "privatekey", "seedphrase"]),
        Rule(kind: .personalID,
             phrases: ["rodne cislo", "birth number", "cislo obcanskeho prukazu", "cislo op", "personal identification number"],
             words: ["rodnecislo", "rc", "birthnumber"]),
        Rule(kind: .licencePlate,
             phrases: ["registracni znacka", "registracni znacku", "registracni znacky", "statni poznavaci znacka", "license plate",
                       "licence plate", "number plate", "plate number"],
             words: ["spz", "rz", "plate", "licenseplate", "licenceplate", "numberplate", "platenumber"]),
        Rule(kind: .password,
             phrases: ["heslo", "password", "pin kod", "passcode"],
             words: ["password", "passwd", "pwd", "heslo", "hesla", "pin", "passcode"]),
        Rule(kind: .phone,
             phrases: ["telefonni cislo", "cislo telefonu", "mobilni cislo", "cislo mobilu", "phone number", "mobile number"],
             words: ["phone", "telefon", "telephone", "tel", "msisdn", "mobil", "mobile", "mobilni", "gsm", "phonenumber", "telefonni"]),
        Rule(kind: .email,
             phrases: ["e mail", "email address"],
             words: ["email", "mail", "emailaddress"]),
    ]

    /// What one field asks for, or nil for ordinary fields (name, quantity, search…).
    static func classify(_ field: PageStructure.Field) -> AskKind? {
        let autocomplete = (field.autocomplete ?? "").lowercased().split(separator: " ").map(String.init)
        if field.type == "password" || autocomplete.contains("current-password") || autocomplete.contains("new-password") { return .password }
        if autocomplete.contains("one-time-code") { return .otp }
        if autocomplete.contains(where: { $0.hasPrefix("cc-") }) { return .card }
        if autocomplete.contains(where: { $0 == "tel" || $0.hasPrefix("tel-") }) { return .phone }
        if autocomplete.contains("email") { return .email }

        let identifiers = [field.name, field.id].compactMap { $0 }.map(splitIdentifier)
        let labels = [field.labelText, field.precedingText, field.ariaLabel, field.placeholder, field.title].compactMap { $0 }
        let text = normalized((identifiers + labels).joined(separator: " "))
        let words = Set(text.split(separator: " ").map(String.init))
        for rule in fieldRules where !rule.words.isDisjoint(with: words) || rule.phrases.contains(where: { text.contains(" \($0) ") }) {
            return rule.kind
        }
        switch field.type {
        case "tel": return .phone
        case "email": return .email
        default: return nil
        }
    }

    // MARK: - Instructions in text

    private static let verbs: Set<String> = [
        "zadejte", "zadat", "zadej", "vyplnte", "vyplnit", "vypln", "uvedte", "uvest", "napiste", "napsat", "vlozte", "vlozit",
        "opiste", "sdelte", "enter", "provide",
    ]

    private static let instructionObjects: [(AskKind, [String])] = [
        (.card, ["cislo karty", "cislo platebni karty", "udaje o karte", "udaje karty", "udaje z karty", "udaje platebni karty", "cvv", "cvc",
                 "card number", "card details"]),
        (.licencePlate, ["spz", "rz", "registracni znacku", "registracni znacka", "license plate", "licence plate"]),
        (.phone, ["telefonni cislo", "cislo telefonu", "mobilni cislo", "cislo mobilu", "phone number", "mobile number"]),
        (.otp, ["kod z sms", "overovaci kod", "sms kod", "jednorazovy kod", "verification code"]),
        (.password, ["heslo", "pin", "password"]),
        (.personalID, ["rodne cislo"]),
        (.recoverySecret, ["12 slov", "24 slov", "obnovovaci frazi", "obnovovaci fraze", "seed", "recovery phrase", "soukromy klic", "private key"]),
        (.email, ["e mail", "email"]),
    ]

    /// Kinds that a sentence explicitly tells the visitor to enter ("Zadejte SPZ a číslo karty"),
    /// in the order they are named. Mentions without an instruction verb don't count.
    static func instructions(in line: String) -> [AskKind] {
        var kinds: [AskKind] = []
        for sentence in line.split(whereSeparator: { ".!?;".contains($0) }) {
            let tokens = normalized(String(sentence)).split(separator: " ").map(String.init)
            guard let verbIndex = tokens.firstIndex(where: verbs.contains) else { continue }
            // Only the words right after the verb are its object (this also bounds the matching work).
            let tail = " " + tokens[verbIndex..<min(tokens.count, verbIndex + 16)].joined(separator: " ") + " "
            var found: [(position: String.Index, kind: AskKind)] = []
            for (kind, phrases) in instructionObjects {
                if let first = phrases.compactMap({ tail.range(of: " \($0) ")?.lowerBound }).min() {
                    found.append((first, kind))
                }
            }
            kinds += found.sorted { $0.position < $1.position }.map(\.kind)
        }
        var seen = Set<AskKind>()
        return kinds.filter { seen.insert($0).inserted }
    }

    // MARK: - Normalization

    /// Folded (deaccented, lower-case) text with every run of non-alphanumerics turned into one
    /// space and padded with spaces, so phrases can be matched as whole words with `contains`.
    static func normalized(_ s: String) -> String {
        let folded = s.folded
        var out = " "
        var lastWasSpace = true
        for c in folded {
            if c.isLetter || c.isNumber {
                out.append(c)
                lastWasSpace = false
            } else if !lastWasSpace {
                out.append(" ")
                lastWasSpace = true
            }
        }
        if !lastWasSpace { out.append(" ") }
        return out
    }

    /// "cardNumber" → "card Number", "card_number" → "card number".
    static func splitIdentifier(_ s: String) -> String {
        var out = ""
        var previous: Character?
        for c in s {
            if let p = previous, p.isLowercase, c.isUppercase { out.append(" ") }
            out.append(c.isLetter || c.isNumber ? c : " ")
            previous = c
        }
        return out
    }
}
