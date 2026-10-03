import BQCore
import Compression
import Foundation
import Network
import Synchronization
@testable import BQServices

/// Live tests run only with `BQ_LIVE_TESTS=1`.
let liveTestsEnabled = ProcessInfo.processInfo.environment["BQ_LIVE_TESTS"] == "1"

/// SplitMix64 — deterministic fragmentation patterns.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Splits `bytes` into random pieces of 1…`maxPiece` bytes.
func fragments(_ bytes: [UInt8], seed: UInt64, maxPiece: Int = 7) -> [[UInt8]] {
    var rng = SeededRandom(seed: seed)
    var pieces: [[UInt8]] = []
    var i = 0
    while i < bytes.count {
        let n = Int.random(in: 1...maxPiece, using: &rng)
        pieces.append(Array(bytes[i..<min(bytes.count, i + n)]))
        i += n
    }
    return pieces
}

// MARK: - Compression fixtures

enum Fixtures {
    static func encode(_ input: [UInt8], _ algorithm: compression_algorithm) -> [UInt8] {
        let stream = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { stream.deallocate() }
        guard compression_stream_init(stream, COMPRESSION_STREAM_ENCODE, algorithm) == COMPRESSION_STATUS_OK else { return [] }
        defer { compression_stream_destroy(stream) }
        let size = 64 * 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: size)
        defer { buffer.deallocate() }
        var out: [UInt8] = []
        let source = input.isEmpty ? [0] : input
        source.withUnsafeBufferPointer { src in
            stream.pointee.src_ptr = src.baseAddress!
            stream.pointee.src_size = input.count
            var status: compression_status
            repeat {
                stream.pointee.dst_ptr = buffer
                stream.pointee.dst_size = size
                status = compression_stream_process(stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                out.append(contentsOf: UnsafeBufferPointer(start: buffer, count: size - stream.pointee.dst_size))
            } while status == COMPRESSION_STATUS_OK
        }
        return out
    }

    /// Raw DEFLATE (RFC 1951).
    static func deflate(_ input: [UInt8]) -> [UInt8] { encode(input, COMPRESSION_ZLIB) }
    static func brotli(_ input: [UInt8]) -> [UInt8] { encode(input, COMPRESSION_BROTLI) }

    /// zlib wrapper (RFC 1950) with a correct Adler-32.
    static func zlib(_ input: [UInt8]) -> [UInt8] {
        var a: UInt32 = 1, b: UInt32 = 0
        for byte in input {
            a = (a + UInt32(byte)) % 65521
            b = (b + a) % 65521
        }
        let adler = b << 16 | a
        return [0x78, 0x9C] + deflate(input) + [UInt8(adler >> 24), UInt8(adler >> 16 & 0xFF), UInt8(adler >> 8 & 0xFF), UInt8(adler & 0xFF)]
    }

