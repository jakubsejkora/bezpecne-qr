import Foundation
import Network

/// Whether the device can reach any network at all.
public protocol NetworkReachability: Sendable {
    func isOffline() async -> Bool
}

/// The system's current network path (one shared `NWPathMonitor`): offline only when it is
/// unsatisfied. No traffic is sent.
public struct SystemReachability: NetworkReachability {
    public init() {}

    public func isOffline() async -> Bool {
        !(await SystemPathProvider.shared.current().usable)
    }
}
