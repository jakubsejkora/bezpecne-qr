import Foundation

/// The eligibility gate. Decides — before any network contact and again on every redirect hop —
/// whether a link may be loaded automatically. Pure and deterministic; BQServices enforces it.
public struct LinkGate: Sendable {
    public enum Decision: Sendable, Hashable {
        /// Load exactly this URL (credentials stripped).
        case fetch(URL)
        /// An `http://` link: load this HTTPS variant instead, never the cleartext original.
        case upgrade(URL)
        /// Don't load automatically. `reason` is an `inc.*` ID; `manual` = the user may start a
        /// one-shot inspection after an explanation.
        case skip(reason: String, manual: Bool)
        /// Operator / carrier-billing host: never contacted, to protect the phone number.
        case billingStop(host: String)
        /// Never load (private address, unsupported scheme, ambiguous URL…).
        case refuse(Refusal)
        /// Loading makes no sense (a download, profile or calendar file).
        case notNeeded(LocalizedText)
    }

    public enum Refusal: String, Sendable, Hashable {
        case unsupportedScheme
        case privateAddress
        case localName
        case ambiguous
        case invalid
    }

    let rules: RuleSet

    public init(rules: RuleSet = .bundled) {
        self.rules = rules
    }

    /// - Parameters:
    ///   - hop: 0 for the scanned link, 1… for redirect targets.
    ///   - manualOverride: the user asked for a one-shot inspection of a keyword-only skip.
    public func evaluate(_ url: URL, hop: Int, manualOverride: Bool = false) -> Decision {
        let raw = url.absoluteString
        // Parser-differential guards: anything a browser could read differently is refused.
        if raw.contains("\\") || raw.contains(where: { $0.isWhitespace || $0.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }) }) {
            return .refuse(.ambiguous)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased() else { return .refuse(.invalid) }
        guard scheme == "http" || scheme == "https" else { return .refuse(.unsupportedScheme) }
        guard let host = LinkGate.canonicalHost(components.encodedHost) else { return .refuse(.ambiguous) }
        // Every later check — and the request itself — uses this one canonical host.
        components.encodedHost = host
        if LinkGate.hasAmbiguousEncoding(components) { return .refuse(.ambiguous) }

        // Hosts that can only mean this device or the local network.
        if let ip = IPAddress(host) {
            if !ip.isPublic { return .refuse(.privateAddress) }
        } else {
            let labels = DomainKit.labels(host)
            if labels.count < 2 || host == "localhost" { return .refuse(.localName) }
            let localSuffixes = ["local", "localhost", "internal", "intranet", "lan", "home", "corp", "test", "invalid", "example", "onion"]
            if localSuffixes.contains(labels.last ?? "") || host.hasSuffix(".home.arpa") { return .refuse(.localName) }
            if !host.allSatisfy({ $0.isASCII }) { return .refuse(.ambiguous) } // IDN must arrive as punycode
        }

        // Never contact a mobile operator or a carrier-billing host, on any hop: the operator can
        // recognise the subscriber by the carrier IP address even over HTTPS.
        if isBillingHost(host) || isOperatorHost(host) {
            return .billingStop(host: host)
        }

        // Login and device-link URLs are sensitive codes; they are never contacted, on any hop.
        if SensitiveLinks.isLoginLink(host: host, path: components.path) {
            return .skip(reason: "inc.token_skipped", manual: false)
        }

        // Files we never download.
        if let file = fileKind(components.path) { return .notNeeded(file) }

        // Single-use links: tokens are never loaded automatically; sign-in paths only on request.
        if hasToken(components, depth: 0) { return .skip(reason: "inc.token_skipped", manual: false) }
        if hasAuthPath(components), !manualOverride { return .skip(reason: "inc.auth_path_skipped", manual: true) }

        // Credentials in the URL are a decoy at best; we never send them.
        components.user = nil
        components.password = nil

        if scheme == "http" {
            components.scheme = "https"
            if components.port == 80 { components.port = nil }
            guard let https = components.url else { return .refuse(.invalid) }
            return .upgrade(https)
        }
        guard let clean = components.url else { return .refuse(.invalid) }
        return .fetch(clean)
    }

    /// Lowercased ASCII host with a single trailing (FQDN) dot removed. Nil for empty hosts, empty
    /// labels ("a..b", "x.cz..") or anything else a resolver might read differently.
    static func canonicalHost(_ encoded: String?) -> String? {
        guard var host = encoded?.lowercased(), !host.isEmpty, !host.contains("%") else { return nil }
        if host.hasPrefix("[") || host.hasSuffix("]") {
            // Brackets are only valid around an IPv6 literal ("https://[o2platba.cz]/" is not).
            return host.hasPrefix("[") && host.hasSuffix("]") && IPAddress(host)?.family == .v6 ? host : nil
        }
        if host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.hasPrefix("."), !host.hasSuffix("."), !host.contains("..") else { return nil }
        return host
    }

    /// Percent-encoding that another decoding layer could read differently: invalid escapes, or
    /// escapes left in a path segment or query key after one decoding pass ("%2574oken" → "%74oken").
    static func hasAmbiguousEncoding(_ c: URLComponents) -> Bool {
        let invalidEscape = "%(?![0-9A-Fa-f]{2})"
        if c.percentEncodedPath.matches(invalidEscape) || (c.percentEncodedQuery ?? "").matches(invalidEscape)
            || (c.percentEncodedFragment ?? "").matches(invalidEscape) { return true }
        // Escapes that don't decode (e.g. invalid UTF-8) hide a parameter from the gate while the
        // request still sends it.
        func decodes(_ raw: String) -> Bool { !raw.contains("%") || raw.removingPercentEncoding != nil }
        if !c.percentEncodedPath.split(separator: "/").allSatisfy({ decodes(String($0)) }) { return true }
        for pair in (c.percentEncodedQuery ?? "").split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
            if !kv.allSatisfy({ decodes($0.replacingOccurrences(of: "+", with: " ")) }) { return true }
        }
        if let fragment = c.percentEncodedFragment, !decodes(fragment) { return true }
        let residual = "%[0-9A-Fa-f]{2}"
        if c.path.matches(residual) { return true }
        let segments = c.path.split(separator: "/", omittingEmptySubsequences: false)
        if segments.contains(where: { $0 == "." || $0 == ".." }) { return true }
        if (c.queryItems ?? []).contains(where: { $0.name.matches(residual) }) { return true }
        return false
    }

    // MARK: Billing and operators

    public func isBillingHost(_ host: String) -> Bool {
        let billing = rules.dcb.operatorBillingHosts + rules.dcb.aggregators.flatMap(\.domains)
        return billing.contains { DomainKit.host(host, isWithin: $0) }
    }

    public func isOperatorHost(_ host: String) -> Bool {
        rules.dcb.operatorDomains.contains { DomainKit.host(host, isWithin: $0) }
    }

    /// The billing aggregator or operator name for a host, for display.
    public func billingOwner(_ host: String) -> String? {
        if let agg = rules.dcb.aggregators.first(where: { a in a.domains.contains { DomainKit.host(host, isWithin: $0) } }) {
            return agg.name
        }
        return isBillingHost(host) || isOperatorHost(host) ? DomainKit.registrable(host) : nil
    }

    // MARK: Files

    func fileKind(_ path: String) -> LocalizedText? {
        let lower = path.lowercased()
        if lower.hasSuffix(".mobileconfig") { return LocalizedText(cs: "Profil nestahujeme.", en: "We don't download profiles.") }
        if lower.hasSuffix(".ics") || lower.hasSuffix(".ical") || lower.hasSuffix(".vcs") {
            return LocalizedText(cs: "Kalendář nestahujeme.", en: "We don't download calendars.")
        }
        let downloads = [".apk", ".aab", ".xapk", ".ipa", ".exe", ".msi", ".dmg", ".pkg", ".zip", ".rar", ".7z", ".bat", ".scr", ".jar"]
        if downloads.contains(where: { lower.hasSuffix($0) }) {
            return LocalizedText(cs: "Soubor ke stažení nenačítáme.", en: "We don't download files.")
        }
        return nil
    }

    // MARK: Tokens and sign-in paths

    func hasToken(_ c: URLComponents, depth: Int) -> Bool {
        let keys = Set(rules.keywords.tokenQueryKeys.map { $0.lowercased() })
        for item in c.queryItems ?? [] {
            if isTokenKey(item.name) { return true }
            guard let v = item.value, !v.isEmpty else { continue }
            let opaqueCounts = !LinkGate.isNonSecretParameter(item.name)
            if opaqueCounts, LinkGate.looksLikeToken(v) { return true }
            // A URL (or query string) nested in a parameter is sent with the outer request: check it too.
            if nestedHasToken(v, depth: depth, opaqueCounts: opaqueCounts) { return true }
        }
        if let fragment = c.fragment {
            let lower = fragment.lowercased()
            if keys.contains(where: { lower.contains("\($0)=") }) || LinkGate.looksLikeToken(fragment) { return true }
            for part in fragment.split(whereSeparator: { "&=/?".contains($0) }) where LinkGate.looksLikeToken(String(part)) { return true }
            if nestedHasToken(fragment, depth: depth) { return true }
        }
        for segment in c.path.split(separator: "/") where LinkGate.looksLikeToken(String(segment), pathSegment: true) { return true }
        return false
    }

    /// Parameters that carry marketing labels or click IDs, never credentials.
    static func isNonSecretParameter(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.hasPrefix("utm_") || ["gclid", "fbclid", "msclkid", "dclid", "mc_cid", "ref", "lang", "locale", "q", "query", "search"].contains(n)
    }

    /// Checks a parameter value (decoded once by URLComponents) that may hide a URL, a query string
    /// or a token behind further layers of percent-encoding. It never assigns untrusted text to
    /// Foundation's percent-encoded properties (they trap on invalid escapes), and it fails closed:
    /// anything it can't resolve within its limits counts as a token.
    private func nestedHasToken(_ value: String, depth: Int, opaqueCounts: Bool = true) -> Bool {
        // Peel up to four more layers ("%25253F" is a "?" three layers down).
        var layers = [value]
        var current = value
        for _ in 0..<4 {
            guard let next = current.removingPercentEncoding, next != current else { break }
            layers.append(next)
            current = next
        }
        if let next = current.removingPercentEncoding, next != current { return true }

        for layer in layers {
            if opaqueCounts, LinkGate.looksLikeToken(layer) { return true }
            guard layer.contains("://") || layer.contains("=") || layer.contains("?") else { continue }
            if depth >= 2 { return true }   // a URL inside a URL inside a URL: fail closed
            if layer.contains("://"), let inner = URLComponents(string: LinkParser.percentEncodeNonASCII(layer)) {
                // Credentials inside a nested URL travel in the outer request's query.
                if inner.percentEncodedUser != nil || inner.percentEncodedPassword != nil { return true }
                let host = LinkGate.canonicalHost(inner.encodedHost)
                if inner.encodedHost != nil, host == nil { return true }
                if let host, SensitiveLinks.isLoginLink(host: host, path: inner.path) { return true }
                if LinkGate.hasAmbiguousEncoding(inner) { return true }
                if hasToken(inner, depth: depth + 1) || hasAuthPath(inner) { return true }
            }
            let query = layer.split(separator: "?", maxSplits: 1).last.map(String.init) ?? layer
            for pair in LinkGate.pairs(query) {
                if isTokenKey(pair.key) || (!LinkGate.isNonSecretParameter(pair.key) && LinkGate.looksLikeToken(pair.value)) { return true }
                if !pair.value.isEmpty, pair.value != layer, nestedHasToken(pair.value, depth: depth + 1) { return true }
            }
        }
        return false
    }

    /// "a=1&b=2" → [(a, 1), (b, 2)], percent-decoded leniently (invalid escapes stay as text).
    static func pairs(_ query: String) -> [(key: String, value: String)] {
        query.split(whereSeparator: { $0 == "&" || $0 == ";" || $0 == "#" }).map { part in
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            let key = (kv.first ?? "").replacingOccurrences(of: "+", with: " ")
            let value = (kv.count > 1 ? kv[1] : "").replacingOccurrences(of: "+", with: " ")
            return (key.removingPercentEncoding ?? key, value.removingPercentEncoding ?? value)
        }
    }

    private func isTokenKey(_ name: String) -> Bool {
        let n = name.lowercased()
        return Set(rules.keywords.tokenQueryKeys.map { $0.lowercased() }).contains(n)
            || rules.keywords.tokenQueryPrefixes.map { $0.lowercased() }.contains(where: { n.hasPrefix($0) })
            || n.hasPrefix("saml")
    }

    /// JWTs, long hex strings, UUIDs and opaque base64url values (≥ 24 characters). Only readable
    /// slugs — words joined by separators — are exempt.
    static func looksLikeToken(_ value: String, pathSegment: Bool = false) -> Bool {
        let v = value.percentDecoded
        if v.matches("eyJ[A-Za-z0-9_-]{8,}\\.[A-Za-z0-9_-]{8,}") { return true }
        if v.matches("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$") { return true }
        if v.count >= 24, v.matches("^[0-9a-fA-F]+$") { return true }
        guard v.count >= 24, v.matches("^[A-Za-z0-9_=+/.~-]+$") else { return false }
        // Article slugs live in paths; an opaque-looking parameter value counts as a token even
        // when its chunks look pronounceable.
        return pathSegment ? !isReadableSlug(v) : true
    }

    /// "podvod-qr-kod-parkovani.A250101_120000_domaci_jkk" is readable: nearly every part is a word,
    /// a number or a short code. "GxqVrNzJ-KpTsWfHd-8yLcBaEe" is not.
    static func isReadableSlug(_ v: String) -> Bool {
        let parts = v.split(whereSeparator: { "-_.~+".contains($0) }).map(String.init)
        guard parts.count >= 3 else { return false }
        func isWord(_ p: String) -> Bool {
            if p.matches("^[0-9]{1,8}$") { return true }                       // numbers, dates
            if p.matches("^[A-Z]{1,4}$") { return true }                       // CZ, QR, DPH
            if p.matches("^[A-Z][0-9]{3,11}$") { return true }                 // A250101
            guard p.matches("^(?:[a-z]+|[A-Z][a-z]+)[0-9]{0,4}$") else { return false }
            let letters = p.filter(\.isLetter).lowercased()
            if letters.count < 4 { return true }
            let vowels = letters.filter { "aeiouy".contains($0) }.count
            return Double(vowels) / Double(letters.count) >= 0.2
        }
        return Double(parts.filter(isWord).count) / Double(parts.count) >= 0.75
    }

    func hasAuthPath(_ c: URLComponents) -> Bool {
        let families = rules.keywords.authPathFamilies.map { $0.lowercased() }
        let segments = c.path.folded.split(whereSeparator: { $0 == "/" }).map(String.init)
        for segment in segments {
            let words = segment.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
            for family in families {
                if family.contains("-") {
                    if segment.contains(family) { return true }
                    continue
                }
                for word in words where LinkGate.word(word, matchesFamily: family) { return true }
            }
        }
        for item in c.queryItems ?? [] where ["action", "do", "mode"].contains(item.name.lowercased()) {
            let value = (item.value ?? "").folded
            if families.contains(where: { LinkGate.word(value, matchesFamily: $0) }) { return true }
        }
        return false
    }

    static func word(_ word: String, matchesFamily family: String) -> Bool {
        switch family {
        case "auth":
            return ["auth", "authorize", "authorise", "authenticate", "authentication", "authorization"].contains(word)
        case "oauth":
            return word.hasPrefix("oauth")
        case "sso", "login", "logout", "prihlaseni", "overeni", "potvrzeni", "aktivace", "odhlasit", "zrusit":
            return word == family || word.hasPrefix(family)
        default:
            return word.hasPrefix(family)
        }
    }
}

