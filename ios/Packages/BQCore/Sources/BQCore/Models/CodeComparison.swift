import Foundation

/// A relative finding, never a claim that a particular parking operator or location is correct.
public enum CodeComparison {
    public static func recommendation(_ candidates: [Analysis], checking: Set<Int> = []) -> Int? {
        guard candidates.count > 1, checking.isEmpty,
              candidates.allSatisfy({ $0.type == .url && !$0.isSensitive && !$0.invalid
                  && $0.completeness.state == .complete && $0.linkResolution?.state == .resolved
                  && [.safe, .caution, .danger].contains($0.band) }) else { return nil }
        let safe = candidates.indices.filter { candidates[$0].band == .safe }
        guard safe.count == 1, let index = safe.first,
              candidates[index].consequences.allSatisfy({ RuleSet.bundled.texts.consequence($0, .en).severity == .info }) else { return nil }
        return index
    }
}
