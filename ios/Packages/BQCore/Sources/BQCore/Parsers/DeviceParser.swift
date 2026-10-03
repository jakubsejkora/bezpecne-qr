import Foundation

/// Wi‑Fi, calendar events, places, structured travel/health codes, executable content and text.
struct DeviceParser {
    /// Splits on `separator`, honouring backslash escapes (`\;`, `\:`, `\,`, `\\`).
    static func splitEscaped(_ s: String, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var escaping = false
        for c in s {
            if escaping {
                current.append(c)
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else if c == separator {
                parts.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        if !current.isEmpty { parts.append(current) }
        return parts
    }

    // MARK: Wi‑Fi

    func wifi(_ text: String) -> Parsed {
        var fields: [String: String] = [:]
        for field in DeviceParser.splitEscaped(String(text.dropFirst(5)), separator: ";") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].uppercased()
            if fields[key] == nil { fields[key] = String(field[field.index(after: colon)...]) }
        }
        let type = (fields["T"] ?? "").uppercased()
        let password = fields["P"].flatMap { $0.isEmpty ? nil : $0 }
        let security: String
        switch type {
        case "WEP": security = "WEP"
        case "SAE", "WPA3": security = "WPA3"
        case "WPA2-EAP", "WPA-EAP", "EAP": security = "WPA2-Enterprise"
        case "NOPASS", "": security = password == nil ? "open" : "WPA2"
        default: security = fields["R"] == "1" ? "WPA3" : (fields["E"] != nil ? "WPA2-Enterprise" : "WPA2")
        }
        let hidden = ["TRUE", "1"].contains((fields["H"] ?? "").uppercased())
        let info = WiFiInfo(ssid: fields["S"] ?? "", security: security, password: password, hidden: hidden)
        var parsed = Parsed(type: .wifi, content: .wifi(info))
        if password != nil { parsed.sensitivity = .password }
        switch security {
        case "open": parsed.consequences.append(Finding("csq.open_wifi"))
        case "WEP": parsed.consequences.append(Finding("csq.weak_wifi"))
        default: parsed.checks.append(Finding("chk.wpa_ok", ["security": .text(security == "WPA3" ? "WPA3" : "WPA2/WPA3")]))
        }
        return parsed
    }

    // MARK: Calendar

    func event(_ text: String) -> Parsed {
        var info = EventInfo(summary: "")
        var inEvent = !text.uppercased().contains("BEGIN:VEVENT")
        for line in ContactParser.unfold(text) {
            let upper = line.uppercased()
            if upper.hasPrefix("BEGIN:VEVENT") { inEvent = true; continue }
            if upper.hasPrefix("END:VEVENT") { break }
            guard inEvent, let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon].uppercased()
            let name = head.split(separator: ";").first.map(String.init) ?? ""
            let value = String(line[line.index(after: colon)...])
            switch name {
            case "SUMMARY": info.summary = ContactParser.unescape(value).trimmed()
            case "DTSTART": info.start = DeviceParser.icsDate(value, params: String(head))
            case "DTEND": info.end = DeviceParser.icsDate(value, params: String(head))
            case "LOCATION": info.location = ContactParser.unescape(value).trimmed().nilIfEmpty
            case "DESCRIPTION": info.description = ContactParser.unescape(value).trimmed().nilIfEmpty
            case "URL": info.url = value.trimmed().nilIfEmpty
            default: break
            }
        }
        if info.summary.isEmpty { info.summary = info.location ?? "Událost" }
        var parsed = Parsed(type: .event, content: .event(info))
        if let url = info.url { parsed.embeddedLinks.append(url) }
        return parsed
    }

    /// "20261012T180000" → "2026-10-12T18:00"; UTC ("…Z") converted to Prague time; dates → "2026-10-12".
    static func icsDate(_ value: String, params: String) -> String? {
        let v = value.trimmed()
        let digits = v.filter(\.isASCIIDigit)
        guard digits.count >= 8 else { return nil }
        let d = Array(digits)
        let date = "\(String(d[0..<4]))-\(String(d[4..<6]))-\(String(d[6..<8]))"
        guard v.contains("T"), digits.count >= 12 else { return date }
        var time = "\(String(d[8..<10])):\(String(d[10..<12]))"
        if v.hasSuffix("Z") {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd'T'HH:mm"
            if let utc = f.date(from: "\(date)T\(time)") {
                let local = Format.isoDateTime.string(from: utc)
                return local
            }
        }
        time = String(time.prefix(5))
        return "\(date)T\(time)"
    }

