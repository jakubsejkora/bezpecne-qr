import BQCore
import Foundation
import Network
import Security

/// A single-request HTTP/1.1 GET client on Network.framework, built so that the bytes go only to
/// an address we vetted.
///
/// Per request:
/// 1. The hostname is resolved with the system resolver and **every** A/AAAA record is vetted with
///    `IPAddress.isPublic`; one non-public record refuses the name (DNS-rebinding / SSRF guard).
///    Only the IPv4 answers are connected to: an IPv6 answer could reach a private destination
///    through a NAT64 translator, while on NAT64 networks the system synthesizes IPv6 for a vetted
///    IPv4 address itself (`AddressVetter`).
/// 2. `NWConnection`s go to the vetted IP endpoints themselves (never the hostname), racing at most
///    two addresses with a short stagger. TLS ≥ 1.2, SNI and certificate verification use the
///    original hostname against the system anchors, with issuer/revocation network fetches off.
///    No session resumption, tickets, false start, 0-RTT or TCP fast open; ALPN offers only
///    `http/1.1`.
/// 3. Once a connection is ready, its peer must be the vetted address (NAT64 synthesis of a vetted
///    IPv4 is accepted) and the establishment report must show no proxy. Otherwise it is cancelled
///    and the fetch fails with `bindingUnproven`.
/// 4. Exactly one GET goes through the winning connection; the response is parsed strictly and
///    decoded within byte caps; the deadline covers DNS, TLS and slow trickles.
public struct SafeFetcher: HTTPTransport {
    public struct Configuration: Sendable {
        public static let defaultUserAgent = HTTPRequestSerializer.defaultUserAgent

        public var userAgent: String
        /// Delay before the second vetted address joins the race.
        public var attemptStagger: Duration

        public init(userAgent: String = Configuration.defaultUserAgent, attemptStagger: Duration = .milliseconds(250)) {
            self.userAgent = userAgent
            self.attemptStagger = attemptStagger
        }
    }

    let vetter: any HostVetting
    let configuration: Configuration
    let connector: Connector

    public init(vetter: any HostVetting = AddressVetter(), configuration: Configuration = Configuration()) {
        self.init(vetter: vetter, configuration: configuration, connector: .network)
    }

    init(vetter: any HostVetting, configuration: Configuration, connector: Connector) {
        self.vetter = vetter
        self.configuration = configuration
        self.connector = connector
    }

    public func fetch(_ request: FetchRequest) async throws(FetchError) -> HTTPResponse {
        let target = try FetchTarget(url: request.url)
        let addresses = try await vetter.vet(target.host, deadline: request.deadline)
        if Task.isCancelled { throw .cancelled }
        if request.deadline.hasPassed { throw .timeout }

        let operation = FetchOperation(
            target: target,
            candidates: AddressPolicy.candidates(addresses),
            requestBytes: HTTPRequestSerializer.get(target, userAgent: configuration.userAgent),
            request: request,
            connector: connector,
            stagger: configuration.attemptStagger
        )
        return try await operation.run().get()
    }
}

/// Creates connections; tests substitute one that records attempts.
struct Connector: Sendable {
    let make: @Sendable (NWEndpoint, NWParameters) -> NWConnection

    static let network = Connector { NWConnection(to: $0, using: $1) }
}

// MARK: - TLS and transport parameters

enum TransportParameters {
    static func make(for target: FetchTarget, deadline: Deadline, verifyQueue: DispatchQueue) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let options = tls.securityProtocolOptions
        sec_protocol_options_set_min_tls_protocol_version(options, .TLSv12)
        if let serverName = target.serverName {
            sec_protocol_options_set_tls_server_name(options, serverName)
        }
        sec_protocol_options_add_tls_application_protocol(options, "http/1.1")
        // Nothing that links two inspections or sends data before authentication.
        sec_protocol_options_set_tls_resumption_enabled(options, false)
        sec_protocol_options_set_tls_tickets_enabled(options, false)
        sec_protocol_options_set_tls_false_start_enabled(options, false)
        sec_protocol_options_set_tls_renegotiation_enabled(options, false)
        // Ask for stapled OCSP and SCTs so trust can use them without network fetches.
        sec_protocol_options_set_tls_ocsp_enabled(options, true)
        sec_protocol_options_set_tls_sct_enabled(options, true)
        sec_protocol_options_set_peer_authentication_required(options, true)
        let host = target.host
        sec_protocol_options_set_verify_block(options, { _, trust, complete in
            complete(TrustEvaluator.evaluate(sec_trust_copy_ref(trust).takeRetainedValue(), host: host))
        }, verifyQueue)

