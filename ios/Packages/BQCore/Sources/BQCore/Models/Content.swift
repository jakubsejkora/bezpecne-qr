import Foundation

/// The parsed content of a code. Each case carries a struct whose coding keys match the
/// `fields` object of the corresponding samples in shared/testdata/samples.json.
public enum CodeContent: Sendable, Hashable {
    case link(LinkInfo)                    // url, webcal
    case appInstall(AppInstallInfo)        // itms-services
    case store(StoreInfo)                  // App Store / Google Play
    case messenger(MessengerInfo)          // wa.me, t.me, signal.me
    case payment(PaymentInfo)              // QR Platba (SPD/SCD), Platba+F
    case invoice(InvoiceDocInfo)           // QR Faktura (SID)
    case transfer(TransferInfo)            // EPC / GiroCode, Swiss QR-bill
    case crypto(CryptoInfo)
    case payBySquare
    case sms(SMSInfo)
    case phone(PhoneInfo)
    case email(EmailInfo)
    case contact(ContactInfo)
    case wifi(WiFiInfo)
    case otp(OTPInfo)
    case otpMigration(OTPMigrationInfo)
    case login(LoginInfo)
    case fido(FIDOInfo)
    case seed(SeedInfo)
    case walletConnect(WalletConnectInfo)
    case event(EventInfo)
    case geo(GeoInfo)
    case text(TextInfo)
    case dataURI(DataURIInfo)
    case script(ScriptInfo)
    case intent(IntentInfo)
    case emvco(EMVCoInfo)
    case gs1(GS1Info)
    case boardingPass(BoardingPassInfo)
    case healthCertificate

    /// The parsed fields as a JSON-compatible dictionary (used by tests and diagnostics).
    public var fieldsJSON: [String: Any] {
        let encoder = JSONEncoder()
        func dict<T: Encodable>(_ value: T) -> [String: Any] {
            guard let data = try? encoder.encode(value),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
            return object
        }
        switch self {
        case .link(let v): return dict(v)
        case .appInstall(let v): return dict(v)
        case .store(let v): return dict(v)
        case .messenger(let v): return dict(v)
        case .payment(let v): return dict(v)
        case .invoice(let v): return dict(v)
        case .transfer(let v): return dict(v)
        case .crypto(let v): return dict(v)
        case .sms(let v): return dict(v)
        case .phone(let v): return dict(v)
        case .email(let v): return dict(v)
        case .contact(let v): return dict(v)
        case .wifi(let v): return dict(v)
        case .otp(let v): return dict(v)
        case .otpMigration(let v): return dict(v)
        case .login(let v): return dict(v)
        case .fido(let v): return dict(v)
        case .seed(let v): return dict(v)
        case .walletConnect(let v): return dict(v)
        case .event(let v): return dict(v)
        case .geo(let v): return dict(v)
        case .text(let v): return dict(v)
        case .dataURI(let v): return dict(v)
        case .script(let v): return dict(v)
        case .intent(let v): return dict(v)
        case .emvco(let v): return dict(v)
        case .gs1(let v): return dict(v)
        case .boardingPass(let v): return dict(v)
        case .payBySquare, .healthCertificate: return [:]
        }
    }
}

// MARK: - Links

/// A web (or webcal) link.
public struct LinkInfo: Sendable, Hashable, Codable {
    /// The link exactly as scanned.
    public var url: String
    /// The link with internationalised domain names decoded, when that differs from `url`.
    public var display: String?
    /// The host in ASCII (punycode) form.
    public var host: String
    /// The host with IDN labels decoded, when that differs from `host`.
    public var hostDisplay: String?
    /// The registrable domain ("eTLD+1"), or the IP address.
    public var registrable: String
    public var scheme: String
    public var port: Int?
    /// The part before `@` in links like `https://www.csob.cz@evil.top/`.
    public var userinfo: String?
    /// The destination hidden in an open-redirect link (e.g. google.com/url?q=…).
    public var inner: String?
    /// The HTTPS variant that was inspected instead of an `http://` link.
    public var upgraded: String?
    /// The file name of a download (.apk, .ipa, .mobileconfig, .ics).
    public var file: String?

    public init(url: String, display: String? = nil, host: String, hostDisplay: String? = nil, registrable: String,
                scheme: String, port: Int? = nil, userinfo: String? = nil, inner: String? = nil,
                upgraded: String? = nil, file: String? = nil) {
        self.url = url
        self.display = display
        self.host = host
        self.hostDisplay = hostDisplay
        self.registrable = registrable
        self.scheme = scheme
        self.port = port
        self.userinfo = userinfo
        self.inner = inner
        self.upgraded = upgraded
        self.file = file
    }
}

