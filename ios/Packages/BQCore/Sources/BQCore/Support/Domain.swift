import Foundation

/// Hostname helpers: IDN decoding, registrable domains and IP literals.
public enum DomainKit {
    /// Second-level public suffixes we recognise without bundling the full Public Suffix List.
    /// Free-hosting parents from freehosts.json are added as private suffixes.
    static let multiLabelSuffixes: Set<String> = [
        "co.uk", "org.uk", "ac.uk", "gov.uk", "ltd.uk", "plc.uk", "me.uk", "net.uk", "sch.uk", "nhs.uk", "police.uk",
        "com.au", "net.au", "org.au", "edu.au", "gov.au", "asn.au", "id.au",
        "co.nz", "org.nz", "net.nz", "govt.nz", "ac.nz",
        "co.jp", "ne.jp", "or.jp", "ac.jp", "go.jp", "gr.jp", "lg.jp",
        "com.br", "net.br", "org.br", "gov.br", "edu.br",
        "com.cn", "net.cn", "org.cn", "gov.cn", "edu.cn", "ac.cn",
        "com.hk", "org.hk", "net.hk", "edu.hk", "gov.hk",
        "com.tw", "org.tw", "net.tw", "edu.tw", "gov.tw",
        "com.sg", "net.sg", "org.sg", "edu.sg", "gov.sg",
        "com.my", "net.my", "org.my", "gov.my", "edu.my",
        "co.in", "net.in", "org.in", "firm.in", "gen.in", "ind.in", "ac.in", "edu.in", "gov.in", "res.in",
        "co.za", "org.za", "net.za", "gov.za", "ac.za", "web.za",
        "com.mx", "org.mx", "net.mx", "gob.mx", "edu.mx",
        "com.ar", "org.ar", "net.ar", "gob.ar", "edu.ar",
        "com.tr", "org.tr", "net.tr", "gov.tr", "edu.tr", "k12.tr",
        "com.ua", "org.ua", "net.ua", "gov.ua", "edu.ua", "in.ua",
        "co.il", "org.il", "net.il", "ac.il", "gov.il",
        "co.kr", "or.kr", "ne.kr", "go.kr", "ac.kr",
        "com.pl", "net.pl", "org.pl", "gov.pl", "edu.pl",
        "co.th", "in.th", "ac.th", "go.th", "or.th",
        "com.ph", "net.ph", "org.ph", "gov.ph", "edu.ph",
        "com.vn", "net.vn", "org.vn", "gov.vn", "edu.vn",
        "com.pk", "com.ng", "com.eg", "com.sa", "com.co", "com.pe", "com.ve", "com.ec", "com.bd", "com.np",
        "com.lk", "com.kh", "com.qa", "com.kw", "com.om", "com.bh", "com.lb", "com.jo", "com.cy", "com.mt",
        "com.gt", "com.py", "com.uy", "com.bo", "com.do", "com.pa", "com.ni", "com.sv", "com.hn",
        "co.ke", "or.ke", "co.tz", "co.ug", "co.zw", "co.zm", "co.bw",
        "eu.com", "uk.com", "us.com", "de.com", "gb.net", "us.org",
    ]

    /// Lowercased labels of a host, without a trailing dot.
    public static func labels(_ host: String) -> [String] {
        var h = host.lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        return h.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
    }

    /// The top-level domain ("top" for "csob-overeni.top").
    public static func tld(_ host: String) -> String {
        labels(host).last ?? ""
    }

    /// The registrable domain (eTLD+1). IP literals are returned unchanged.
    public static func registrable(_ host: String, privateSuffixes: [String] = []) -> String {
        let h = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        if isIPLiteral(h) { return h }
        let parts = labels(h)
        guard parts.count > 2 else { return h }
        // Private suffixes (free hosting): tenant.pages.dev is its own registrable domain.
        for suffix in privateSuffixes {
            let s = suffix.lowercased()
            if h.hasSuffix("." + s) {
                let tenantLabels = labels(String(h.dropLast(s.count + 1)))
                if let tenant = tenantLabels.last { return "\(tenant).\(s)" }
            }
        }
        let lastTwo = parts.suffix(2).joined(separator: ".")
        if multiLabelSuffixes.contains(lastTwo) {
            return parts.suffix(3).joined(separator: ".")
        }
        return lastTwo
    }

