import Foundation

/// Web links and link-like schemes (webcal, itms-services, intent, market).
struct LinkParser {
    let rules: RuleSet

    /// A URL split into the parts we need, with the host normalised to ASCII.
    struct Pieces {
        var original: String
        var scheme: String
        var userinfo: String?
        var host: String            // ASCII, lowercased
        var hostDisplay: String?    // Unicode, when different
        var port: Int?
        var components: URLComponents
        var url: URL
    }

    /// Splits `text` into URL pieces. Unicode hosts are converted to punycode and non-ASCII
    /// characters elsewhere are percent-encoded, so Foundation parses the same host a browser would.
    static func pieces(_ text: String) -> Pieces? {
        guard let parts = text.captures("^([A-Za-z][A-Za-z0-9+.-]*)://([^/?#]*)(.*)$", options: [.dotMatchesLineSeparators]),
              let scheme = parts[1]?.lowercased(), let authority = parts[2] else { return nil }
        var rest = parts[3] ?? ""
        var userinfo: String?
        var hostPort = authority
        if let at = authority.lastIndex(of: "@") {
            userinfo = String(authority[..<at])
            hostPort = String(authority[authority.index(after: at)...])
        }
        var host = hostPort
        var port: Int?
        if hostPort.hasPrefix("[") {
            if let close = hostPort.firstIndex(of: "]") {
                host = String(hostPort[...close])
                let after = hostPort[hostPort.index(after: close)...]
                if after.hasPrefix(":") { port = Int(after.dropFirst()) }
            }
        } else if let colon = hostPort.lastIndex(of: ":") {
            host = String(hostPort[..<colon])
            port = Int(hostPort[hostPort.index(after: colon)...])
        }
        guard !host.isEmpty else { return nil }
        let unicodeHost = host.lowercased()
        let asciiHost = DomainKit.asciiHost(unicodeHost.precomposedStringWithCanonicalMapping)
        let display = DomainKit.displayHost(asciiHost)

        rest = percentEncodeNonASCII(rest)
        var rebuilt = "\(scheme)://"
        if let userinfo { rebuilt += percentEncodeNonASCII(userinfo) + "@" }
        rebuilt += asciiHost
        if let port { rebuilt += ":\(port)" }
        rebuilt += rest
        guard let components = URLComponents(string: rebuilt), let url = components.url else { return nil }
        return Pieces(original: text, scheme: scheme, userinfo: userinfo, host: asciiHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")),
                      hostDisplay: display != asciiHost ? display : nil, port: port, components: components, url: url)
    }

    static func percentEncodeNonASCII(_ s: String) -> String {
        var out = ""
        for scalar in s.unicodeScalars {
            if scalar.isASCII, scalar != " ", scalar != "\"", scalar != "<", scalar != ">", scalar != "`", scalar.value > 0x20 {
                out.unicodeScalars.append(scalar)
            } else {
                for byte in String(scalar).utf8 { out += String(format: "%%%02X", byte) }
            }
        }
        return out
    }

    func registrable(_ host: String) -> String {
        DomainKit.registrable(host, privateSuffixes: rules.freeHosts)
    }

    func linkInfo(_ p: Pieces) -> LinkInfo {
        var info = LinkInfo(url: p.original, host: p.host, registrable: registrable(p.host), scheme: p.scheme,
                            port: p.port, userinfo: p.userinfo?.isEmpty == false ? p.userinfo : nil)
        if let display = p.hostDisplay {
            info.hostDisplay = display
            info.display = p.original.replacingOccurrences(of: p.host, with: display, options: .caseInsensitive)
        }
        if let inner = OpenRedirect.innerTarget(of: p.url) { info.inner = inner.absoluteString.percentDecoded }
        if p.scheme == "http" {
            var c = p.components
            c.scheme = "https"
            c.user = nil
            c.password = nil
            if c.port == 80 { c.port = nil }
            info.upgraded = c.url?.absoluteString
        }
        let last = (p.components.path as NSString).lastPathComponent
        let ext = (last as NSString).pathExtension.lowercased()
        if ["apk", "aab", "xapk", "ipa", "mobileconfig", "exe", "msi", "dmg", "pkg"].contains(ext) { info.file = last }
        return info
    }

