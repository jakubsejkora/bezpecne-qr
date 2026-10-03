import Foundation

/// The per-type risk score. A line-by-line port of scripts/lib/engine.mjs; both must produce the
/// same score and band for every sample in shared/testdata/samples.json.
public struct Scorer: Sendable {
    let weights: Weights

    public init(weights: Weights) {
        self.weights = weights
    }

    static let scoredEngines: Set<EngineKind> = [.url, .payment, .sms, .phone, .generic]

    public func assess(engine: EngineKind, evidence: [Finding], completeness: Completeness) -> Assessment {
        if !Scorer.scoredEngines.contains(engine) || (engine == .generic && evidence.isEmpty) {
            return Assessment(scored: false, score: nil, band: .info)
        }
        let baseline = (weights.engines[engine.rawValue] ?? weights.engines["generic"])?.baseline ?? -3

        // Group the signals (first occurrence order), dedupe IDs.
        var order: [String] = []
        var byGroup: [String: [(id: String, weight: Double)]] = [:]
        var floors: [(id: String, floor: Int)] = []
        var seen = Set<String>()
        for finding in evidence where !seen.contains(finding.id) {
            seen.insert(finding.id)
            guard let def = weights.signals[finding.id] else { continue }
            if byGroup[def.group] == nil { order.append(def.group) }
            byGroup[def.group, default: []].append((finding.id, def.weight))
            if let floor = def.floor { floors.append((finding.id, floor)) }
        }

        var groups: [ScoreMath.Group] = []
        var sum = 0.0
        for name in order {
            guard let items = byGroup[name], let g = weights.groups[name] else { continue }
            let combined = g.combine == .max ? (items.map(\.weight).max() ?? 0) : items.reduce(0) { $0 + $1.weight }
            let contribution = min(g.cap, combined)
            sum += contribution
            groups.append(.init(group: name, signals: items.map(\.id), combined: Scorer.round2(combined), cap: g.cap,
                                contribution: Scorer.round2(contribution)))
        }

        let logit = baseline + sum
        var raw = 100 / (1 + exp(-logit))
        var math = ScoreMath(baseline: baseline, groups: groups, logit: Scorer.round2(logit), raw: Scorer.round2(raw))

        let weakOnly = !groups.isEmpty && groups.allSatisfy { weights.weakOnlyCap.groups.contains($0.group) }
        if weakOnly, raw > weights.weakOnlyCap.cap {
            raw = weights.weakOnlyCap.cap
            math.weakOnlyCapApplied = weights.weakOnlyCap.cap
        }

        // JavaScript's Math.round rounds .5 up; Swift's .rounded() rounds half away from zero (same for positives).
        var score = Int((raw).rounded(.toNearestOrAwayFromZero))
        let maxFloor = floors.map(\.floor).max() ?? 0
        if maxFloor > score {
            score = maxFloor
            if let f = floors.first(where: { $0.floor == maxFloor }) { math.floorApplied = (f.id, f.floor) }
        }

        var band = weights.bands.first(where: { score >= $0.min && score <= $0.max })?.id ?? .danger
        if (completeness.state == .incomplete || completeness.state == .skipped) && score < 25 { band = .incomplete }
        return Assessment(scored: true, score: score, band: band, math: math)
    }

    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