    /// Whether `host` equals `domain` or is a subdomain of it.
    public static func host(_ host: String, isWithin domain: String) -> Bool {
        func canonical(_ s: String) -> String {
            var x = s.lowercased()
            if x.hasSuffix(".") { x.removeLast() }
            return x
        }
        let h = canonical(host), d = canonical(domain)
        return h == d || h.hasSuffix("." + d)
    }

    public static func isIPLiteral(_ host: String) -> Bool {
        IPAddress(host) != nil
    }

    /// Decodes IDN labels ("xn--…") to Unicode. Invalid labels are kept as they are.
    public static func displayHost(_ asciiHost: String) -> String {
        labels(asciiHost).map { label in
            guard label.hasPrefix("xn--"), let decoded = Punycode.decode(String(label.dropFirst(4))) else { return label }
            return decoded
        }.joined(separator: ".")
    }

    /// Encodes Unicode labels to IDNA ASCII ("xn--…"); ASCII labels are lowercased.
    public static func asciiHost(_ host: String) -> String {
        labels(host).map { label in
            if label.allSatisfy({ $0.isASCII }) { return label }
            return Punycode.encode(label.precomposedStringWithCanonicalMapping).map { "xn--" + $0 } ?? label
        }.joined(separator: ".")
    }
}

extension URL {
    /// The host as it goes on the wire: IDNA (punycode) ASCII, lowercased; IPv6 in brackets.
    /// `URL.host` and `URLComponents.host` may return the decoded Unicode name instead.
    public var asciiHost: String? {
        guard let host = URLComponents(url: self, resolvingAgainstBaseURL: false)?.encodedHost, !host.isEmpty else { return nil }
        return host.lowercased()
    }
}

// MARK: - Punycode (RFC 3492)

public enum Punycode {
    private static let base = 36, tMin = 1, tMax = 26, skew = 38, damp = 700, initialBias = 72, initialN = 128

    private static func adapt(_ delta: Int, _ numPoints: Int, _ firstTime: Bool) -> Int {
        var delta = firstTime ? delta / damp : delta / 2
        delta += delta / numPoints
        var k = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            k += base
        }
        return k + (base - tMin + 1) * delta / (delta + skew)
    }

    private static func digitValue(_ c: Character) -> Int? {
        guard let a = c.asciiValue else { return nil }
        switch a {
        case 48...57: return Int(a) - 22      // 0-9 → 26-35
        case 65...90: return Int(a) - 65      // A-Z
        case 97...122: return Int(a) - 97     // a-z
        default: return nil
        }
    }

    private static func digitChar(_ d: Int) -> Character {
        Character(UnicodeScalar(UInt8(d < 26 ? d + 97 : d + 22)))
    }

    /// Decodes the part after "xn--".
    public static func decode(_ input: String) -> String? {
        var output: [UnicodeScalar] = []
        var basicEnd = input.startIndex
        if let lastDash = input.lastIndex(of: "-") {
            for c in input[..<lastDash] {
                guard c.isASCII, let s = c.unicodeScalars.first else { return nil }
                output.append(s)
            }
            basicEnd = input.index(after: lastDash)
        }
        var n = initialN, i = 0, bias = initialBias
        var idx = basicEnd
        while idx < input.endIndex {
            let oldI = i
            var w = 1, k = base
            while true {
                guard idx < input.endIndex, let digit = digitValue(input[idx]) else { return nil }
                idx = input.index(after: idx)
                i += digit * w
                let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                if digit < t { break }
                w *= base - t
                k += base
                if i > Int(Int32.max) || w > Int(Int32.max) { return nil }
            }
            bias = adapt(i - oldI, output.count + 1, oldI == 0)
            n += i / (output.count + 1)
            i %= output.count + 1
            guard let scalar = UnicodeScalar(n) else { return nil }
            output.insert(scalar, at: i)
            i += 1
        }
        var s = ""
        s.unicodeScalars.append(contentsOf: output)
        return s
    }

    /// Encodes a Unicode label (without the "xn--" prefix in the result).
    public static func encode(_ input: String) -> String? {
        let scalars = Array(input.unicodeScalars)
        var output = String(scalars.filter { $0.isASCII }.map { Character($0) })
        let basicCount = output.count
        var handled = basicCount
        if basicCount > 0 { output.append("-") }
        var n = initialN, delta = 0, bias = initialBias
        while handled < scalars.count {
            guard let m = scalars.map({ Int($0.value) }).filter({ $0 >= n }).min() else { return nil }
            delta += (m - n) * (handled + 1)
            n = m
            for s in scalars {
                let c = Int(s.value)
                if c < n { delta += 1 }
                if c == n {
                    var q = delta, k = base
                    while true {
                        let t = k <= bias ? tMin : (k >= bias + tMax ? tMax : k - bias)
                        if q < t { break }
                        output.append(digitChar(t + (q - t) % (base - t)))
                        q = (q - t) / (base - t)
                        k += base
                    }
                    output.append(digitChar(q))
                    bias = adapt(delta, handled + 1, handled == basicCount)
                    delta = 0
                    handled += 1
                }
            }
            delta += 1
            n += 1
        }
        return output
    }
}

