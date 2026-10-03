import BQCore
import Dispatch
import Foundation
import Network
import Synchronization

/// A NAT64 translation prefix (RFC 6052). An IPv6 address inside it stands for the IPv4 address
/// embedded at the positions its length defines, and the translator connects to that IPv4 address.
struct NAT64Prefix: Hashable, Sendable, CustomStringConvertible {
    /// 16 bytes; only the first `length / 8` are significant (the rest are zero).
    let bytes: [UInt8]
    /// 32, 40, 48, 56, 64 or 96.
    let length: Int

    /// Positions of the embedded IPv4 bytes for each prefix length (RFC 6052 §2.2). Byte 8 (bits
    /// 64–71) is never used and must be zero.
    static let layouts: [Int: [Int]] = [
        32: [4, 5, 6, 7], 40: [5, 6, 7, 9], 48: [6, 7, 9, 10], 56: [7, 9, 10, 11], 64: [9, 10, 11, 12], 96: [12, 13, 14, 15],
    ]

    var description: String {
        "\(BQCore.IPAddress(v6: bytes))/\(length)"
    }

    func contains(_ address: BQCore.IPAddress) -> Bool {
        address.family == .v6 && address.bytes.prefix(length / 8).elementsEqual(bytes.prefix(length / 8))
    }

    /// The IPv4 address `address` stands for, if it lies inside this prefix.
    func embeddedV4(_ address: BQCore.IPAddress) -> BQCore.IPAddress? {
        guard contains(address), let positions = NAT64Prefix.layouts[length] else { return nil }
        return BQCore.IPAddress(v4: positions.map { address.bytes[$0] })
    }

    /// RFC 7050 §3: the prefixes that could have synthesized `address` from one of the well-known
    /// IPv4 addresses of ipv4only.arpa (192.0.0.170, 192.0.0.171). Every matching layout is kept;
    /// an extra candidate only makes vetting stricter.
    static func discovered(in address: BQCore.IPAddress) -> [NAT64Prefix] {
        guard address.family == .v6 else { return [] }
        let wellKnown: [[UInt8]] = [[192, 0, 0, 170], [192, 0, 0, 171]]
        var found: [NAT64Prefix] = []
        for (length, positions) in layouts.sorted(by: { $0.key < $1.key }) {
            guard wellKnown.contains(positions.map { address.bytes[$0] }) else { continue }
            if length < 96, address.bytes[8] != 0 { continue }
            let significant = Array(address.bytes.prefix(length / 8))
            found.append(NAT64Prefix(bytes: significant + [UInt8](repeating: 0, count: 16 - significant.count), length: length))
        }
        return found
    }
}

/// What the current network does to IPv6 addresses, as far as vetting resolver answers goes.
struct TranslationContext: Sendable, Equatable {
    /// Discovered NAT64 prefixes. (The well-known 64:ff9b::/96 is also handled by `IPAddress.isPublic`.)
    var prefixes: [NAT64Prefix]
    /// IPv6 addresses outside the prefixes are genuine and can be vetted with `isPublic`. False when
    /// discovery failed, or on an IPv6-only path without a discovered prefix: a translator with an
    /// unknown network-specific prefix may be in use there.
    var trustsIPv6: Bool

    /// Nothing known about translation: IPv6 answers are not trusted.
    static let unknown = TranslationContext(prefixes: [], trustsIPv6: false)
}

/// A snapshot of the system's current network path.
struct PathSnapshot: Sendable, Equatable {
    /// Changes when the network changes (interfaces, gateways, address families).
    var signature: String
    /// The path has IPv6 but no IPv4.
    var ipv6Only: Bool
    /// Not `.unsatisfied` (a path that requires a connection, such as VPN on demand, counts).
    var usable: Bool
}

protocol NetworkPathProviding: Sendable {
    func current() async -> PathSnapshot
}

/// The default network path from one long-lived `NWPathMonitor` (observes only; sends nothing).
final class SystemPathProvider: NetworkPathProviding {
    static let shared = SystemPathProvider()