    // MARK: http(s)

    func parse(_ text: String) -> Parsed {
        guard let p = LinkParser.pieces(text) else {
            return DeviceParser().text(text, rules: rules)
        }
        let host = p.host
        let path = p.components.path
        let query = p.components.queryItems ?? []

        // Login / device-link URLs (sensitive)
        if let service = SensitiveLinks.loginService(host: host, path: path) {
            return SecurityParser().loginParsed(service: service, kind: "login")
        }

        // GS1 Digital Link
        if let gs1 = gs1(p) { return gs1 }

        // App stores
        if ["apps.apple.com", "itunes.apple.com"].contains(host) {
            let appId = path.firstMatch("id[0-9]{5,}").map { String($0.dropFirst(2)) }
            let info = StoreInfo(url: text, store: "App Store", appId: appId, host: host, registrable: registrable(host))
            return Parsed(type: .store, content: .store(info), inspectTarget: p.url)
        }
        if host == "play.google.com", path.hasPrefix("/store/apps") {
            let appId = query.first(where: { $0.name == "id" })?.value
            let info = StoreInfo(url: text, store: "Google Play", appId: appId, host: host, registrable: registrable(host))
            return Parsed(type: .store, content: .store(info), inspectTarget: p.url)
        }

        // Messengers
        if let messenger = messenger(p, text: text) { return messenger }

        var parsed = Parsed(type: .url, content: .link(linkInfo(p)), inspectTarget: p.url)
        if case .link(let info) = parsed.content, let file = info.file {
            let ext = (file as NSString).pathExtension.lowercased()
            if ext == "mobileconfig" {
                parsed.subtype = .profile
                parsed.consequences.append(Finding("csq.profile_install"))
            } else if ["apk", "aab", "xapk"].contains(ext) {
                parsed.subtype = .download
                parsed.consequences.append(Finding("csq.apk_download"))
            } else {
                parsed.subtype = .download
            }
        }
        return parsed
    }

    func messenger(_ p: Pieces, text: String) -> Parsed? {
        let host = p.host
        let segments = p.components.path.split(separator: "/").map(String.init)
        let query = p.components.queryItems ?? []
        func make(_ service: String, _ target: String, _ kind: String, _ message: String? = nil) -> Parsed {
            let info = MessengerInfo(url: text, service: service, target: target, text: message, kind: kind,
                                     host: host, registrable: registrable(host))
            return Parsed(type: .messenger, content: .messenger(info), inspectTarget: p.url)
        }
        let textParam = query.first(where: { $0.name == "text" })?.value
        switch host {
        case "wa.me":
            guard let number = segments.first, number.allSatisfy(\.isASCIIDigit) else {
                return segments.first.map { make("WhatsApp", $0, "profile", textParam) }
            }
            return make("WhatsApp", PhoneFormat.display("+" + number), "chat", textParam)
        case "api.whatsapp.com", "web.whatsapp.com":
            guard let phone = query.first(where: { $0.name == "phone" })?.value?.filter(\.isASCIIDigit), !phone.isEmpty else { return nil }
            return make("WhatsApp", PhoneFormat.display("+" + phone), "chat", textParam)
        case "chat.whatsapp.com":
            return make("WhatsApp", "skupina", "group-invite")
        case "t.me", "telegram.me", "www.t.me":
            guard let first = segments.first else { return nil }
            if first.hasPrefix("+") || first == "joinchat" { return make("Telegram", "soukromá skupina", "group-invite") }
            return make("Telegram", "@" + first, "chat", textParam)
        case "signal.me":
            return make("Signal", "profil", "profile")
        case "signal.group":
            return make("Signal", "skupina", "group-invite")
        default:
            return nil
        }
    }

