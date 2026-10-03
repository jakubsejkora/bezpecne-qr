import BQCore
import Foundation

/// The registry's answer about a domain. Missing values mean unknown — never "old".
public struct RDAPRegistration: Sendable, Hashable {
    /// Registration date as `yyyy-MM-dd` (Europe/Prague day).
    public var registered: String?
    /// A short registry label: "CZ.NIC", "Verisign", "ZDNS" or the RDAP server host.
    public var registry: String?

    public init(registered: String? = nil, registry: String? = nil) {
        self.registered = registered
        self.registry = registry
    }
}

/// The IANA RDAP bootstrap for DNS (RFC 9224), bundled as a snapshot (see README for its date).
public struct RDAPBootstrap: Sendable {
    private let servers: [String: URL]

    public static let bundled: RDAPBootstrap = {
        guard let url = Bundle.module.url(forResource: "rdap-dns", withExtension: "json"),
              let data = try? Data(contentsOf: url), let bootstrap = try? RDAPBootstrap(json: data) else {
            return RDAPBootstrap(servers: [:])
        }
        return bootstrap
    }()

    init(servers: [String: URL]) {
        self.servers = servers
    }

    /// Parses `{"services": [[["tld", …], ["https://…/", …]], …]}`, keeping the first HTTPS URL.
    public init(json: Data) throws {
        struct File: Decodable { var services: [[[String]]] }
        var map: [String: URL] = [:]
        for service in try JSONDecoder().decode(File.self, from: json).services where service.count == 2 {
            guard let base = service[1].first(where: { $0.lowercased().hasPrefix("https://") }),
                  let url = URL(string: base.hasSuffix("/") ? base : base + "/") else { continue }
            for tld in service[0] { map[tld.lowercased()] = url }
        }
        servers = map
    }

    /// The registry's RDAP base URL for a TLD ("cz" → https://rdap.nic.cz/).
    public func server(forTLD tld: String) -> URL? {
        servers[tld.lowercased()]
    }
}