// MARK: - IP addresses

/// A parsed IPv4 or IPv6 address with classification of special-use ranges.
public struct IPAddress: Sendable, Hashable, CustomStringConvertible {
    public enum Family: Sendable { case v4, v6 }

    public let family: Family
    /// 4 or 16 bytes, network order.
    public let bytes: [UInt8]

    /// Parses dotted IPv4, IPv6 (with or without brackets) and the decimal/hex IPv4 forms that
    /// browsers accept ("http://3115782423/").
    public init?(_ string: String) {
        var s = string.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("["), s.hasSuffix("]") { s = String(s.dropFirst().dropLast()) }
        if let pct = s.firstIndex(of: "%") { s = String(s[..<pct]) } // zone ID
        if let v4 = IPAddress.parseV4(s) {
            family = .v4
            bytes = v4
            return
        }
        if s.contains(":") {
            var addr = in6_addr()
            guard inet_pton(AF_INET6, s, &addr) == 1 else { return nil }
            family = .v6
            bytes = withUnsafeBytes(of: addr) { Array($0) }
            return
        }
        return nil
    }

    public init(v4 bytes: [UInt8]) {
        family = .v4
        self.bytes = bytes
    }

    public init(v6 bytes: [UInt8]) {
        family = .v6
        self.bytes = bytes
    }

    private static func parseV4(_ s: String) -> [UInt8]? {
        guard !s.isEmpty, s.allSatisfy({ $0.isASCII && ($0.isHexDigit || $0 == "." || $0 == "x" || $0 == "X") }) else { return nil }
        let parts = s.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        func value(_ p: Substring) -> UInt64? {
            if p.isEmpty { return nil }
            if p.lowercased().hasPrefix("0x") { return UInt64(p.dropFirst(2), radix: 16) }
            if p.count > 1, p.hasPrefix("0") { return UInt64(p.dropFirst(), radix: 8) }
            return UInt64(p, radix: 10)
        }
        let values = parts.compactMap(value)
        guard values.count == parts.count else { return nil }
        // A plain decimal word with no dots is only an IP when it is a number at all.
        var result: UInt64 = 0
        for (i, v) in values.enumerated() {
            if i < values.count - 1 {
                guard v <= 255 else { return nil }
                result = result << 8 | v
            } else {
                let remaining = 4 - (values.count - 1)
                guard v < (UInt64(1) << (8 * UInt64(remaining))) else { return nil }
                result = result << (8 * UInt64(remaining)) | v
            }
        }
        // Purely alphabetic hex-looking hosts like "cafe" must not parse as IPs.
        if parts.count == 1, !s.allSatisfy(\.isNumber), !s.lowercased().hasPrefix("0x") { return nil }
        return [UInt8((result >> 24) & 0xff), UInt8((result >> 16) & 0xff), UInt8((result >> 8) & 0xff), UInt8(result & 0xff)]
    }

