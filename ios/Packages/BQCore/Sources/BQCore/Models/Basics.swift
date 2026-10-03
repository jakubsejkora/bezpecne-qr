import Foundation

// MARK: - Language and localized values

/// App languages. Czech is the base language.
public enum Language: String, Sendable, Codable, CaseIterable {
    case cs, en

    /// The language the user's device prefers among the ones we support.
    public static var preferred: Language {
        let first = Bundle.main.preferredLocalizations.first ?? Locale.preferredLanguages.first ?? "cs"
        return first.hasPrefix("en") ? .en : .cs
    }
}

/// A text available in both app languages (`{"cs": …, "en": …}` in the shared JSON files).
public struct LocalizedText: Sendable, Hashable, Codable {
    public var cs: String
    public var en: String

    public init(cs: String, en: String) {
        self.cs = cs
        self.en = en
    }

    public init(_ both: String) {
        self.cs = both
        self.en = both
    }

    public func resolve(_ language: Language) -> String {
        language == .en ? en : cs
    }
}

/// An argument of a finding: plain text, a localized text or a number.
public enum ArgValue: Sendable, Hashable, Codable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral {
    case text(String)
    case localized(LocalizedText)
    case number(Double)

    public init(stringLiteral value: String) { self = .text(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }

    public func resolve(_ language: Language) -> String {
        switch self {
        case .text(let s): return s
        case .localized(let l): return l.resolve(language)
        case .number(let n): return n.rounded() == n ? String(Int(n)) : String(n)
        }
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s); return }
        if let n = try? c.decode(Double.self) { self = .number(n); return }
        self = .localized(try c.decode(LocalizedText.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .text(let s): try c.encode(s)
        case .localized(let l): try c.encode(l)
        case .number(let n): try c.encode(n)
        }
    }
}

// MARK: - Findings

/// One finding about a code. The same shape is used for scored evidence (signal IDs from
/// weights.json), consequences (`csq.*`) and completed checks (`chk.*`). Texts live in
/// signals.json and are filled from `args`.
public struct Finding: Sendable, Hashable, Codable, Identifiable {
    public var id: String
    public var args: [String: ArgValue]

    public init(_ id: String, _ args: [String: ArgValue] = [:]) {
        self.id = id
        self.args = args
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        args = try c.decodeIfPresent([String: ArgValue].self, forKey: .args) ?? [:]
    }
}

public enum Severity: String, Sendable, Codable, Comparable {
    case critical, warning, info

    private var rank: Int { self == .critical ? 0 : self == .warning ? 1 : 2 }
    public static func < (a: Severity, b: Severity) -> Bool { a.rank < b.rank }
}

// MARK: - Verdict

/// Result bands. `info` is used for informational, unscored types (Wi‑Fi, contact, event…).
public enum Band: String, Sendable, Codable, CaseIterable {
    case safe, caution, danger, incomplete, info
}

/// Whether the inspection of a code could be completed.
public struct Completeness: Sendable, Hashable, Codable {
    public enum State: String, Sendable, Codable {
        case complete, incomplete, skipped
        case notNeeded = "not-needed"
    }

    public var state: State
    /// An `inc.*` ID from signals.json, or nil.
    public var reason: String?
    /// For `skipped`: whether the user may start a one-shot manual inspection.
    public var manual: Bool

    public init(_ state: State, reason: String? = nil, manual: Bool = false) {
        self.state = state
        self.reason = reason
        self.manual = manual
    }

    public static let complete = Completeness(.complete)
    public static let notNeeded = Completeness(.notNeeded)

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        state = try c.decode(State.self, forKey: .state)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        manual = try c.decodeIfPresent(Bool.self, forKey: .manual) ?? false
    }
}

// MARK: - Scanned input

public enum Symbology: String, Sendable, Codable, CaseIterable {
    case qr
    case microQR = "microqr"
    case aztec
    case dataMatrix = "datamatrix"
    case pdf417
}

public enum ScanSource: String, Sendable, Codable {
    case camera, photo, share, debug
}

/// What a barcode reader returned.
public struct ScannedCode: Sendable, Hashable, Codable {
    /// The decoded string value.
    public var text: String
    /// Raw payload bytes, when the reader provided them (used for charset heuristics).
    public var rawBytes: Data?
    public var symbology: Symbology
    public var source: ScanSource

    public init(text: String, rawBytes: Data? = nil, symbology: Symbology = .qr, source: ScanSource = .camera) {
        self.text = text
        self.rawBytes = rawBytes
        self.symbology = symbology
        self.source = source
    }
}

// MARK: - Types

/// Every code type the app recognises. Raw values match `type` in shared/testdata/samples.json.
public enum CodeType: String, Sendable, Codable, CaseIterable {
    case url
    case appInstall = "app-install"
    case webcal
    case store
    case messenger
    case spd
    case sid
    case epc
    case spc
    case crypto
    case payBySquare = "paybysquare"
    case sms
    case tel
    case mailto
    case contact
    case wifi
    case otpauth
    case otpauthMigration = "otpauth-migration"
    case login
    case fido
    case seed
    case walletConnect = "walletconnect"
    case event
    case geo
    case text
    case dataURI = "data-uri"
    case jsURI = "js-uri"
    case intent
    case emvco
    case gs1
    case bcbp
    case hc1
}

/// The scoring engine used for a code. Raw values match `engine` in the corpus.
public enum EngineKind: String, Sendable, Codable {
    case url, payment, sms, phone, generic, none
}

/// Why a code is handled by the non-overridable sensitivity gate.
public enum Sensitivity: String, Sendable, Codable {
    /// 2FA secrets, seed phrases, private keys.
    case secret
    /// Login / device-link / FIDO / WalletConnect tokens.
    case token
    /// Wi‑Fi passwords.
    case password
    /// Boarding passes, health certificates.
    case personal
}

/// Special handling for some links.
public enum LinkSubtype: String, Sendable, Codable {
    /// A file download such as an .apk.
    case download
    /// A configuration profile (.mobileconfig).
    case profile
}