public struct AppInstallInfo: Sendable, Hashable, Codable {
    public var scheme: String
    public var manifest: String?
    public var host: String?
    public var registrable: String?
}

public struct StoreInfo: Sendable, Hashable, Codable {
    public var url: String
    public var store: String
    public var appId: String?
    public var host: String
    public var registrable: String
}

public struct MessengerInfo: Sendable, Hashable, Codable {
    public var url: String
    public var service: String
    /// Phone number, user name or a description such as "soukromá skupina".
    public var target: String
    public var text: String?
    /// "chat", "group-invite" or "profile".
    public var kind: String
    public var host: String
    public var registrable: String
}

// MARK: - Payments

/// QR Platba (SPD), direct-debit consent (SCD) and QR Platba+F.
public struct PaymentInfo: Sendable, Hashable, Codable {
    /// "payment", "standing" or "directDebit".
    public var kind: String
    public var iban: String
    public var bic: String?
    /// Domestic form `prefix-number/bank` for Czech IBANs.
    public var domestic: String?
    public var bankCode: String?
    public var bankName: String?
    /// Country code of a non-Czech IBAN.
    public var country: String?
    /// Normalised amount ("480.50"), nil when missing or invalid.
    public var amount: String?
    /// The raw value when `AM` is not a valid number.
    public var amountRaw: String?
    public var currency: String?
    public var vs: String?
    public var ss: String?
    public var ks: String?
    public var recipientName: String?
    /// `PT` field, e.g. "IP" for an instant payment.
    public var paymentType: String?
    public var message: String?
    /// `FRQ` of a standing order, e.g. "1M".
    public var frequency: String?
    /// ISO date (yyyy-MM-dd).
    public var dueDate: String?
    /// ISO date of the last payment / end of a direct-debit consent.
    public var lastDate: String?
    public var reference: String?
    /// `X-URL`.
    public var url: String?
    public var crc32: String?
    public var invoice: InvoiceInfo?
}

/// Invoice data embedded in QR Platba+F (`X-INV`).
public struct InvoiceInfo: Sendable, Hashable, Codable {
    public var id: String?
    public var issued: String?
    public var taxPoint: String?
    public var issuerIco: String?
    public var issuerVat: String?
    public var base: String?
    public var vat: String?
    public var total: String?
}

/// QR Faktura (SID).
public struct InvoiceDocInfo: Sendable, Hashable, Codable {
    public var id: String?
    public var issued: String?
    public var due: String?
    public var taxPoint: String?
    public var total: String?
    public var currency: String?
    public var vs: String?
    public var issuerIco: String?
    public var issuerVat: String?
    public var base: String?
    public var vat: String?
    public var iban: String?
    public var domestic: String?
    public var bankCode: String?
    public var bankName: String?
}

/// EPC / GiroCode (SEPA) and Swiss QR-bill.
public struct TransferInfo: Sendable, Hashable, Codable {
    /// "epc" or "spc".
    public var standard: String
    public var version: String?
    public var bic: String?
    /// Beneficiary name (EPC).
    public var name: String?
    /// Creditor name and address (Swiss QR-bill).
    public var creditor: String?
    public var iban: String
    public var amount: String?
    public var currency: String?
    /// Unstructured remittance text (EPC).
    public var text: String?
    /// Additional information (Swiss QR-bill).
    public var message: String?
    public var debtor: String?
    /// "QRR", "SCOR", "NON" or "RF".
    public var referenceType: String?
    public var reference: String?
    public var purpose: String?
}

public struct CryptoInfo: Sendable, Hashable, Codable {
    public var scheme: String
    public var network: String
    public var address: String?
    public var amount: String?
    public var unit: String?
    public var label: String?
    public var message: String?
    public var description: String?
    public var chainId: Int?
    /// ERC-20 token contract (the address in the URI's path).
    public var contract: String?
    public var token: String?
    /// The real recipient of an ERC-20 transfer.
    public var recipient: String?
    /// Shortened BOLT11 invoice for display.
    public var invoice: String?
}

// MARK: - Communication

public struct PremiumInfo: Sendable, Hashable, Codable {
    public var prefix: String
    public var digits: Int?
    /// Display price, e.g. "99 Kč" or "50 Kč/min"; nil when the number doesn't encode it.
    public var price: String?
    /// "sent", "received", "order", "perMinute", "perCall" or "internet".
    public var billing: String?
    public var category: LocalizedText?
}