    /// gzip member (RFC 1952) with optional header fields.
    static func gzip(_ input: [UInt8], extra: [UInt8]? = nil, name: String? = nil, comment: String? = nil,
                     headerCRC: Bool = false, corruptCRC: Bool = false, corruptSize: Bool = false, reservedFlag: Bool = false) -> [UInt8] {
        var flags: UInt8 = 0
        if headerCRC { flags |= 0x02 }
        if extra != nil { flags |= 0x04 }
        if name != nil { flags |= 0x08 }
        if comment != nil { flags |= 0x10 }
        if reservedFlag { flags |= 0x20 }
        var header: [UInt8] = [0x1F, 0x8B, 8, flags, 0, 0, 0, 0, 0, 3]
        if let extra { header += [UInt8(extra.count & 0xFF), UInt8(extra.count >> 8)] + extra }
        if let name { header += Array(name.utf8) + [0] }
        if let comment { header += Array(comment.utf8) + [0] }
        if headerCRC {
            let crc = Banking.crc32(Data(header))
            header += [UInt8(crc & 0xFF), UInt8(crc >> 8 & 0xFF)]
        }
        var crc = Banking.crc32(Data(input))
        if corruptCRC { crc ^= 1 }
        var size = UInt32(truncatingIfNeeded: input.count)
        if corruptSize { size &+= 1 }
        let le = { (v: UInt32) -> [UInt8] in [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
        return header + deflate(input) + le(crc) + le(size)
    }
}

// MARK: - Fakes

/// Answers requests from a table (or a closure) and records every URL requested.
final class FakeTransport: HTTPTransport {
    enum Reply: Sendable {
        case response(HTTPResponse)
        case failure(FetchError)
        case delayed(Duration, HTTPResponse)
    }

    private let replies: @Sendable (URL) -> Reply
    private let log = Mutex<[URL]>([])

    init(_ replies: @escaping @Sendable (URL) -> Reply) {
        self.replies = replies
    }

    convenience init(_ table: [String: Reply]) {
        self.init { url in table[url.absoluteString] ?? .response(HTTPResponse(status: 404, headers: HTTPHeaders([("Content-Type", "text/html")]), body: Data("<title>Nenalezeno</title>".utf8))) }
    }

    var requested: [String] { log.withLock { $0.map(\.absoluteString) } }

    func fetch(_ request: FetchRequest) async throws(FetchError) -> HTTPResponse {
        log.withLock { $0.append(request.url) }
        switch replies(request.url) {
        case .response(let r): return r
        case .failure(let e): throw e
        case .delayed(let delay, let r):
            do {
                try await Task.sleep(until: min(ContinuousClock.now + delay, request.deadline), clock: .continuous)
            } catch {
                throw .cancelled
            }
            if request.deadline.hasPassed { throw .timeout }
            return r
        }
    }

    static func redirect(_ location: String, status: Int = 302) -> Reply {
        .response(HTTPResponse(status: status, headers: HTTPHeaders([("Location", location)]), bodyState: .skipped))
    }

    static func html(_ html: String, status: Int = 200, contentType: String = "text/html; charset=utf-8",
                     bodyState: HTTPResponse.BodyState = .complete) -> Reply {
        .response(HTTPResponse(status: status, headers: HTTPHeaders([("Content-Type", contentType)]), body: Data(html.utf8), bodyState: bodyState))
    }
}

/// Records which hosts and domains were checked; answers from tables.
final class FakeDomainChecker: DomainChecking {
    private let verdicts: [String: DomainFacts.Quad9]
    private let registrations: [String: RDAPRegistration]
    private let log = Mutex<[String]>([])

    init(verdicts: [String: DomainFacts.Quad9] = [:], registrations: [String: RDAPRegistration] = [:]) {
        self.verdicts = verdicts
        self.registrations = registrations
    }

    var calls: [String] { log.withLock { $0 } }

    func quad9(_ host: String, deadline: Deadline) async -> DomainFacts.Quad9 {
        log.withLock { $0.append("quad9:\(host)") }
        return verdicts[host] ?? .ok
    }

    func registration(_ domain: String, deadline: Deadline) async -> RDAPRegistration {
        log.withLock { $0.append("rdap:\(domain)") }
        return registrations[domain] ?? RDAPRegistration(registered: "2020-04-14", registry: "CZ.NIC")
    }
}

struct FixedReachability: NetworkReachability {
    var offline = false
    func isOffline() async -> Bool { offline }
}

/// Answers from a table (unknown names don't resolve) and records every name asked for.
final class FakeResolver: HostResolver {
    let answers: [String: [String]]
    private let log = Mutex<[String]>([])

    init(answers: [String: [String]]) {
        self.answers = answers
    }

    var calls: [String] { log.withLock { $0 } }

    func resolve(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress] {
        log.withLock { $0.append(host) }
        guard let list = answers[host] else { throw .nameNotResolved }
        return list.compactMap { BQCore.IPAddress($0) }
    }
}

/// A network path that tests can switch.
final class FakePaths: NetworkPathProviding {
    private let state: Mutex<PathSnapshot>

    init(signature: String = "wifi-1") {
        state = Mutex(PathSnapshot(signature: signature, usable: true))
    }

    func set(signature: String) {
        state.withLock { $0 = PathSnapshot(signature: signature, usable: true) }
    }

    func current() async -> PathSnapshot { state.withLock { $0 } }
}

/// An `AddressVetter` with a fake resolver and its own (not the shared) NAT64 discovery. IPv6
/// answers are used only when `answers` holds a synthesized ipv4only.arpa AAAA (a NAT64 prefix).
func testVetter(_ answers: [String: [String]], paths: FakePaths = FakePaths()) -> AddressVetter {
    let resolver = FakeResolver(answers: answers)
    return AddressVetter(resolver: resolver, translation: TranslationPrefixes(resolver: resolver, paths: paths))
}

/// The usual answers for ipv4only.arpa on a network without DNS64.
let noNAT64 = ["ipv4only.arpa": ["192.0.0.170", "192.0.0.171"]]
/// A DNS64 network with the network-specific prefix 2001:470:64::/96.
let nsp64 = ["ipv4only.arpa": ["2001:470:64::c000:aa", "2001:470:64::c000:ab", "192.0.0.170"]]

/// Vets names from a table: names listed as private fail with `nonPublicAddress`, others pass.
final class FakeVetter: HostVetting {
    private let failures: [String: FetchError]
    private let log = Mutex<[String]>([])

    init(_ failures: [String: FetchError] = [:]) {
        self.failures = failures
    }

    var calls: [String] { log.withLock { $0 } }

    func vet(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress] {
        log.withLock { $0.append(host) }
        if let failure = failures[host] { throw failure }
        return [BQCore.IPAddress("93.184.215.14")!]
    }
}

/// Counts connections a `SafeFetcher` tries to create.
final class ConnectionCounter: Sendable {
    private let count = Mutex(0)
    var value: Int { count.withLock { $0 } }

    var connector: Connector {
        Connector { endpoint, parameters in
            self.count.withLock { $0 += 1 }
            return NWConnection(to: endpoint, using: parameters)
        }
    }
}

/// Canned HTTPS responses for the Quad9 and RDAP clients; records requests. `delay` answers late
/// (cancellation-aware, like URLSession).
final class FakeEndpointClient: EndpointClient {
    private let handler: @Sendable (URLRequest) -> (Int, Data, [String: String])?
    private let delay: Duration
    private let log = Mutex<[URLRequest]>([])

    init(delay: Duration = .zero, _ handler: @escaping @Sendable (URLRequest) -> (Int, Data, [String: String])?) {
        self.delay = delay
        self.handler = handler
    }

    var requests: [URLRequest] { log.withLock { $0 } }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        log.withLock { $0.append(request) }
        if delay > .zero { try await Task.sleep(for: delay) }
        guard let (status, data, headers) = handler(request),
              let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/2", headerFields: headers) else {
            throw URLError(.cannotConnectToHost)
        }
        return (data, response)
    }
}

