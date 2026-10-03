import BQCore
import Foundation

/// Asks Quad9's protective DNS whether a hostname is on its threat lists: one RFC 8484 DoH POST
/// (`application/dns-message`, type A) to https://dns.quad9.net/dns-query. Only public hostnames
/// are ever sent.
///
/// Quad9 signals a security block as NXDOMAIN with an **empty** authority section (and an Extended
/// DNS Error "Blocked"/"Filtered"); a name that simply does not exist is NXDOMAIN **with** the
/// zone's SOA, which is not a block. Every failure is `.unknown`.
public actor Quad9Client {
    public static let endpoint = URL(string: "https://dns.quad9.net/dns-query")!
    /// The process-wide client (one cache and back-off for the whole app).
    public static let shared = Quad9Client()

    private let client: any EndpointClient
    private let rules: RuleSet
    private var cache: [String: (verdict: DomainFacts.Quad9, expires: ContinuousClock.Instant)] = [:]
    private var backoffUntil: ContinuousClock.Instant?

    public init(client: any EndpointClient = URLSessionEndpointClient.shared, rules: RuleSet = .bundled) {
        self.client = client
        self.rules = rules
    }

    public func check(_ host: String, deadline: Deadline) async -> DomainFacts.Quad9 {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        guard PublicName.isEligible(name, rules: rules) else { return .unknown }
        let now = ContinuousClock.now
        if let cached = cache[name], cached.expires > now { return cached.verdict }
        if let until = backoffUntil, until > now { return .unknown }

        let outcome = await Quad9Client.query(name, client: client, deadline: deadline)
        switch outcome {
        case .answer(let verdict, let ttl):
            cache[name] = (verdict, .now + .seconds(ttl))
            if cache.count > 512 { cache = cache.filter { $0.value.expires > .now } }
            return verdict
        case .failed(let backoff):
            if backoff { backoffUntil = .now + .seconds(30) }
            return .unknown
        }
    }

    enum Outcome: Sendable, Equatable {
        /// A usable answer and how long to keep it (seconds).
        case answer(DomainFacts.Quad9, ttl: Int)
        /// No usable answer; `backoff` when the service itself is struggling (429/5xx/network).
        case failed(backoff: Bool)
    }

    static func query(_ name: String, client: any EndpointClient, deadline: Deadline) async -> Outcome {
        guard let message = try? DNSMessage.query(name: name, type: DNSMessage.typeA) else { return .failed(backoff: false) }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        request.httpBody = Data(message)
        request.timeoutInterval = max(0.5, deadline.secondsRemaining)

        let post = request
        let response: (Data, HTTPURLResponse)? = await withDeadline(deadline, fallback: nil) {
            try? await client.send(post)
        }
        guard let (data, http) = response else { return .failed(backoff: !deadline.hasPassed) }
        guard http.statusCode == 200 else { return .failed(backoff: http.statusCode == 429 || http.statusCode >= 500) }
        guard let parsed = try? DNSMessage.parse(Array(data)) else { return .failed(backoff: false) }
        return interpret(parsed, name: name)
    }

    /// Maps a DNS answer to Quad9's verdict.
    static func interpret(_ m: DNSMessage, name: String) -> Outcome {
        guard m.isResponse, m.id == 0, m.opcode == 0, m.questions.count == 1,
              m.questions[0].name.lowercased() == name.lowercased(),
              m.questions[0].type == DNSMessage.typeA, m.questions[0].qclass == DNSMessage.classIN else {
            return .failed(backoff: false)
        }
        let ede = Set(m.extendedErrors.map(\.infoCode))
        // EDE 16 "Censored" marks a legal (court-ordered) block, which says nothing about threats.
        if ede.contains(16) { return .answer(.unknown, ttl: 300) }
        // EDE 15 "Blocked" / 17 "Filtered": the resolver's own policy (threat intelligence).
        if ede.contains(15) || ede.contains(17) { return .answer(.blocked, ttl: 300) }
        switch m.rcode {
        case DNSMessage.rcodeNoError:
            let ttl = m.answers.map { Int($0.ttl) }.min() ?? 300
            return .answer(.ok, ttl: min(max(ttl, 60), 3600))
        case DNSMessage.rcodeNXDomain:
            if m.answers.isEmpty && m.authorities.isEmpty { return .answer(.blocked, ttl: 300) }
            return .answer(.ok, ttl: 300) // nonexistent name (SOA present): not a block
        default:
            return .failed(backoff: false)
        }
    }
}