    // MARK: Places

    func geo(_ text: String) -> Parsed {
        let body = String(text.dropFirst(4))
        let parts = body.split(separator: "?", maxSplits: 1).map(String.init)
        let coords = (parts.first ?? "").split(separator: ";").first.map(String.init) ?? ""
        let numbers = coords.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        var label: String?
        if parts.count > 1 {
            for pair in parts[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.first == "q", kv.count > 1 {
                    var q = kv[1].replacingOccurrences(of: "+", with: " ").percentDecoded
                    // "q=50.08,14.42(Label)" form
                    if let open = q.firstIndex(of: "("), q.hasSuffix(")") {
                        q = String(q[q.index(after: open)..<q.index(before: q.endIndex)])
                    }
                    label = q.trimmed().nilIfEmpty
                }
            }
        }
        guard numbers.count >= 2, (-90...90).contains(numbers[0]), (-180...180).contains(numbers[1]) else {
            return self.text(text, rules: .bundled)
        }
        let info = GeoInfo(lat: numbers[0], lon: numbers[1], label: label)
        return Parsed(type: .geo, content: .geo(info), decodeOnly: true)
    }

    // MARK: Travel and health

    func healthCertificate() -> Parsed {
        var parsed = Parsed(type: .hc1, content: .healthCertificate, sensitivity: .personal)
        parsed.consequences.append(Finding("csq.personal_data", ["what": .localized(LocalizedText(
            cs: "EU zdravotní certifikát obsahuje jméno a datum narození.",
            en: "An EU health certificate contains your name and date of birth."))]))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    /// IATA Bar Coded Boarding Pass (mandatory unique + first repeated section).
    func boardingPass(_ text: String) -> Parsed? {
        let chars = Array(text)
        guard chars.count >= 58, chars[0] == "M", chars[1].isASCIIDigit, chars[22] == "E" || chars[22] == " " else { return nil }
        func field(_ start: Int, _ length: Int) -> String {
            String(chars[start..<min(start + length, chars.count)]).trimmingCharacters(in: .whitespaces)
        }
        let from = field(30, 3), to = field(33, 3)
        guard from.count == 3, to.count == 3, from.allSatisfy(\.isLetter), to.allSatisfy(\.isLetter) else { return nil }
        let flight = String(field(39, 5).drop(while: { $0 == "0" }))
        let julian = Int(field(44, 3)) ?? 0
        var seat = field(48, 4)
        seat = String(seat.drop(while: { $0 == "0" }))
        var date: LocalizedText?
        if (1...366).contains(julian) {
            var components = DateComponents()
            components.year = Calendar(identifier: .gregorian).component(.year, from: Date())
            components.day = julian
            if let d = Calendar(identifier: .gregorian).date(from: components) {
                let cs = DateFormatter(), en = DateFormatter()
                cs.locale = Locale(identifier: "cs_CZ")
                cs.dateFormat = "d. M."
                en.locale = Locale(identifier: "en_GB")
                en.dateFormat = "d MMM"
                date = LocalizedText(cs: cs.string(from: d), en: en.string(from: d))
            }
        }
        let info = BoardingPassInfo(name: field(2, 20), pnr: field(23, 7), from: from, to: to, carrier: field(36, 3),
                                    flight: flight, date: date, seat: seat, class: field(47, 1).nilIfEmpty)
        var parsed = Parsed(type: .bcbp, content: .boardingPass(info), sensitivity: .personal)
        parsed.consequences.append(Finding("csq.personal_data", ["what": .localized(LocalizedText(
            cs: "Palubní vstupenka obsahuje jméno a rezervační kód — s ním jde změnit let.",
            en: "A boarding pass contains your name and booking code — enough to change the flight."))]))
        parsed.checks.append(Finding("chk.sensitive_local"))
        return parsed
    }

    // MARK: Executable content

    func script(_ text: String) -> Parsed {
        let code = String(text.dropFirst("javascript:".count)).percentDecoded
        var parsed = Parsed(type: .jsURI, content: .script(ScriptInfo(code: String(code.prefix(500)))))
        parsed.consequences.append(Finding("csq.executable_content", ["what": .localized(LocalizedText(
            cs: "Kód obsahuje skript.", en: "The code contains a script."))]))
        return parsed
    }

    func dataURI(_ text: String) -> Parsed {
        let body = String(text.dropFirst(5))
        let comma = body.firstIndex(of: ",") ?? body.endIndex
        let meta = String(body[..<comma])
        let payload = comma < body.endIndex ? String(body[body.index(after: comma)...]) : ""
        let metaParts = meta.split(separator: ";").map(String.init)
        let mime = (metaParts.first?.isEmpty == false ? metaParts.first! : "text/plain").lowercased()
        let isBase64 = metaParts.contains { $0.lowercased() == "base64" }
        var decoded = ""
        if isBase64 {
            var b64 = payload.percentDecoded
            while b64.count % 4 != 0 { b64 += "=" }
            if let data = Data(base64Encoded: b64, options: .ignoreUnknownCharacters) {
                decoded = String(decoding: data.prefix(64 * 1024), as: UTF8.self)
            }
        } else {
            decoded = payload.percentDecoded
        }
        let info = DataURIInfo(mime: mime, preview: String(decoded.prefix(600)))
        var parsed = Parsed(type: .dataURI, content: .dataURI(info))
        let isHTML = mime.contains("html") || mime.contains("svg") || mime.contains("javascript")
        let hasForm = decoded.lowercased().contains("<form") || decoded.lowercased().contains("<input")
        parsed.consequences.append(Finding("csq.executable_content", ["what": .localized(
            isHTML && hasForm
                ? LocalizedText(cs: "Kód obsahuje celou webovou stránku s formulářem.", en: "The code contains a whole web page with a form.")
                : isHTML ? LocalizedText(cs: "Kód obsahuje celou webovou stránku.", en: "The code contains a whole web page.")
                : LocalizedText(cs: "Kód obsahuje vložený soubor (\(mime)).", en: "The code contains an embedded file (\(mime)).")
        )]))
        return parsed
    }

    // MARK: Text

    func text(_ text: String, rules: RuleSet) -> Parsed {
        var entities: [TextEntity] = []
        var links: [String] = []
        // URLs and bare www. domains
        if let re = try? NSRegularExpression(pattern: "(?i)\\b(?:https?://|www\\.)[^\\s<>\"]+") {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                var value = String(text[r])
                while let last = value.last, ".,;:!?)".contains(last) { value.removeLast() }
                entities.append(TextEntity(kind: "url", value: value))
                links.append(value.lowercased().hasPrefix("www.") ? "https://" + value : value)
            }
        }
        // IBANs and Czech domestic accounts
        if let re = try? NSRegularExpression(pattern: "\\b[A-Z]{2}[0-9]{2}(?: ?[A-Z0-9]{4}){3,7}(?: ?[A-Z0-9]{1,4})?\\b") {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                let value = String(text[r])
                if Banking.isValidIBAN(value) { entities.append(TextEntity(kind: "iban", value: value)) }
            }
        }
        if let re = try? NSRegularExpression(pattern: "(?<![0-9/-])(?:[0-9]{1,6}-)?[0-9]{2,10}/[0-9]{4}(?![0-9])") {
            for m in re.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                guard let r = Range(m.range, in: text) else { continue }
                entities.append(TextEntity(kind: "account", value: String(text[r])))
            }
        }
        // Phrases that suggest "move your money to a safe account"
        for phrase in rules.keywords.safeAccountPhrases {
            if let r = DeviceParser.originalRange(of: phrase, in: text) {
                entities.append(TextEntity(kind: "phrase", value: String(text[r])))
                break
            }
        }
        let info = TextInfo(text: text, entities: entities)
        var parsed = Parsed(type: .text, content: .text(info))
        parsed.embeddedLinks = links
        if links.isEmpty { parsed.checks.append(Finding("chk.no_links")) }
        return parsed
    }

    /// Finds a folded `phrase` in `text` and returns the range in the original spelling.
    static func originalRange(of phrase: String, in text: String) -> Range<String.Index>? {
        // Fold character by character so indexes stay aligned with the original text.
        let chars = Array(text)
        let foldedChars = chars.map { String($0).folded }
        let target = phrase
        var i = 0
        while i < chars.count {
            var j = i
            var built = ""
            while j < chars.count, built.count < target.count {
                built += foldedChars[j]
                j += 1
            }
            if built == target {
                let before = i == 0 || !(chars[i - 1].isLetter || chars[i - 1].isNumber)
                let after = j >= chars.count || !(chars[j].isLetter || chars[j].isNumber)
                if before && after {
                    let start = text.index(text.startIndex, offsetBy: i)
                    let end = text.index(text.startIndex, offsetBy: j)
                    return start..<end
                }
            }
            i += 1
        }
        return nil
    }
}
