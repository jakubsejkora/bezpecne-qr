import Foundation

/// Codes in the non-overridable sensitive class: 2FA secrets, login and device-link tokens,
/// passkeys, wallet connections and recovery phrases. Their secrets are never kept in the parsed
/// content, never stored in history, never sent anywhere.
struct SecurityParser {
    // MARK: 2FA

    func otp(_ text: String) -> Parsed {
        let c = URLComponents(string: LinkParser.percentEncodeNonASCII(text))
        let kind = (c?.host ?? "totp").uppercased()
        let label = (c?.path ?? "").drop(while: { $0 == "/" }).description.percentDecoded
        let labelParts = label.split(separator: ":", maxSplits: 1).map { String($0).trimmed() }
        let query = c?.queryItems ?? []
        func q(_ name: String) -> String? { query.first(where: { $0.name.lowercased() == name })?.value }
        let issuer = q("issuer") ?? (labelParts.count == 2 ? labelParts[0] : "")
        let account = labelParts.count == 2 ? labelParts[1] : (labelParts.first ?? "")
        let info = OTPInfo(kind: kind == "HOTP" ? "HOTP" : "TOTP", issuer: issuer.isEmpty ? "?" : issuer, account: account,
                           digits: Int(q("digits") ?? "") ?? 6, period: kind == "HOTP" ? nil : (Int(q("period") ?? "") ?? 30),
                           algorithm: q("algorithm")?.uppercased())
        var parsed = Parsed(type: .otpauth, content: .otp(info), sensitivity: .secret)
        parsed.consequences.append(Finding("csq.twofa_setup"))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    func otpMigration(_ text: String) -> Parsed {
        let c = URLComponents(string: text)
        var info = OTPMigrationInfo(count: 0, issuers: [])
        if let dataParam = c?.queryItems?.first(where: { $0.name == "data" })?.value {
            var b64 = dataParam.replacingOccurrences(of: " ", with: "+")
            while b64.count % 4 != 0 { b64 += "=" }
            if let data = Data(base64Encoded: b64) {
                // MigrationPayload { repeated OtpParameters otp_parameters = 1; … }
                // OtpParameters { bytes secret = 1; string name = 2; string issuer = 3; … }
                // Only the issuer (falling back to the name) is read; secrets are skipped unread.
                for entry in Protobuf.fields(data) where entry.number == 1 {
                    guard case .bytes(let inner) = entry.value else { continue }
                    info.count += 1
                    var issuer: String?, name: String?
                    for f in Protobuf.fields(inner) {
                        if f.number == 3, case .bytes(let b) = f.value { issuer = String(data: b, encoding: .utf8) }
                        if f.number == 2, case .bytes(let b) = f.value { name = String(data: b, encoding: .utf8) }
                    }
                    if let label = issuer?.nilIfEmpty ?? name?.nilIfEmpty { info.issuers.append(label) }
                }
            }
        }
        var parsed = Parsed(type: .otpauthMigration, content: .otpMigration(info), sensitivity: .secret)
        parsed.consequences.append(Finding("csq.twofa_secrets", ["count": .number(Double(info.count))]))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    // MARK: Login and device-link codes

    static let loginEffects: [String: LocalizedText] = [
        "WhatsApp": LocalizedText(cs: "Propojí váš WhatsApp s jiným zařízením — uvidí všechny vaše zprávy.",
                                  en: "Links your WhatsApp to another device — it would see all your messages."),
        "Telegram": LocalizedText(cs: "Přihlásí jiné zařízení k vašemu Telegramu.", en: "Signs another device into your Telegram."),
        "Signal": LocalizedText(cs: "Propojí jiné zařízení s vaším Signalem — uvidí nové zprávy.",
                                en: "Links another device to your Signal — it would see new messages."),
        "Discord": LocalizedText(cs: "Přihlásí jiné zařízení k vašemu účtu Discord.", en: "Signs another device into your Discord account."),
        "Steam": LocalizedText(cs: "Přihlásí jiné zařízení k vašemu účtu Steam.", en: "Signs another device into your Steam account."),
    ]

    func loginParsed(service: String, kind: String) -> Parsed {
        var parsed = Parsed(type: .login, content: .login(LoginInfo(service: service, kind: kind)), sensitivity: .token)
        let effect = SecurityParser.loginEffects[service]
            ?? LocalizedText(cs: "Přihlásí jiné zařízení k vašemu účtu \(service).", en: "Signs another device into your \(service) account.")
        parsed.consequences.append(Finding("csq.account_access", ["effect": .localized(effect)]))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    func login(_ text: String) -> Parsed? {
        let lower = text.lowercased()
        if lower.hasPrefix("tg://login") { return loginParsed(service: "Telegram", kind: "login") }
        if lower.hasPrefix("sgnl://linkdevice") { return loginParsed(service: "Signal", kind: "device-link") }
        // WhatsApp Web / linked-device QR: "2@<ref>,<noise key>,<identity key>,<adv secret>"
        if text.matches("^[0-9]@[A-Za-z0-9+/=]{8,},[A-Za-z0-9+/=]{20,},[A-Za-z0-9+/=]{20,}(,[A-Za-z0-9+/=]{8,})?$") {
            return loginParsed(service: "WhatsApp", kind: "device-link")
        }
        return nil
    }

    // MARK: Passkeys, wallets, recovery phrases

    func fido(_ text: String) -> Parsed {
        var parsed = Parsed(type: .fido, content: .fido(FIDOInfo(kind: "hybrid")), sensitivity: .token)
        parsed.consequences.append(Finding("csq.passkey_nearby"))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    func walletConnect(_ text: String) -> Parsed {
        let body = String(text.dropFirst(3))
        let version = body.captures("@([0-9]+)")?[1].flatMap { Int($0) } ?? 1
        let c = URLComponents(string: "wc://x?" + (body.split(separator: "?", maxSplits: 1).dropFirst().first.map(String.init) ?? ""))
        var relay = c?.queryItems?.first(where: { $0.name == "relay-protocol" })?.value
        if relay == nil, let bridge = c?.queryItems?.first(where: { $0.name == "bridge" })?.value { relay = URL(string: bridge)?.host }
        var parsed = Parsed(type: .walletConnect, content: .walletConnect(WalletConnectInfo(version: version, relay: relay)), sensitivity: .token)
        parsed.consequences.append(Finding("csq.wallet_connect"))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    static let stopWords: Set<String> = [
        "the", "and", "to", "of", "a", "in", "is", "it", "for", "on", "with", "you", "your", "are", "be", "this",
        "je", "a", "na", "se", "v", "ve", "do", "za", "pro", "jsme", "jste", "to", "ze", "s", "z", "k", "o",
    ]

    /// BIP 39 style recovery phrases (12–24 lower-case words) and WIF private keys.
    func seedPhrase(_ text: String) -> Parsed? {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        let phrase = [12, 15, 18, 21, 24].contains(words.count)
            && words.allSatisfy { $0.count >= 3 && $0.count <= 8 && $0.allSatisfy { $0 >= "a" && $0 <= "z" } }
            && Set(words).count >= words.count - 1
            && !words.contains(where: { SecurityParser.stopWords.contains($0) })
        let wif = text.matches("^[5KL][1-9A-HJ-NP-Za-km-z]{50,51}$")
        guard phrase || wif else { return nil }
        var parsed = Parsed(type: .seed, content: .seed(SeedInfo(words: phrase ? words.count : 1)), sensitivity: .secret)
        parsed.consequences.append(Finding("csq.seed_phrase"))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }
}

/// Minimal protobuf reader (varint and length-delimited fields only).
enum Protobuf {
    enum Value {
        case varint(UInt64)
        case bytes(Data)
    }

    struct Field {
        var number: Int
        var value: Value
    }

    static func fields(_ data: Data) -> [Field] {
        var result: [Field] = []
        let bytes = [UInt8](data)
        var i = 0
        func varint() -> UInt64? {
            var value: UInt64 = 0, shift: UInt64 = 0
            while i < bytes.count, shift < 64 {
                let b = bytes[i]
                i += 1
                value |= UInt64(b & 0x7F) << shift
                if b & 0x80 == 0 { return value }
                shift += 7
            }
            return nil
        }
        while i < bytes.count {
            guard let key = varint() else { break }
            let number = Int(key >> 3), wire = key & 7
            switch wire {
            case 0:
                guard let v = varint() else { return result }
                result.append(Field(number: number, value: .varint(v)))
            case 2:
                guard let len = varint(), len <= UInt64(bytes.count - i) else { return result }
                result.append(Field(number: number, value: .bytes(Data(bytes[i..<i + Int(len)]))))
                i += Int(len)
            case 1: i += 8
            case 5: i += 4
            default: return result
            }
        }
        return result
    }
}
