import Dispatch
import Foundation
import Network
import Synchronization

/// Whether the device can reach any network at all.
public protocol NetworkReachability: Sendable {
    func isOffline() async -> Bool
}

/// The system's current network path (one shared `NWPathMonitor`): offline only when it is
/// unsatisfied. No traffic is sent.
public struct SystemReachability: NetworkReachability {
    public init() {}

    public func isOffline() async -> Bool {
        !(await SystemPathProvider.shared.isUsable())
    }
}

/// The default network path from one long-lived `NWPathMonitor` (observes only; sends nothing).
final class SystemPathProvider: Sendable {
    static let shared = SystemPathProvider()

    private let monitor = NWPathMonitor()
    /// Whether the latest path is usable (not `.unsatisfied`; a path that requires a connection,
    /// such as VPN on demand, counts), and callers waiting for the first update.
    private let state = Mutex<(usable: Bool?, waiters: [OneShot<Bool>])>((nil, []))
    private let queue = DispatchQueue(label: "cz.bezpecneqr.path")

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in self?.update(path.status != .unsatisfied) }
        monitor.start(queue: queue)
    }

    /// Whether the current path is usable. The first update arrives within milliseconds of
    /// starting; if it doesn't, the network is assumed usable and the fetch reports what it finds.
    func isUsable() async -> Bool {
        let once = OneShot<Bool>()
        let known: Bool? = state.withLock { s in
            if s.usable == nil { s.waiters.append(once) }
            return s.usable
        }
        if let known { return known }
        queue.asyncAfter(deadline: .now() + .milliseconds(500)) { once.resume(true) }
        return await withCheckedContinuation { once.install($0) }
    }

    private func update(_ usable: Bool) {
        let waiters = state.withLock { s in
            s.usable = usable
            defer { s.waiters = [] }
            return s.waiters
        }
        for waiter in waiters { waiter.resume(usable) }
    }
}
