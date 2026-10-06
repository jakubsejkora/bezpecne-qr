import Foundation

/// Observations, never a guarantee about what a browser will see later.
public struct DestinationResolution: Sendable, Hashable, Codable {
    public enum State: String, Sendable, Codable { case resolved, unresolved, appHandoff }
    public var state: State
    public var scannedURL: String
    /// Only a URL for which an HTTP response was received; never an unvisited Location.
    public var lastObserved: Endpoint?
    public var resolved: Endpoint?
    public var reason: String?
    /// False when fragments, app handoffs or an incomplete walk require the original route.
    public var allowsDirectOpen: Bool

    public init(state: State, scannedURL: String, lastObserved: Endpoint? = nil,
                resolved: Endpoint? = nil, reason: String? = nil, allowsDirectOpen: Bool = false) {
        self.state = state; self.scannedURL = scannedURL; self.lastObserved = lastObserved
        self.resolved = resolved; self.reason = reason; self.allowsDirectOpen = allowsDirectOpen
    }
}

extension Inspection {
    /// Older corpus/history data has no resolution metadata. It can describe its observations,
    /// but cannot opt into direct opening without the inspector's fragment information.
    public func resolution(scannedURL: String, fallbackCompleteness: Completeness) -> DestinationResolution {
        if let destination { return destination }
        let complete = completeness ?? fallbackCompleteness
        let last = chain.last { $0.status != nil }
        let observed = final ?? last.flatMap { hop -> Endpoint? in
            guard let url = URL(string: hop.url), let host = url.asciiHost else { return nil }
            return Endpoint(url: hop.url, host: host, registrable: DomainKit.registrable(host))
        }
        let resolved = complete.state == .complete ? final : nil
        let handoff = chain.last.flatMap { URL(string: $0.url)?.scheme?.lowercased() }
            .map { Analyzer.storeSchemes.contains($0) } == true
        return DestinationResolution(state: resolved != nil ? .resolved : (handoff ? .appHandoff : .unresolved),
                                     scannedURL: scannedURL, lastObserved: observed, resolved: resolved,
                                     reason: complete.reason)
    }
}

extension Analysis {
    public var linkResolution: DestinationResolution? {
        guard case .link(let info) = content else { return nil }
        return inspection?.resolution(scannedURL: info.url, fallbackCompleteness: completeness)
            ?? DestinationResolution(state: .unresolved, scannedURL: info.url, reason: completeness.reason)
    }

    public var resolvedHost: String? {
        guard !isSensitive, let resolution = linkResolution, resolution.state == .resolved else { return nil }
        return resolution.resolved?.host
    }

    public var opensOriginalLink: Bool {
        guard type == .url, let resolution = linkResolution, let openURL else { return false }
        return resolution.state != .resolved || resolution.resolved?.url != openURL.absoluteString
    }
}
