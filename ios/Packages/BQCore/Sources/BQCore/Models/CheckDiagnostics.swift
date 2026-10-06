import Foundation

/// Bounded, inert diagnostic facts. No page text, headers, URL paths, queries or finding parameters.
public struct CheckDiagnostics: Codable, Hashable, Sendable {
    public struct Preferences: Codable, Hashable, Sendable {
        public var pageFetch: Bool
        public var domainChecks: Bool
        public var offline: Bool
    }
    public struct HopSummary: Codable, Hashable, Sendable {
        public var host: String?
        public var status: Int?
        public var kind: String?
        public var stopped: String?
    }
    public var version = 1
    public var completeness: Completeness
    public var destinationState: DestinationResolution.State?
    public var destinationReason: String?
    public var preferences: Preferences
    public var stageTimingsMS: [String: Int]
    public var transportError: String?
    public var httpStatus: Int?
    public var hops: [HopSummary]
    public var findingIDs: [String]

    public init(_ analysis: Analysis, options: AnalysisOptions, timings: [String: Int] = [:]) {
        completeness = analysis.completeness
        destinationState = analysis.linkResolution?.state
        destinationReason = analysis.linkResolution?.reason
        preferences = Preferences(pageFetch: options.pageFetch, domainChecks: options.domainChecks, offline: options.offline)
        stageTimingsMS = timings
        transportError = analysis.inspection?.transportError
        httpStatus = analysis.inspection?.chain.last(where: { $0.status != nil })?.status
        hops = (analysis.inspection?.chain ?? []).prefix(20).map { hop in
            HopSummary(host: Self.publicHost(hop.url), status: hop.status, kind: hop.kind?.rawValue, stopped: hop.stopped?.rawValue)
        }
        findingIDs = Array(Set((analysis.evidence + analysis.consequences + analysis.checks).map(\.id))).sorted()
    }

    public static func publicHost(_ raw: String) -> String? {
        guard let url = URL(string: raw), url.user == nil, url.password == nil else { return nil }
        switch LinkGate(rules: .bundled).evaluate(url, hop: 0) {
        case .fetch, .upgrade, .billingStop: return url.asciiHost
        default: return nil
        }
    }

    /// Validate untrusted inbox data, including unknown future diagnostic shapes.
    public var isValid: Bool {
        func identifier(_ value: String?) -> Bool {
            guard let value else { return true }
            return value.utf8.count <= 100 && value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-").contains($0) }
        }
        return version == 1 && hops.count <= 20 && findingIDs.count <= 200 && stageTimingsMS.count <= 12
            && identifier(completeness.reason) && identifier(destinationReason) && identifier(transportError)
            && findingIDs.allSatisfy { identifier($0) }
            && stageTimingsMS.allSatisfy { identifier($0.key) && (0...600_000).contains($0.value) }
            && hops.allSatisfy { hop in
                identifier(hop.kind) && identifier(hop.stopped)
                    && (hop.status == nil || (100...599).contains(hop.status!))
                    && (hop.host == nil || Self.publicHost("https://" + hop.host!) == hop.host)
            }
    }
}

public enum HistoryPrivacy {
    /// Rechecked at export time; being locally unscored does not imply a payload is shareable.
    public static func isProtected(_ analysis: Analysis) -> Bool {
        if analysis.isSensitive { return true }
        var urls: [URL] = analysis.linkTarget.map { [$0] } ?? []
        if case .text(let text) = analysis.content {
            urls += text.entities.filter { $0.kind == "url" }.compactMap { URL(string: $0.value.hasPrefix("http") ? $0.value : "https://" + $0.value) }
        }
        if let url = URL(string: analysis.code.text), url.host != nil { urls.append(url) }
        // Contact/event/payment fields may themselves contain protected links.
        if let pattern = try? NSRegularExpression(pattern: #"(?i)(?:https?://|www\.)[^\s<>\"']+"#) {
            let raw = analysis.code.text
            for match in pattern.matches(in: raw, range: NSRange(raw.startIndex..., in: raw)) {
                if let range = Range(match.range, in: raw) {
                    let value = String(raw[range]).trimmingCharacters(in: CharacterSet(charactersIn: ".,;:!?)"))
                    if let url = URL(string: value.lowercased().hasPrefix("www.") ? "https://" + value : value) { urls.append(url) }
                }
            }
        }
        return urls.contains { url in
            if url.user != nil || url.password != nil { return true }
            if case .skip = LinkGate(rules: .bundled).evaluate(url, hop: 0) { return true }
            return false
        }
    }
}
