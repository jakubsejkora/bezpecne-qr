import BQCore
import Dispatch
import Foundation

/// Resolves a hostname to every A and AAAA address. `SafeFetcher` vets all of them before it
/// connects anywhere.
public protocol HostResolver: Sendable {
    func resolve(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress]
}

/// The system resolver (`getaddrinfo`), so on-device DNS settings, VPN and DNS64 apply as they do
/// for every other app. Never Quad9: the fetch path and the public checks stay independent.
public struct SystemResolver: HostResolver {
    /// `getaddrinfo` blocks and cannot be cancelled; it runs here and its late result is dropped.
    private static let queue = DispatchQueue(label: "cz.bezpecneqr.resolver", qos: .userInitiated, attributes: .concurrent)

    public init() {}

    public func resolve(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress] {
        if deadline.hasPassed { throw .timeout }
        let once = OneShot<Result<[IPAddress], FetchError>>()
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                once.install(continuation)
                SystemResolver.queue.asyncAfter(deadline: deadline.dispatchTime) { once.resume(.failure(.timeout)) }
                SystemResolver.queue.async { once.resume(SystemResolver.lookup(host)) }
            }
        } onCancel: {
            once.resume(.failure(.cancelled))
        }
        return try result.get()
    }

    /// Every TCP address of `host`. No `AI_ADDRCONFIG`: records of both families are returned even
    /// when the current network lacks one, so a rebinding record of either family is still seen.
    static func lookup(_ host: String) -> Result<[IPAddress], FetchError> {
        var hints = addrinfo()
        hints.ai_family = AF_UNSPEC
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP
        hints.ai_flags = 0
        var list: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &list)
        guard status == 0 else { return .failure(failure(status: status)) }
        guard let first = list else { return .failure(.nameNotResolved) }
        defer { freeaddrinfo(first) }

        var addresses: [IPAddress] = []
        var node: UnsafeMutablePointer<addrinfo>? = first
        while let entry = node {
            if let sa = entry.pointee.ai_addr {
                switch entry.pointee.ai_family {
                case AF_INET:
                    let bytes = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin_addr) { Array($0) } }
                    addresses.append(IPAddress(v4: bytes))
                case AF_INET6:
                    let bytes = sa.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { withUnsafeBytes(of: $0.pointee.sin6_addr) { Array($0) } }
                    addresses.append(IPAddress(v6: bytes))
                default:
                    break
                }
            }
            node = entry.pointee.ai_next
        }
        var seen = Set<IPAddress>()
        let unique = addresses.filter { seen.insert($0).inserted }
        return unique.isEmpty ? .failure(.nameNotResolved) : .success(unique)
    }
}

/// Resolves names with the system resolver and applies the address rules. `SafeFetcher` uses it
/// before every connection, and `LinkInspector` before a name may leave the device for the public
/// domain checks (a split-DNS name that points into a private network must not).
public protocol HostVetting: Sendable {
    /// The vetted IPv4 addresses `host` (a hostname or an IP literal) may be contacted at.
    func vet(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress]
}

/// `HostVetting` with the system resolver.
public struct AddressVetter: HostVetting {
    let resolver: any HostResolver

    public init(resolver: any HostResolver = SystemResolver()) {
        self.resolver = resolver
    }

    public func vet(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress] {
        // Brackets belong only around an IPv6 literal ("https://[o2platba.cz]/" parses in Foundation).
        if host.hasPrefix("[") || host.hasSuffix("]") {
            guard host.hasPrefix("["), host.hasSuffix("]"), IPAddress(String(host.dropFirst().dropLast()))?.family == .v6 else {
                throw .invalidRequest
            }
        }
        if deadline.hasPassed { throw .timeout }
        let addresses: [IPAddress]
        if let literal = IPAddress(host) {
            addresses = [literal]
        } else {
            addresses = try await resolver.resolve(host, deadline: deadline)
        }
        return try AddressPolicy.vet(addresses)
    }
}

extension SystemResolver {
    /// Only "no such name / no address" means the name doesn't exist; anything else (EAI_AGAIN,
    /// EAI_FAIL, EAI_SYSTEM…) says nothing about it.
    static func failure(status: Int32) -> FetchError {
        status == EAI_NONAME || status == EAI_NODATA ? .nameNotResolved : .resolverFailed
    }
}

/// The address rules for every connection `SafeFetcher` makes.
enum AddressPolicy {
    /// Every answer must be public: one non-public answer, of either family, refuses the whole name
    /// (DNS rebinding / SSRF), whichever address would have been picked. Connections then go only to
    /// the IPv4 answers. An IPv6 answer can't be shown to be native: any NAT64 translator on the
    /// network — with a prefix nothing tells us about (RFC 7050 §5.1) — may turn it into a private
    /// IPv4 destination. On NAT64 networks the system synthesizes IPv6 for a vetted IPv4 address
    /// itself. A name with IPv6 answers only is `unverifiableAddress`.
    static func vet(_ addresses: [IPAddress]) throws(FetchError) -> [IPAddress] {
        guard !addresses.isEmpty else { throw .nameNotResolved }
        guard addresses.allSatisfy(\.isPublic) else { throw .nonPublicAddress }
        let v4 = addresses.filter { $0.family == .v4 }
        guard !v4.isEmpty else { throw .unverifiableAddress }
        return v4
    }

    /// At most two vetted addresses to race, in the resolver's order.
    static func candidates(_ vetted: [IPAddress]) -> [IPAddress] {
        Array(vetted.prefix(2))
    }

    /// Positions of the embedded IPv4 bytes for each NAT64 prefix length (RFC 6052 §2.2). Byte 8
    /// (bits 64–71) is never used and must be zero for prefixes shorter than /96.
    static let nat64Layouts: [Int: [Int]] = [
        32: [4, 5, 6, 7], 40: [5, 6, 7, 9], 48: [6, 7, 9, 10], 56: [7, 9, 10, 11], 64: [9, 10, 11, 12], 96: [12, 13, 14, 15],
    ]

    /// Whether the connection's remote address is the vetted one. When the system reaches a vetted
    /// IPv4 address through NAT64, the synthesized address (RFC 6052, any prefix length) embeds
    /// exactly that IPv4 address and is accepted; the prefix is the system's own.
    static func isBound(observed: IPAddress, vetted: IPAddress) -> Bool {
        if observed == vetted { return true }
        guard vetted.family == .v4, observed.family == .v6 else { return false }
        return nat64Layouts.contains { length, positions in
            (length == 96 || observed.bytes[8] == 0) && positions.map({ observed.bytes[$0] }) == vetted.bytes
        }
    }
}