/// Looks up a domain's registration date over RDAP: HTTPS registry servers from the bundled IANA
/// bootstrap only, no redirects (a redirect means unknown), results cached for an hour, concurrent
/// lookups of the same domain coalesced (each caller keeps its own deadline), one request per
/// second per server, and back-off after 429/503.
public actor RDAPClient {
    private let client: any EndpointClient
    private let bootstrap: RDAPBootstrap
    private let rules: RuleSet
    private var cache: [String: (result: RDAPRegistration, expires: ContinuousClock.Instant)] = [:]
    private var inFlight: [String: Task<RDAPRegistration, Never>] = [:]
    private var nextRequest: [String: ContinuousClock.Instant] = [:]
    private var backoffUntil: [String: ContinuousClock.Instant] = [:]

    static let cacheTTL: Duration = .seconds(3600)
    /// The process-wide client: registries rate-limit per IP address, so all lookups share one
    /// request schedule, cache and back-off.
    public static let shared = RDAPClient()

    enum Status: Sendable, Equatable {
        case found, notFound, failed
        case throttled(retryAfter: Int)
    }

    public init(client: any EndpointClient = URLSessionEndpointClient.shared, bootstrap: RDAPBootstrap = .bundled,
                rules: RuleSet = .bundled) {
        self.client = client
        self.bootstrap = bootstrap
        self.rules = rules
    }

    /// - Parameter domain: a registrable domain ("rohlik.cz"), not a hostname.
    public func lookup(_ domain: String, deadline: Deadline) async -> RDAPRegistration {
        var name = domain.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        guard PublicName.isEligible(name, rules: rules), let server = bootstrap.server(forTLD: DomainKit.tld(name)),
              let serverHost = server.host() else { return RDAPRegistration() }
        let label = RDAPClient.registryLabel(tld: DomainKit.tld(name), server: server)
        let unknown = RDAPRegistration(registered: nil, registry: label)

        let now = ContinuousClock.now
        if let cached = cache[name], cached.expires > now { return cached.result }
        if let until = backoffUntil[serverHost], until > now { return unknown }

        let lookup: Task<RDAPRegistration, Never>
        if let running = inFlight[name] {
            lookup = running // coalesced with a lookup already on its way
        } else {
            // Registries rate-limit per client (rdap.nic.cz: 1 request/s); space our requests out.
            let slot = max(now, nextRequest[serverHost] ?? now)
            guard slot < deadline else { return unknown }
            nextRequest[serverHost] = slot + .seconds(1)
            let client = self.client
            // Runs on this actor between awaits; bounded by the starting caller's deadline.
            lookup = Task {
                if slot > .now { try? await Task.sleep(until: slot, clock: .continuous) }
                // The registry may have asked us to back off while this lookup waited for its turn.
                if let until = self.backoffUntil[serverHost], until > .now {
                    self.record(name, serverHost: serverHost, result: unknown, status: .failed)
                    return unknown
                }
                let (result, status) = await RDAPClient.fetch(name, server: server, label: label, client: client, deadline: deadline)
                self.record(name, serverHost: serverHost, result: result, status: status)
                return result
            }
            inFlight[name] = lookup
        }
        // Every caller waits only until its own deadline and stops waiting when it is cancelled;
        // the shared lookup carries on for the others and fills the cache.
        return await waitForValue(of: lookup, until: deadline, fallback: unknown)
    }

    private func record(_ name: String, serverHost: String, result: RDAPRegistration, status: Status) {
        inFlight[name] = nil
        switch status {
        case .found, .notFound:
            cache[name] = (result, .now + RDAPClient.cacheTTL)
            if cache.count > 512 { cache = cache.filter { $0.value.expires > .now } }
        case .throttled(let seconds):
            backoffUntil[serverHost] = .now + .seconds(seconds)
        case .failed:
            break
        }
    }

    static func fetch(_ domain: String, server: URL, label: String, client: any EndpointClient,
                      deadline: Deadline) async -> (RDAPRegistration, Status) {
        let unknown = RDAPRegistration(registered: nil, registry: label)
        guard !deadline.hasPassed, let url = URL(string: "domain/\(domain)", relativeTo: server)?.absoluteURL else { return (unknown, .failed) }
        var request = URLRequest(url: url)
        request.setValue("application/rdap+json, application/json;q=0.9", forHTTPHeaderField: "Accept")
        request.timeoutInterval = max(0.5, deadline.secondsRemaining)

        let get = request
        let response: (Data, HTTPURLResponse)? = await withDeadline(deadline, fallback: nil) {
            try? await client.send(get)
        }
        guard let (data, http) = response else { return (unknown, .failed) }
        // Redirects are not followed (EndpointClient): a redirect means unknown, like any other status.
        switch http.statusCode {
        case 200:
            guard let date = registrationDate(from: data) else { return (unknown, .found) }
            return (RDAPRegistration(registered: date, registry: label), .found)
        case 404:
            return (unknown, .notFound)
        case 429, 503:
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 60
            return (unknown, .throttled(retryAfter: min(max(retryAfter, 1), 300)))
        default:
            return (unknown, .failed)
        }
    }

    /// The `registration` event of an RDAP domain object as a Europe/Prague calendar day.
    static func registrationDate(from data: Data) -> String? {
        struct Domain: Decodable {
            struct Event: Decodable {
                var eventAction: String?
                var eventDate: String?
            }
            var events: [Event]?
        }
        guard let domain = try? JSONDecoder().decode(Domain.self, from: data),
              let raw = domain.events?.first(where: { $0.eventAction?.lowercased() == "registration" })?.eventDate,
              let date = parseDate(raw) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return nil }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// RFC 3339 with or without fractional seconds; a bare date is read as UTC midnight.
    static func parseDate(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if let d = try? Date(s, strategy: .iso8601) { return d }
        if let d = try? Date(s, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) { return d }
        if s.count == 10, let d = try? Date(s + "T00:00:00Z", strategy: .iso8601) { return d }
        return nil
    }

    /// A short label for the registry behind a TLD.
    static func registryLabel(tld: String, server: URL) -> String {
        switch tld.lowercased() {
        case "cz": return "CZ.NIC"
        case "com", "net", "cc", "tv", "name": return "Verisign"
        case "top": return "ZDNS"
        default: return server.host() ?? server.absoluteString
        }
    }
}