public struct SMSInfo: Sendable, Hashable, Codable {
    public var number: String
    public var numberDisplay: String
    public var body: String
    public var premium: PremiumInfo?
    public var charity: Bool?
}

public struct MMIInfo: Sendable, Hashable, Codable {
    /// "activation" or "status".
    public var action: String
    public var service: LocalizedText
    public var target: String?
}

public struct PhoneInfo: Sendable, Hashable, Codable {
    public var number: String
    public var numberDisplay: String
    /// ISO country code when known.
    public var country: String?
    public var kind: LocalizedText?
    public var premium: PremiumInfo?
    public var mmi: MMIInfo?
}

public struct EmailInfo: Sendable, Hashable, Codable {
    public var to: String
    public var cc: String?
    public var subject: String?
    public var body: String?
    public var host: String
    public var registrable: String
}

public struct ContactInfo: Sendable, Hashable, Codable {
    /// "vCard 3.0", "MECARD", "BIZCARD"…
    public var format: String
    public var name: String
    public var org: String?
    public var title: String?
    public var tels: [String]
    public var emails: [String]
    public var urls: [String]
    public var address: String?
    public var note: String?
    public var birthday: String?
    /// A URL inside the contact that raised a warning.
    public var flaggedUrl: String?
    public var host: String?
    public var registrable: String?
}

// MARK: - Devices and security

public struct WiFiInfo: Sendable, Hashable, Codable {
    public var ssid: String
    /// "WPA3", "WPA2", "WPA2/WPA3", "WEP", "WPA2-Enterprise" or "open".
    public var security: String
    /// Never stored in history or sent anywhere.
    public var password: String?
    public var hidden: Bool

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ssid, forKey: .ssid)
        try c.encode(security, forKey: .security)
        try c.encode(password, forKey: .password) // explicit null for open networks
        try c.encode(hidden, forKey: .hidden)
    }
}

/// `otpauth://` — the secret is deliberately not part of this struct.
public struct OTPInfo: Sendable, Hashable, Codable {
    /// "TOTP" or "HOTP".
    public var kind: String
    public var issuer: String
    public var account: String
    public var digits: Int
    public var period: Int?
    public var algorithm: String?
}

public struct OTPMigrationInfo: Sendable, Hashable, Codable {
    public var count: Int
    public var issuers: [String]
}

public struct LoginInfo: Sendable, Hashable, Codable {
    public var service: String
    /// "device-link" or "login".
    public var kind: String
}

public struct FIDOInfo: Sendable, Hashable, Codable {
    public var kind: String
}

public struct SeedInfo: Sendable, Hashable, Codable {
    public var words: Int
}

public struct WalletConnectInfo: Sendable, Hashable, Codable {
    public var version: Int
    public var relay: String?
}

// MARK: - Calendar, places, text

public struct EventInfo: Sendable, Hashable, Codable {
    public var summary: String
    /// Local date-time "yyyy-MM-ddTHH:mm", or a date "yyyy-MM-dd" for all-day events.
    public var start: String?
    public var end: String?
    public var location: String?
    public var description: String?
    public var url: String?
}

public struct GeoInfo: Sendable, Hashable, Codable {
    public var lat: Double
    public var lon: Double
    public var label: String?
}

public struct TextEntity: Sendable, Hashable, Codable {
    /// "account", "iban", "url", "phone", "email" or "phrase".
    public var kind: String
    public var value: String
}

public struct TextInfo: Sendable, Hashable, Codable {
    public var text: String
    public var entities: [TextEntity]
}

public struct DataURIInfo: Sendable, Hashable, Codable {
    public var mime: String
    /// Decoded content, shortened for display.
    public var preview: String
}

public struct ScriptInfo: Sendable, Hashable, Codable {
    public var code: String
}

public struct IntentInfo: Sendable, Hashable, Codable {
    public var package: String?
    public var scheme: String?
    public var fallback: String?
    public var host: String?
    public var registrable: String?
}

public struct EMVCoInfo: Sendable, Hashable, Codable {
    public var merchant: String?
    public var city: String?
    public var country: String?
    public var amount: String?
    public var currencyCode: String?
}

public struct GS1Info: Sendable, Hashable, Codable {
    public var gtin: String
    public var batch: String?
    public var serial: String?
    /// ISO date.
    public var expiry: String?
    public var host: String
}

public struct BoardingPassInfo: Sendable, Hashable, Codable {
    public var name: String
    public var pnr: String
    public var from: String
    public var to: String
    public var carrier: String
    public var flight: String
    public var date: LocalizedText?
    public var seat: String
    public var `class`: String?
}