    func gs1(_ p: Pieces) -> Parsed? {
        let path = p.components.path
        guard let caps = path.captures("/01/([0-9]{8,14})(?:/|$)") , let gtin = caps[1] else { return nil }
        let isGS1Host = p.host == "id.gs1.org" || p.host.hasSuffix(".gs1.org")
        // Other resolvers use the same path syntax; require the AI 01 structure plus a 14-digit GTIN.
        guard isGS1Host || gtin.count == 14 else { return nil }
        let batch = path.captures("/10/([^/]+)")?[1].map(\.percentDecoded)
        let serial = path.captures("/21/([^/]+)")?[1].map(\.percentDecoded)
        var expiry: String?
        if let yymmdd = p.components.queryItems?.first(where: { $0.name == "17" })?.value, yymmdd.count == 6 {
            let chars = Array(yymmdd)
            var day = String(chars[4...5])
            let year = "20" + String(chars[0...1]), month = String(chars[2...3])
            if day == "00" { // "00" = last day of the month
                let f = Format.isoDate
                if let first = f.date(from: "\(year)-\(month)-01"),
                   let range = Calendar(identifier: .gregorian).range(of: .day, in: .month, for: first) {
                    day = String(format: "%02d", range.count)
                }
            }
            expiry = "\(year)-\(month)-\(day)"
        }
        let info = GS1Info(gtin: gtin, batch: batch, serial: serial, expiry: expiry, host: p.host)
        return Parsed(type: .gs1, content: .gs1(info), decodeOnly: false, embeddedLinks: [p.original])
    }

    // MARK: Other link schemes

    func webcal(_ text: String) -> Parsed {
        let https = "https" + text.dropFirst("webcal".count)
        guard let p = LinkParser.pieces(https) else { return DeviceParser().text(text, rules: rules) }
        var info = linkInfo(p)
        info.url = text
        info.scheme = "webcal"
        info.upgraded = nil
        var parsed = Parsed(type: .webcal, content: .link(info), inspectTarget: p.url)
        parsed.consequences.append(Finding("csq.calendar_subscription"))
        return parsed
    }

    func appInstall(_ text: String) -> Parsed {
        let components = URLComponents(string: LinkParser.percentEncodeNonASCII(text))
        let manifest = components?.queryItems?.first(where: { $0.name == "url" })?.value
        var info = AppInstallInfo(scheme: "itms-services", manifest: manifest)
        if let manifest, let p = LinkParser.pieces(manifest) {
            info.host = p.host
            info.registrable = registrable(p.host)
        }
        var parsed = Parsed(type: .appInstall, content: .appInstall(info))
        parsed.consequences.append(Finding("csq.app_install"))
        if let manifest { parsed.embeddedLinks.append(manifest) }
        return parsed
    }

    func intent(_ text: String) -> Parsed {
        // intent://host/path#Intent;scheme=…;package=…;S.browser_fallback_url=…;end
        var info = IntentInfo()
        if let hash = text.range(of: "#Intent;", options: .caseInsensitive) {
            let params = text[hash.upperBound...].split(separator: ";")
            for param in params {
                let kv = param.split(separator: "=", maxSplits: 1).map(String.init)
                guard kv.count == 2 else { continue }
                switch kv[0] {
                case "package": info.package = kv[1]
                case "scheme": info.scheme = kv[1]
                case "S.browser_fallback_url": info.fallback = kv[1].percentDecoded
                default: break
                }
            }
        }
        var parsed = Parsed(type: .intent, content: .intent(info))
        if let fallback = info.fallback, let p = LinkParser.pieces(fallback) {
            info.host = p.host
            info.registrable = registrable(p.host)
            parsed.content = .intent(info)
            parsed.embeddedLinks.append(fallback)
            parsed.inspectTarget = p.url
        }
        return parsed
    }

    func market(_ text: String) -> Parsed? {
        guard let c = URLComponents(string: text), let id = c.queryItems?.first(where: { $0.name == "id" })?.value else { return nil }
        let url = "https://play.google.com/store/apps/details?id=\(id)"
        let info = StoreInfo(url: text, store: "Google Play", appId: id, host: "play.google.com", registrable: "google.com")
        return Parsed(type: .store, content: .store(info), inspectTarget: URL(string: url))
    }
}