        let tcp = NWProtocolTCP.Options()
        tcp.noDelay = true
        tcp.enableFastOpen = false
        tcp.connectionTimeout = max(1, Int(deadline.secondsRemaining.rounded(.up)))

        let parameters = NWParameters(tls: tls, tcp: tcp)
        parameters.preferNoProxies = true
        parameters.allowFastOpen = false
        parameters.includePeerToPeer = false
        parameters.multipathServiceType = .disabled
        return parameters
    }
}

/// Server trust: SSL policy for the original hostname (or IP literal) against the system anchors,
/// with network fetching disabled — no AIA issuer downloads and no OCSP/CRL requests. Stapled
/// OCSP responses and SCTs delivered in the handshake are still used.
enum TrustEvaluator {
    static func evaluate(_ trust: SecTrust, host: String) -> Bool {
        var policies = [SecPolicyCreateSSL(true, host as CFString)]
        let revocationFlags = CFOptionFlags(kSecRevocationUseAnyAvailableMethod | kSecRevocationNetworkAccessDisabled)
        if let revocation = SecPolicyCreateRevocation(revocationFlags) { policies.append(revocation) }
        guard SecTrustSetPolicies(trust, policies as CFArray) == errSecSuccess,
              SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess else { return false }
        return SecTrustEvaluateWithError(trust, nil)
    }
}

extension IPAddress {
    var networkHost: NWEndpoint.Host? {
        switch family {
        case .v4: return IPv4Address(Data(bytes)).map { .ipv4($0) }
        case .v6: return IPv6Address(Data(bytes)).map { .ipv6($0) }
        }
    }

    init?(networkHost: NWEndpoint.Host) {
        switch networkHost {
        case .ipv4(let a): self.init(v4: Array(a.rawValue))
        case .ipv6(let a): self.init(v6: Array(a.rawValue))
        default: return nil
        }
    }
}

// MARK: - One fetch

