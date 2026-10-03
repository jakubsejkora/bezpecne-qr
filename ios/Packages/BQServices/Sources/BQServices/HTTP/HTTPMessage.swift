import Foundation

/// Response header fields in received order. Names compare case-insensitively.
public struct HTTPHeaders: Sendable, Hashable, Sequence {
    public struct Field: Sendable, Hashable {
        public var name: String
        public var value: String
    }

    public private(set) var fields: [Field]

    public init(_ fields: [(String, String)] = []) {
        self.fields = fields.map { Field(name: $0.0, value: $0.1) }
    }

    mutating func append(name: String, value: String) {
        fields.append(Field(name: name, value: value))
    }

    /// The first value of `name`, or nil.
    public subscript(_ name: String) -> String? {
        fields.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    /// Every value of `name`, in order.
    public func values(_ name: String) -> [String] {
        fields.filter { $0.name.caseInsensitiveCompare(name) == .orderedSame }.map(\.value)
    }

    public func makeIterator() -> IndexingIterator<[Field]> { fields.makeIterator() }
}

/// One HTTP response as received by `SafeFetcher` (content coding already removed).
public struct HTTPResponse: Sendable, Hashable {
    /// How the body ended.
    public enum BodyState: String, Sendable, Hashable {
        /// The whole body was received (and checksums matched where the coding has them).
        case complete
        /// A byte cap was reached; `body` holds the first part.
        case truncated
        /// The connection ended early or the body framing broke; `body` holds what arrived.
        case interrupted
        /// The deadline passed while the body was arriving; `body` holds what arrived.
        case timedOut
        /// Not read on purpose (a redirect, or content we don't analyse).
        case skipped
    }

    public var status: Int
    public var reason: String
    public var headers: HTTPHeaders
    public var body: Data
    public var bodyState: BodyState
    /// The vetted address the connection was bound to (nil in fakes).
    public var remoteAddress: String?

    public init(status: Int, reason: String = "", headers: HTTPHeaders = HTTPHeaders(), body: Data = Data(),
                bodyState: BodyState = .complete, remoteAddress: String? = nil) {
        self.status = status
        self.reason = reason
        self.headers = headers
        self.body = body
        self.bodyState = bodyState
        self.remoteAddress = remoteAddress
    }

    /// 301, 302, 303, 307 and 308 — the statuses a browser follows via `Location`.
    public var isRedirect: Bool { [301, 302, 303, 307, 308].contains(status) }

    /// The media type of `Content-Type`, lowercased ("text/html"), or nil.
    public var mediaType: String? { ContentType(headers["content-type"])?.mediaType }

    /// The `charset` parameter of `Content-Type`, or nil.
    public var charset: String? { ContentType(headers["content-type"])?.charset }
}

/// A parsed `Content-Type` value.
struct ContentType: Equatable {
    var mediaType: String
    var charset: String?

    init?(_ value: String?) {
        guard let value else { return nil }
        let parts = value.split(separator: ";", omittingEmptySubsequences: false)
        let type = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
        guard !type.isEmpty else { return nil }
        mediaType = type
        for parameter in parts.dropFirst() {
            let pair = parameter.split(separator: "=", maxSplits: 1)
            guard pair.count == 2, pair[0].trimmingCharacters(in: .whitespaces).lowercased() == "charset" else { continue }
            let raw = pair[1].trimmingCharacters(in: .whitespaces)
            let unquoted = raw.count >= 2 && raw.hasPrefix("\"") && raw.hasSuffix("\"") ? String(raw.dropFirst().dropLast()) : raw
            if !unquoted.isEmpty { charset = unquoted }
            break
        }
    }

    /// Whether a browser would render this as an HTML document.
    var isHTML: Bool { mediaType == "text/html" || mediaType == "application/xhtml+xml" }
}

/// What a fetch may consume. Exceeding a body cap truncates the body; it is not an error.
public struct FetchLimits: Sendable, Hashable {
    /// Status line plus all header fields (interim responses and trailers included).
    public var maxHeaderBytes: Int
    /// Body bytes as sent (after chunk framing, before decompression).
    public var maxCompressedBytes: Int
    /// Body bytes after removing the content coding.
    public var maxDecodedBytes: Int

    public init(maxHeaderBytes: Int = 32 * 1024, maxCompressedBytes: Int = 1024 * 1024, maxDecodedBytes: Int = 512 * 1024) {
        self.maxHeaderBytes = maxHeaderBytes
        self.maxCompressedBytes = maxCompressedBytes
        self.maxDecodedBytes = maxDecodedBytes
    }
}

/// One GET request for an `HTTPTransport`.
public struct FetchRequest: Sendable {
    public enum BodyPolicy: Sendable, Hashable {
        /// Always read the body (up to the caps).
        case always
        /// Return right after the header section for redirects and for content that isn't HTML
        /// (a missing `Content-Type` is read so it can be sniffed).
        case htmlOnly
    }

    /// An `https` URL. Credentials and the fragment are never sent.
    public var url: URL
    /// Everything — DNS, connect, TLS and the body — must finish by this instant.
    public var deadline: Deadline
    public var limits: FetchLimits
    public var bodyPolicy: BodyPolicy

    public init(url: URL, deadline: Deadline, limits: FetchLimits = FetchLimits(), bodyPolicy: BodyPolicy = .always) {
        self.url = url
        self.deadline = deadline
        self.limits = limits
        self.bodyPolicy = bodyPolicy
    }

    /// A request that must finish within `timeout` from now (3 s by default, DNS and TLS included).
    public init(url: URL, timeout: Duration = .seconds(3), limits: FetchLimits = FetchLimits(), bodyPolicy: BodyPolicy = .always) {
        self.init(url: url, deadline: .now + timeout, limits: limits, bodyPolicy: bodyPolicy)
    }
}

/// Why a fetch produced no response.
public enum FetchError: Error, Sendable, Hashable {
    /// Not an `https` URL, or a host / request target we refuse to put on the wire.
    case invalidRequest
    /// The name resolved to at least one non-public address (DNS rebinding / SSRF guard), directly
    /// or through a NAT64 prefix.
    case nonPublicAddress
    /// The name resolved only to IPv6 addresses on a network whose NAT64 prefix is unknown, so they
    /// could not be vetted.
    case unverifiableAddress
    /// The name did not resolve (or resolved to nothing).
    case nameNotResolved
    /// No usable network path.
    case offline
    case timeout
    /// TCP connection refused, reset or unreachable.
    case connectionFailed
    /// TLS handshake or certificate trust failed.
    case tlsFailed
    /// The server negotiated an application protocol other than HTTP/1.1.
    case unsupportedProtocol
    /// We could not prove the connection went to the vetted address (proxy, or a different peer).
    case bindingUnproven
    /// The response violated HTTP/1.1 framing or syntax before the body.
    case malformedResponse
    /// An unknown or corrupt content coding (bad gzip CRC32/ISIZE, invalid compressed data).
    case decodingFailed
    case cancelled
}

/// Performs exactly one request per call and never follows redirects. `SafeFetcher` is the
/// production implementation; tests inject fakes.
public protocol HTTPTransport: Sendable {
    func fetch(_ request: FetchRequest) async throws(FetchError) -> HTTPResponse
}
