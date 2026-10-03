import BQCore
import Foundation

/// The public domain checks used by `LinkInspector`. Only the domain name is sent.
public protocol DomainChecking: Sendable {
    /// Quad9's verdict for a hostname.
    func quad9(_ host: String, deadline: Deadline) async -> DomainFacts.Quad9
    /// Registration facts for a registrable domain.
    func registration(_ domain: String, deadline: Deadline) async -> RDAPRegistration
}

/// Quad9 DoH plus RDAP. By default both are the process-wide clients, so caches, back-off and the
/// per-registry request spacing hold however many inspectors exist (registries limit per IP).
public struct DomainChecker: DomainChecking {
    public let quad9Client: Quad9Client
    public let rdapClient: RDAPClient

    public init(quad9Client: Quad9Client = .shared, rdapClient: RDAPClient = .shared) {
        self.quad9Client = quad9Client
        self.rdapClient = rdapClient
    }

    public func quad9(_ host: String, deadline: Deadline) async -> DomainFacts.Quad9 {
        await quad9Client.check(host, deadline: deadline)
    }

    public func registration(_ domain: String, deadline: Deadline) async -> RDAPRegistration {
        await rdapClient.lookup(domain, deadline: deadline)
    }
}