/// Serves canned responses inside URLSession for `URLSessionEndpointClient` tests (no network).
/// Bodies are delivered in chunks, one every `chunkInterval`, until the client stops loading.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Reply: Sendable {
        var status = 200
        var headers: [String: String] = [:]
        var chunks: [Data] = []
        /// Answer with a redirect to this URL instead.
        var redirect: URL?
    }

    /// Replies by URL; requests to other URLs fail.
    static let replies = Mutex<[String: Reply]>([:])
    /// URLs that were requested, and how many body chunks each delivered before it was stopped.
    static let log = Mutex<[(url: String, chunksSent: Int)]>([])
    static let chunkInterval: Duration = .milliseconds(5)

    private let stopped = Mutex(false)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let index = MockURLProtocol.log.withLock { log -> Int in
            log.append((url.absoluteString, 0))
            return log.count - 1
        }
        guard let reply = MockURLProtocol.replies.withLock({ $0[url.absoluteString] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        if let target = reply.redirect {
            let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1",
                                           headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: reply.status, httpVersion: "HTTP/1.1", headerFields: reply.headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        Task {
            for chunk in reply.chunks {
                if self.stopped.withLock({ $0 }) { return }
                self.client?.urlProtocol(self, didLoad: chunk)
                MockURLProtocol.log.withLock { $0[index].chunksSent += 1 }
                try? await Task.sleep(for: MockURLProtocol.chunkInterval)
            }
            if !self.stopped.withLock({ $0 }) { self.client?.urlProtocolDidFinishLoading(self) }
        }
    }

    override func stopLoading() {
        stopped.withLock { $0 = true }
    }

    static func client(maxResponseBytes: Int) -> URLSessionEndpointClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSessionEndpointClient(configuration: configuration, maxResponseBytes: maxResponseBytes)
    }
}

/// A fetch as a value, for tasks that are cancelled from outside.
func fetchResult(_ fetcher: SafeFetcher, _ request: FetchRequest) async -> Result<HTTPResponse, FetchError> {
    do {
        return .success(try await fetcher.fetch(request))
    } catch {
        return .failure(error)
    }
}

func hex(_ s: String) -> [UInt8] {
    var out: [UInt8] = []
    var it = s.makeIterator()
    while let a = it.next(), let b = it.next() { out.append(UInt8(String([a, b]), radix: 16)!) }
    return out
}