/// The state of one fetch. Its executor is the serial queue every `NWConnection` callback runs on,
/// so callbacks enter the actor synchronously with `assumeIsolated` and are handled in order.
/// The continuation is resumed exactly once by `finish`, whatever happens first: response, error,
/// deadline or task cancellation.
actor FetchOperation {
    private let queue = DispatchSerialQueue(label: "cz.bezpecneqr.fetch", qos: .userInitiated)
    nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    private let target: FetchTarget
    private let candidates: [IPAddress]
    private let requestBytes: [UInt8]
    private let request: FetchRequest
    private let connector: Connector
    private let stagger: Duration

    private var connections: [Int: NWConnection] = [:]
    private var failures: [Int: FetchError] = [:]
    /// The attempt whose establishment report is pending.
    private var verifying: Int?
    private var winner: Int?

    private var parser: HTTPResponseParser
    private var head: HTTPResponseParser.Head?
    private var decoder: BodyDecoder?
    private var wireBytes = 0
    private var bodyBytes = 0

    private var outcome: Result<HTTPResponse, FetchError>?
    private var continuation: CheckedContinuation<Result<HTTPResponse, FetchError>, Never>?

    init(target: FetchTarget, candidates: [IPAddress], requestBytes: [UInt8], request: FetchRequest,
         connector: Connector, stagger: Duration) {
        self.target = target
        self.candidates = candidates
        self.requestBytes = requestBytes
        self.request = request
        self.connector = connector
        self.stagger = stagger
        var limits = HTTPResponseParser.Limits()
        limits.maxHeaderBytes = request.limits.maxHeaderBytes
        parser = HTTPResponseParser(limits: limits)
    }

    func run() async -> Result<HTTPResponse, FetchError> {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if let outcome {
                    continuation.resume(returning: outcome)
                    return
                }
                self.continuation = continuation
                if Task.isCancelled { return finish(.failure(.cancelled)) }
                start()
            }
        } onCancel: {
            queue.async { [weak self] in self?.assumeIsolated { $0.finish(.failure(.cancelled)) } }
        }
    }

    // MARK: Connecting

    private func start() {
        guard !candidates.isEmpty else { return finish(.failure(.nameNotResolved)) }
        guard !request.deadline.hasPassed else { return finish(.failure(.timeout)) }
        queue.asyncAfter(deadline: request.deadline.dispatchTime) { [weak self] in
            self?.assumeIsolated { $0.deadlineReached() }
        }
        startAttempt(0)
        if candidates.count > 1 {
            queue.asyncAfter(deadline: .now() + stagger.dispatchInterval) { [weak self] in
                self?.assumeIsolated { $0.startAttempt(1) }
            }
        }
    }

    private func startAttempt(_ i: Int) {
        guard outcome == nil, winner == nil, i < candidates.count, connections[i] == nil, failures[i] == nil else { return }
        guard let host = candidates[i].networkHost, let port = NWEndpoint.Port(rawValue: target.port) else {
            return attemptFailed(i, .connectionFailed)
        }
        let parameters = TransportParameters.make(for: target, deadline: request.deadline, verifyQueue: queue)
        let connection = connector.make(.hostPort(host: host, port: port), parameters)
        connections[i] = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.assumeIsolated { $0.attempt(i, changed: state) }
        }
        connection.start(queue: queue)
    }

    private func attempt(_ i: Int, changed state: NWConnection.State) {
        guard outcome == nil, i != winner else { return } // the winner's failures surface in receive
        switch state {
        case .ready:
            guard winner == nil, verifying == nil else { return } // cancelled once the winner is adopted
            verify(i)
        case .waiting(let error):
            let unsatisfied = connections[i]?.currentPath?.status == .unsatisfied
            attemptFailed(i, unsatisfied ? .offline : FetchOperation.map(error))
        case .failed(let error):
            attemptFailed(i, FetchOperation.map(error))
        default:
            break
        }
    }

    private func attemptFailed(_ i: Int, _ error: FetchError) {
        failures[i] = error
        if let connection = connections.removeValue(forKey: i) {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        if verifying == i {
            verifying = nil
            // Another attempt may have become ready while this one was being verified.
            if let ready = connections.first(where: { $0.value.state == .ready })?.key { verify(ready) }
        }
        // Do not wait for the stagger when an attempt has already failed.
        startAttempt(i + 1)
        if failures.count == candidates.count {
            finish(.failure(FetchOperation.mostInformative(Array(failures.values))))
        }
    }

    /// Proves the binding before anything is sent: ALPN, peer address, then the establishment
    /// report (no proxy).
    private func verify(_ i: Int) {
        guard let connection = connections[i] else { return }
        guard let tls = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
            return finish(.failure(.tlsFailed))
        }
        let security = tls.securityProtocolMetadata
        guard sec_protocol_metadata_get_negotiated_tls_protocol_version(security).rawValue >= tls_protocol_version_t.TLSv12.rawValue else {
            return finish(.failure(.tlsFailed))
        }
        if let alpn = FetchOperation.negotiatedProtocol(security), alpn != "http/1.1" {
            return finish(.failure(.unsupportedProtocol))
        }
        guard let remote = connection.currentPath?.remoteEndpoint,
              case .hostPort(let host, let port) = remote, port.rawValue == target.port,
              let observed = IPAddress(networkHost: host),
              AddressPolicy.isBound(observed: observed, vetted: candidates[i]) else {
            return finish(.failure(.bindingUnproven))
        }
        verifying = i
        connection.requestEstablishmentReport(queue: queue) { [weak self] report in
            self?.assumeIsolated { $0.adopt(i, report: report) }
        }
    }

    private func adopt(_ i: Int, report: NWConnection.EstablishmentReport?) {
        guard outcome == nil, verifying == i, let connection = connections[i] else { return }
        verifying = nil
        guard let report, !report.usedProxy, report.proxyEndpoint == nil else {
            return finish(.failure(.bindingUnproven))
        }
        winner = i
        for (j, other) in connections where j != i {
            other.stateUpdateHandler = nil
            other.cancel()
        }
        connections = [i: connection]
        connection.send(content: Data(requestBytes), completion: .contentProcessed { [weak self] error in
            guard let error else { return }
            self?.assumeIsolated { $0.transferFailed(FetchOperation.map(error)) }
        })
        receive()
    }

    // MARK: Receiving

    private func receive() {
        guard outcome == nil, let w = winner, let connection = connections[w] else { return }
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            self?.assumeIsolated { $0.received(data, isComplete: isComplete, error: error) }
        }
    }

    private func received(_ data: Data?, isComplete: Bool, error: NWError?) {
        guard outcome == nil else { return }
        if let data, !data.isEmpty {
            wireBytes += data.count
            var events: [HTTPResponseParser.Event] = []
            var parseError: HTTPParseError?
            do { try parser.feed(data, into: &events) } catch { parseError = error }
            for event in events {
                handle(event)
                if outcome != nil { return }
            }
            if let parseError { return parseFailed(parseError) }
            let maxWire = request.limits.maxHeaderBytes + request.limits.maxCompressedBytes + 64 * 1024
            if wireBytes > maxWire { return head == nil ? finish(.failure(.malformedResponse)) : finishBody(.truncated) }
        }
        if isComplete {
            var events: [HTTPResponseParser.Event] = []
            var parseError: HTTPParseError?
            do { try parser.finish(into: &events) } catch { parseError = error }
            for event in events {
                handle(event)
                if outcome != nil { return }
            }
            return parseFailed(parseError ?? .prematureEOF)
        }
        if let error {
            return head == nil ? finish(.failure(FetchOperation.map(error))) : finishBody(.interrupted)
        }
        receive()
    }

    private func handle(_ event: HTTPResponseParser.Event) {
        switch event {
        case .head(let head): receivedHead(head)
        case .body(let bytes): receivedBody(bytes)
        case .end: bodyEnded()
        }
    }

    private func receivedHead(_ head: HTTPResponseParser.Head) {
        self.head = head
        if request.bodyPolicy == .htmlOnly {
            let redirect = [301, 302, 303, 307, 308].contains(head.status) && head.headers["location"] != nil
            let type = ContentType(head.headers["content-type"])
            if redirect || (type != nil && type?.isHTML == false) { return finishBody(.skipped) }
        }
        guard let coding = ContentCoding.parse(head.headers.values("content-encoding")) else {
            return finish(.failure(.decodingFailed))
        }
        decoder = BodyDecoder(coding: coding, maxOutput: request.limits.maxDecodedBytes)
    }

    private func receivedBody(_ bytes: [UInt8]) {
        guard decoder != nil else { return }
        let room = request.limits.maxCompressedBytes - bodyBytes
        let accepted = bytes.count > room ? Array(bytes.prefix(max(0, room))) : bytes
        bodyBytes += accepted.count
        decoder?.append(accepted)
        if decoder?.capped == true || bytes.count > room { finishBody(.truncated) }
    }

    private func bodyEnded() {
        finishBody(.complete)
    }

    private func parseFailed(_ error: HTTPParseError) {
        if head == nil { finish(.failure(.malformedResponse)) } else { finishBody(.interrupted) }
    }

    private func transferFailed(_ error: FetchError) {
        if head == nil { finish(.failure(error)) } else { finishBody(.interrupted) }
    }

    private func deadlineReached() {
        guard outcome == nil else { return }
        if head == nil { finish(.failure(.timeout)) } else { finishBody(.timedOut) }
    }

    // MARK: Finishing

    /// Ends the response. The content coding is removed here, once the body is known to be complete
    /// (checksums verified) or cut short (whatever decodes is kept).
    private func finishBody(_ ending: HTTPResponse.BodyState) {
        guard let head else { return finish(.failure(.malformedResponse)) }
        var state = ending
        var body = Data()
        if state != .skipped, var decoder {
            do {
                switch try decoder.finish(bodyComplete: state == .complete) {
                case .complete: break
                case .truncated: state = .truncated
                case .partial: if state == .complete { state = .interrupted }
                }
            } catch {
                return finish(.failure(.decodingFailed))
            }
            body = Data(decoder.output)
        }
        let address = winner.map { candidates[$0].description }
        finish(.success(HTTPResponse(status: head.status, reason: head.reason, headers: head.headers, body: body,
                                     bodyState: state, remoteAddress: address)))
    }

    private func finish(_ result: Result<HTTPResponse, FetchError>) {
        guard outcome == nil else { return }
        outcome = result
        for connection in connections.values {
            connection.stateUpdateHandler = nil
            connection.cancel()
        }
        connections.removeAll()
        continuation?.resume(returning: result)
        continuation = nil
    }

    // MARK: Helpers

    nonisolated static func map(_ error: NWError) -> FetchError {
        switch error {
        case .tls: return .tlsFailed
        case .dns: return .nameNotResolved
        case .posix(let code):
            switch code {
            case .ETIMEDOUT: return .timeout
            case .ENETDOWN: return .offline
            case .ECANCELED: return .cancelled
            default: return .connectionFailed
            }
        default: return .connectionFailed
        }
    }

    /// When every attempt failed, report the failure that says most about the server.
    nonisolated static func mostInformative(_ errors: [FetchError]) -> FetchError {
        let order: [FetchError] = [.tlsFailed, .unsupportedProtocol, .bindingUnproven, .connectionFailed, .timeout, .offline]
        return order.first(where: errors.contains) ?? errors.first ?? .connectionFailed
    }

    nonisolated static func negotiatedProtocol(_ metadata: sec_protocol_metadata_t) -> String? {
        if #available(iOS 18.5, macOS 15.5, *) {
            guard let p = sec_protocol_metadata_copy_negotiated_protocol(metadata) else { return nil }
            defer { free(UnsafeMutableRawPointer(mutating: p)) }
            return String(cString: p)
        } else {
            return sec_protocol_metadata_get_negotiated_protocol(metadata).map { String(cString: $0) }
        }
    }
}

extension Duration {
    var dispatchInterval: DispatchTimeInterval {
        let c = components
        return .nanoseconds(Int(c.seconds) * 1_000_000_000 + Int(c.attoseconds / 1_000_000_000))
    }
}