    public var description: String {
        switch family {
        case .v4: return bytes.map(String.init).joined(separator: ".")
        case .v6:
            var addr = in6_addr()
            withUnsafeMutableBytes(of: &addr) { $0.copyBytes(from: bytes) }
            var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
            inet_ntop(AF_INET6, &addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
            return String(decoding: buffer.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }, as: UTF8.self)
        }
    }

    /// The IPv4 address embedded in an IPv4-mapped (::ffff:a.b.c.d) or NAT64 (64:ff9b::/96) address.
    public var embeddedV4: IPAddress? {
        guard family == .v6 else { return nil }
        let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        let nat64 = bytes[0..<12] == [0x00, 0x64, 0xff, 0x9b, 0, 0, 0, 0, 0, 0, 0, 0][...]
        return mapped || nat64 ? IPAddress(v4: Array(bytes[12..<16])) : nil
    }

    /// True for globally routable unicast addresses. Everything private, loopback, link-local,
    /// shared (CGNAT), multicast, documentation, benchmarking or reserved is not public.
    public var isPublic: Bool {
        switch family {
        case .v4:
            let a = bytes[0], b = bytes[1], c = bytes[2]
            if a == 0 || a == 10 || a == 127 { return false }
            if a == 100 && (64...127).contains(b) { return false }          // 100.64/10 CGNAT
            if a == 169 && b == 254 { return false }                        // link-local
            if a == 172 && (16...31).contains(b) { return false }
            if a == 192 && b == 168 { return false }
            if a == 192 && b == 0 && (c == 0 || c == 2) { return false }    // 192.0.0/24, 192.0.2/24
            if a == 192 && b == 88 && c == 99 { return false }              // 6to4 relay anycast
            if a == 198 && (b == 18 || b == 19) { return false }            // benchmarking
            if a == 198 && b == 51 && c == 100 { return false }             // documentation
            if a == 203 && b == 0 && c == 113 { return false }              // documentation
            if a >= 224 { return false }                                    // multicast + reserved
            return true
        case .v6:
            if let v4 = embeddedV4 { return v4.isPublic }
            if bytes.allSatisfy({ $0 == 0 }) { return false }               // ::
            if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return false } // ::1
            if bytes[0] == 0xff { return false }                            // multicast
            if bytes[0] & 0xfe == 0xfc { return false }                     // fc00::/7 unique local
            if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0x80 { return false } // fe80::/10 link-local
            if bytes[0] == 0xfe && bytes[1] & 0xc0 == 0xc0 { return false } // fec0::/10 site-local
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] & 0xFE == 0 { return false }    // 2001::/23 IETF protocol assignments (Teredo, benchmarking, ORCHID…)
            if bytes[0] == 0x20 && bytes[1] == 0x01 && bytes[2] == 0x0d && bytes[3] == 0xb8 { return false } // 2001:db8::/32 documentation
            if bytes[0] == 0x3f && bytes[1] & 0xF0 == 0xF0 { return false }                     // 3fff::/20 documentation (RFC 9637)
            if bytes[0] == 0x01 && bytes[1] == 0x00 && bytes[2..<8].allSatisfy({ $0 == 0 }) { return false } // 100::/64 discard
            if bytes[0] == 0x20 && bytes[1] == 0x02 {                       // 6to4: check embedded v4
                return IPAddress(v4: Array(bytes[2..<6])).isPublic
            }
            return bytes[0] & 0xe0 == 0x20                                  // 2000::/3 global unicast
        }
    }
}