    private let monitor = NWPathMonitor()
    private let state = Mutex<(latest: PathSnapshot?, waiters: [OneShot<PathSnapshot>])>((nil, []))
    private let queue = DispatchQueue(label: "cz.bezpecneqr.path")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.update(SystemPathProvider.snapshot(path)) }
        monitor.start(queue: queue)
    }

    func current() async -> PathSnapshot {
        let once = OneShot<PathSnapshot>()
        let latest: PathSnapshot? = state.withLock { s in
            if s.latest == nil { s.waiters.append(once) }
            return s.latest
        }
        if let latest { return latest }
        // The first update arrives within milliseconds of starting; don't wait long for it.
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) {
            once.resume(PathSnapshot(signature: "unknown", ipv6Only: false, usable: true))
        }
        return await withCheckedContinuation { once.install($0) }
    }

    private func update(_ snapshot: PathSnapshot) {
        let waiters = state.withLock { s in
            s.latest = snapshot
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.resume(snapshot) }
    }

    static func snapshot(_ path: NWPath) -> PathSnapshot {
        let interfaces = path.availableInterfaces.map { "\($0.name):\($0.type)" }.joined(separator: ",")
        let gateways = path.gateways.map { "\($0)" }.joined(separator: ",")
        return PathSnapshot(
            signature: "\(path.status)|v4=\(path.supportsIPv4)|v6=\(path.supportsIPv6)|\(interfaces)|\(gateways)",
            ipv6Only: path.supportsIPv6 && !path.supportsIPv4,
            usable: path.status != .unsatisfied
        )
    }
}

/// Discovers the NAT64 prefixes of the current network (RFC 7050: the AAAA records the resolver
/// synthesizes for ipv4only.arpa) and caches them per network path.
actor TranslationPrefixes {
    static let shared = TranslationPrefixes()

    private let resolver: any HostResolver
    private let paths: any NetworkPathProviding
    private var cached: (signature: String, context: TranslationContext, expires: ContinuousClock.Instant)?
    private var running: (signature: String, task: Task<TranslationContext, Never>)?

    static let discoveryTimeout: Duration = .seconds(2)
    static let successTTL: Duration = .seconds(600)
    static let failureTTL: Duration = .seconds(30)

    init(resolver: any HostResolver = SystemResolver(), paths: any NetworkPathProviding = SystemPathProvider.shared) {
        self.resolver = resolver
        self.paths = paths
    }

    /// The context for the current path. When discovery is still running at `deadline` (or the
    /// caller is cancelled), IPv6 answers are not trusted.
    func context(deadline: Deadline) async -> TranslationContext {
        let path = await paths.current()
        if let cached, cached.signature == path.signature, cached.expires > .now { return cached.context }
        let task: Task<TranslationContext, Never>
        if let running, running.signature == path.signature {
            task = running.task
        } else {
            let resolver = self.resolver
            task = Task {
                let (context, succeeded) = await TranslationPrefixes.discover(resolver: resolver, ipv6Only: path.ipv6Only)
                self.store(context, signature: path.signature, ttl: succeeded ? TranslationPrefixes.successTTL : TranslationPrefixes.failureTTL)
                return context
            }
            running = (path.signature, task)
        }
        return await waitForValue(of: task, until: deadline, fallback: .unknown)
    }

    private func store(_ context: TranslationContext, signature: String, ttl: Duration) {
        cached = (signature, context, .now + ttl)
        if running?.signature == signature { running = nil }
    }

    /// Resolves ipv4only.arpa. Its A records are 192.0.0.170/171; AAAA records exist only when a
    /// DNS64 synthesized them, and they reveal the prefix.
    static func discover(resolver: any HostResolver, ipv6Only: Bool) async -> (TranslationContext, succeeded: Bool) {
        let addresses: [BQCore.IPAddress]
        do {
            addresses = try await resolver.resolve("ipv4only.arpa", deadline: .now + discoveryTimeout)
        } catch {
            return (.unknown, false)
        }
        var prefixes: [NAT64Prefix] = []
        for prefix in addresses.flatMap(NAT64Prefix.discovered(in:)) where !prefixes.contains(prefix) { prefixes.append(prefix) }
        return (TranslationContext(prefixes: prefixes, trustsIPv6: !prefixes.isEmpty || !ipv6Only), true)
    }
}
