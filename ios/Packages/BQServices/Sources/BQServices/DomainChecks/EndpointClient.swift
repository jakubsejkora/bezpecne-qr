import BQCore
import Foundation
import Security

/// HTTPS requests to our own fixed endpoints (Quad9 DoH, RDAP registries). Only the domain name
/// travels; tests inject fakes.
public protocol EndpointClient: Sendable {
    /// Sends `request` (HTTPS only). Redirects are never followed: a redirect comes back as the
    /// response. Bodies over the client's byte budget fail instead of being buffered.
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// URLSession with an ephemeral configuration: no cookies, no cache, no stored credentials, TLS ≥
/// 1.2, never waiting for connectivity, no redirects. Server trust is evaluated by us, like in
/// `SafeFetcher` (no issuer or revocation downloads). The body is streamed and the request is
/// cancelled as soon as it exceeds the budget.
public final class URLSessionEndpointClient: EndpointClient {
    public static let shared = URLSessionEndpointClient()

    private let session: URLSession
    /// DNS messages and RDAP records are small; anything larger is refused.
    private let maxResponseBytes: Int

    public convenience init(maxResponseBytes: Int = 256 * 1024) {
        self.init(configuration: .ephemeral, maxResponseBytes: maxResponseBytes)
    }

    /// `configuration` is the base (tests add a mock `URLProtocol`); our settings are applied on top.
    init(configuration base: URLSessionConfiguration, maxResponseBytes: Int) {
        let configuration = base
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.waitsForConnectivity = false
        configuration.tlsMinimumSupportedProtocolVersion = .TLSv12
        configuration.timeoutIntervalForRequest = 8
        configuration.timeoutIntervalForResource = 8
        configuration.httpMaximumConnectionsPerHost = 2
        // The policy is the session delegate too, so session-level challenges reach it as well.
        session = URLSession(configuration: configuration, delegate: EndpointTaskPolicy.shared, delegateQueue: nil)
        self.maxResponseBytes = maxResponseBytes
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        var request = request
        request.httpShouldHandleCookies = false
        let (bytes, response) = try await session.bytes(for: request, delegate: EndpointTaskPolicy.shared)
        let task = bytes.task
        guard let http = response as? HTTPURLResponse else {
            task.cancel()
            throw URLError(.badServerResponse)
        }
        if http.expectedContentLength > Int64(maxResponseBytes) {
            task.cancel()
            throw URLError(.dataLengthExceedsMaximum)
        }
        let limit = maxResponseBytes
        return try await withTaskCancellationHandler {
            var data = Data()
            data.reserveCapacity(Int(min(max(http.expectedContentLength, 0), Int64(limit))))
            for try await byte in bytes {
                guard data.count < limit else {
                    task.cancel()
                    throw URLError(.dataLengthExceedsMaximum)
                }
                data.append(byte)
            }
            return (data, http)
        } onCancel: {
            task.cancel()
        }
    }
}

/// Never follows a redirect (a hostile registry could point anywhere, including private or
/// billing hosts) and never answers authentication challenges. Server trust is evaluated here with
/// `TrustEvaluator`: the hostname SSL policy against the system anchors, with issuer downloads and
/// revocation fetches off — the default evaluation could fetch a missing issuer from any URL the
/// peer's certificate names, over cleartext HTTP.
final class EndpointTaskPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    static let shared = EndpointTaskPolicy()

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        nil
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        EndpointTaskPolicy.answer(challenge)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge) async
        -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        EndpointTaskPolicy.answer(challenge)
    }

    static func answer(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else { return (.rejectProtectionSpace, nil) }
        return disposition(for: space.serverTrust, host: space.host)
    }

    /// Accepts the server only when our evaluation passes; anything else cancels the request.
    static func disposition(for trust: SecTrust?, host: String) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard let trust, TrustEvaluator.evaluate(trust, host: host) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }
}

/// Names that may be sent to Quad9 or a registry: public DNS names only — never IP literals,
/// single labels, local or special-use names (the same rules as the link gate).
enum PublicName {
    static func isEligible(_ host: String, rules: RuleSet = .bundled) -> Bool {
        var h = host.lowercased()
        if h.hasSuffix(".") { h.removeLast() }
        guard IPAddress(h) == nil, FetchTarget.isValidHostname(h), DomainKit.labels(h).count >= 2,
              let url = URL(string: "https://\(h)/") else { return false }
        if case .refuse = LinkGate(rules: rules).evaluate(url, hop: 0) { return false }
        return true
    }
}