/// Known open redirectors whose real destination is in a query parameter.
public enum OpenRedirect {
    static let patterns: [(host: String, path: String, params: [String])] = [
        ("google", "/url", ["q", "url"]),
        ("l.facebook.com", "/l.php", ["u"]),
        ("lm.facebook.com", "/l.php", ["u"]),
        ("l.instagram.com", "/", ["u"]),
        ("t.umblr.com", "/redirect", ["z"]),
        ("away.vk.com", "/away.php", ["to"]),
        ("www.youtube.com", "/redirect", ["q"]),
        ("slack-redirect.slack.com", "/link", ["url"]),
        ("out.reddit.com", "/", ["url"]),
        ("href.li", "/", []),
    ]

    /// Google's own domains (not "google.attacker.cz").
    static let googleDomains: Set<String> = [
        "google.com", "google.cz", "google.sk", "google.de", "google.at", "google.pl", "google.hu", "google.co.uk",
        "google.fr", "google.it", "google.es", "google.nl", "google.be", "google.ch", "google.com.ua",
    ]

    static func isGoogle(_ host: String) -> Bool {
        googleDomains.contains { host == $0 || host == "www." + $0 }
    }

    /// The destination hidden in an open-redirect link, if the link is one.
    public static func innerTarget(of url: URL) -> URL? {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = c.encodedHost?.lowercased() else { return nil }
        for p in patterns {
            let hostMatches = p.host == "google" ? OpenRedirect.isGoogle(host) : host == p.host
            guard hostMatches, c.path.hasPrefix(p.path) else { continue }
            for name in p.params {
                if let value = c.queryItems?.first(where: { $0.name == name })?.value,
                   let inner = URL(string: value), let scheme = inner.scheme?.lowercased(),
                   scheme == "http" || scheme == "https", inner.host != nil {
                    return inner
                }
            }
            // Generic: any query value that is itself an absolute http(s) URL.
            if p.params.isEmpty, let q = c.query, let inner = URL(string: q.percentDecoded), inner.host != nil { return inner }
        }
        return nil
    }
}

/// Web URLs that are really login / device-link codes. They belong to the sensitive class: never
/// contacted (on any hop), never stored, never reported.
public enum SensitiveLinks {
    /// (host, path prefix, service)
    static let loginLinks: [(host: String, path: String, service: String)] = [
        ("discord.com", "/ra/", "Discord"),
        ("discordapp.com", "/ra/", "Discord"),
        ("s.team", "/q/", "Steam"),
    ]

    /// The service name when `host` + `path` is a login / device-link URL.
    public static func loginService(host: String, path: String) -> String? {
        let h = host.lowercased()
        return loginLinks.first { DomainKit.host(h, isWithin: $0.host) && path.hasPrefix($0.path) }?.service
    }

    public static func isLoginLink(host: String, path: String) -> Bool {
        loginService(host: host, path: path) != nil
    }
}
