import Foundation

/// vCard 2.1/3.0/4.0, MECARD and BIZCARD.
struct ContactParser {
    func parse(_ text: String) -> Parsed {
        let upper = text.uppercased()
        let info: ContactInfo
        if upper.hasPrefix("MECARD:") {
            info = mecard(String(text.dropFirst(7)))
        } else if upper.hasPrefix("BIZCARD:") {
            info = bizcard(String(text.dropFirst(8)))
        } else {
            info = vcard(text)
        }
        var parsed = Parsed(type: .contact, content: .contact(info))
        parsed.embeddedLinks = info.urls
        return parsed
    }

    // MARK: vCard

    /// Unfolds continuation lines (RFC 6350 §3.2) and soft line breaks of quoted-printable values.
    static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            if (line.hasPrefix(" ") || line.hasPrefix("\t")), !lines.isEmpty {
                lines[lines.count - 1] += line.dropFirst()
            } else if let last = lines.last, last.hasSuffix("="), last.uppercased().contains("QUOTED-PRINTABLE") {
                lines[lines.count - 1] = String(last.dropLast()) + line
            } else {
                lines.append(line)
            }
        }
        return lines.filter { !$0.isEmpty }
    }

    static func unescape(_ s: String) -> String {
        var out = ""
        var escaping = false
        for c in s {
            if escaping {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        return out
    }

    static func decodeQuotedPrintable(_ s: String, charset: String?) -> String {
        var bytes: [UInt8] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "=", let end = s.index(i, offsetBy: 3, limitedBy: s.endIndex),
               let byte = UInt8(s[s.index(after: i)..<end], radix: 16) {
                bytes.append(byte)
                i = end
            } else {
                bytes.append(contentsOf: Array(String(c).utf8))
                i = s.index(after: i)
            }
        }
        let encoding: String.Encoding = {
            switch charset?.lowercased() {
            case "windows-1250", "cp1250": return .windowsCP1250
            case "iso-8859-2", "latin2": return .isoLatin2
            case "iso-8859-1", "latin1": return .isoLatin1
            default: return .utf8
            }
        }()
        return String(bytes: bytes, encoding: encoding) ?? String(decoding: bytes, as: UTF8.self)
    }

    func vcard(_ text: String) -> ContactInfo {
        var version = "3.0"
        var fn: String?, n: [String] = [], org: String?, title: String?, note: String?, bday: String?
        var tels: [String] = [], emails: [String] = [], urls: [String] = [], address: String?
        for line in ContactParser.unfold(text) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let head = line[..<colon]
            var value = String(line[line.index(after: colon)...])
            let headParts = head.split(separator: ";").map(String.init)
            var name = (headParts.first ?? "").uppercased()
            if let dot = name.lastIndex(of: ".") { name = String(name[name.index(after: dot)...]) } // item1.TEL
            let params = headParts.dropFirst().map { $0.uppercased() }
            if params.contains(where: { $0.contains("QUOTED-PRINTABLE") }) {
                let charset = headParts.first(where: { $0.uppercased().hasPrefix("CHARSET=") })?.split(separator: "=").last.map(String.init)
                value = ContactParser.decodeQuotedPrintable(value, charset: charset)
            }
            switch name {
            case "VERSION": version = value.trimmed()
            case "FN": fn = ContactParser.unescape(value).trimmed()
            case "N": n = value.split(separator: ";", omittingEmptySubsequences: false).map { ContactParser.unescape(String($0)).trimmed() }
            case "ORG": org = ContactParser.unescape(value.replacingOccurrences(of: ";", with: ", ")).trimmed()
            case "TITLE": title = ContactParser.unescape(value).trimmed()
            case "TEL": tels.append(PhoneFormat.display(value.replacingOccurrences(of: "tel:", with: "").trimmed()))
            case "EMAIL": emails.append(value.trimmed())
            case "URL": urls.append(ContactParser.unescape(value).trimmed())
            case "NOTE": note = ContactParser.unescape(value).trimmed()
            case "BDAY": bday = value.trimmed()
            case "ADR": address = address ?? ContactParser.formatAddress(value.split(separator: ";", omittingEmptySubsequences: false).map { ContactParser.unescape(String($0)).trimmed() })
            default: break
            }
        }
        let fromN = [n.count > 1 ? n[1] : "", n.first ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        let name = fn?.isEmpty == false ? fn! : (fromN.isEmpty ? (org ?? "?") : fromN)
        return ContactInfo(format: "vCard \(version)", name: name, org: org?.nilIfEmpty, title: title?.nilIfEmpty, tels: tels,
                           emails: emails, urls: urls, address: address, note: note?.nilIfEmpty, birthday: bday)
    }

    /// ADR: PO box; extended; street; locality; region; postal code; country.
    static func formatAddress(_ p: [String]) -> String? {
        func part(_ i: Int) -> String { i < p.count ? p[i] : "" }
        let street = [part(1), part(2)].filter { !$0.isEmpty }.joined(separator: " ")
        let town = [part(5), part(3)].filter { !$0.isEmpty }.joined(separator: " ")
        let country = part(6)
        let domestic = ["", "česko", "česká republika", "czech republic", "czechia", "cz"].contains(country.lowercased())
        let parts = [street, town, domestic ? "" : country].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    // MARK: MECARD / BIZCARD

    func mecard(_ body: String) -> ContactInfo {
        var name = "", org: String?, note: String?, address: String?, bday: String?
        var tels: [String] = [], emails: [String] = [], urls: [String] = []
        for field in DeviceParser.splitEscaped(body, separator: ";") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].uppercased(), value = String(field[field.index(after: colon)...])
            switch key {
            case "N":
                let parts = value.split(separator: ",", maxSplits: 1).map { String($0).trimmed() }
                name = parts.count == 2 ? "\(parts[1]) \(parts[0])" : value.trimmed()
            case "TEL", "TEL-AV": tels.append(PhoneFormat.display(value))
            case "EMAIL": emails.append(value)
            case "URL": urls.append(value)
            case "NOTE", "MEMO": note = value
            case "ADR": address = value.replacingOccurrences(of: ",", with: ", ").collapsedWhitespace
            case "BDAY": bday = value
            case "ORG": org = value
            default: break
            }
        }
        return ContactInfo(format: "MECARD", name: name.isEmpty ? "?" : name, org: org, title: nil, tels: tels, emails: emails,
                           urls: urls, address: address, note: note, birthday: bday)
    }

    func bizcard(_ body: String) -> ContactInfo {
        var first = "", last = "", title: String?, org: String?, address: String?
        var tels: [String] = [], emails: [String] = []
        for field in DeviceParser.splitEscaped(body, separator: ";") {
            guard let colon = field.firstIndex(of: ":") else { continue }
            let key = field[..<colon].uppercased(), value = String(field[field.index(after: colon)...])
            switch key {
            case "N": first = value
            case "X": last = value
            case "T": title = value
            case "C": org = value
            case "A": address = value
            case "B", "M", "F": tels.append(PhoneFormat.display(value))
            case "E": emails.append(value)
            default: break
            }
        }
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        return ContactInfo(format: "BIZCARD", name: name.isEmpty ? (org ?? "?") : name, org: org, title: title, tels: tels,
                           emails: emails, urls: [], address: address)
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
