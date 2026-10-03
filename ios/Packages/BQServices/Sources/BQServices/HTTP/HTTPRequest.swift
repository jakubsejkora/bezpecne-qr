import BQCore
import Foundation

/// A validated `https` request target: what goes on the wire, and what TLS must verify.
struct FetchTarget: Sendable, Hashable {
    /// Lowercased ASCII hostname without a trailing dot, or the canonical text of an IP literal.
    let host: String
    /// Set when the URL host is an IP literal (no DNS; certificate must carry a matching IP SAN).
    let ipLiteral: IPAddress?
    let port: UInt16
    /// Origin-form request target: absolute path plus query, never the fragment.
    let requestTarget: String
    /// `Host` header value.
    let hostHeader: String

    /// SNI name: the hostname, never an IP literal (RFC 6066).
    var serverName: String? { ipLiteral == nil ? host : nil }

    init(url: URL) throws(FetchError) {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              c.scheme?.lowercased() == "https",
              var rawHost = c.encodedHost, !rawHost.isEmpty else { throw .invalidRequest }
        // Brackets are allowed only around an IPv6 literal: Foundation also accepts
        // "https://[o2platba.cz]/", which must not reach DNS, SNI or Host as "o2platba.cz".
        if rawHost.hasPrefix("[") || rawHost.hasSuffix("]") {
            let inner = String(rawHost.dropFirst().dropLast())
            guard rawHost.hasPrefix("["), rawHost.hasSuffix("]"), IPAddress(inner)?.family == .v6 else { throw .invalidRequest }
            rawHost = inner
        }

        let port = c.port ?? 443
        guard (1...65535).contains(port) else { throw .invalidRequest }
        self.port = UInt16(port)

        if let ip = IPAddress(rawHost) {
            ipLiteral = ip
            host = ip.description
        } else {
            var h = rawHost.lowercased()
            if h.hasSuffix(".") { h.removeLast() }
            guard FetchTarget.isValidHostname(h) else { throw .invalidRequest }
            ipLiteral = nil
            host = h
        }

        var target = c.percentEncodedPath
        if target.isEmpty { target = "/" }
        if let query = c.percentEncodedQuery { target += "?" + query }
        // Only printable ASCII without spaces may appear in the request line.
        guard target.hasPrefix("/"), target.utf8.allSatisfy({ (0x21...0x7E).contains($0) }) else { throw .invalidRequest }
        requestTarget = target

        let hostPart = ipLiteral?.family == .v6 ? "[\(host)]" : host
        hostHeader = port == 443 ? hostPart : "\(hostPart):\(port)"
    }

    /// LDH labels (underscore tolerated), 1–63 octets each, 253 in total.
    static func isValidHostname(_ host: String) -> Bool {
        guard !host.isEmpty, host.utf8.count <= 253 else { return false }
        for label in host.split(separator: ".", omittingEmptySubsequences: false) {
            guard (1...63).contains(label.utf8.count), label.first != "-", label.last != "-" else { return false }
            guard label.utf8.allSatisfy({ ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D || $0 == 0x5F })
            else { return false }
        }
        return true
    }
}

/// Serializes the single GET that `SafeFetcher` sends. No cookies, no Referer, no credentials.
enum HTTPRequestSerializer {
    /// Mobile Safari 18.6 on an iPhone. Safari 26 keeps the same frozen OS token (18_6), so pages
    /// that key on the user agent see an ordinary current iPhone.
    static let defaultUserAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.6 Mobile/15E148 Safari/604.1"

    /// Only the codings `BodyDecoder` implements are advertised.
    static let acceptEncoding = "gzip, deflate, br"

    static func get(_ target: FetchTarget, userAgent: String = defaultUserAgent) -> [UInt8] {
        // A user agent with control characters would allow header injection; drop them.
        let ua = String(userAgent.unicodeScalars.filter { $0.isASCII && $0.value >= 0x20 && $0.value != 0x7F }.map(Character.init))
        let lines = [
            "GET \(target.requestTarget) HTTP/1.1",
            "Host: \(target.hostHeader)",
            "User-Agent: \(ua)",
            "Accept: text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language: cs-CZ,cs;q=0.9,en;q=0.8",
            "Accept-Encoding: \(acceptEncoding)",
            "Connection: close",
        ]
        return Array((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
    }
}
