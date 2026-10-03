import Foundation

/// Rendered, localized texts for findings (from signals.json).
public struct EvidenceTexts: Sendable, Hashable {
    public var title: String
    public var observation: String
    public var implication: String
    public var action: String
}

public struct ConsequenceTexts: Sendable, Hashable {
    public var title: String
    public var text: String
    public var severity: Severity
}

extension SignalTexts {
    /// Fills `{placeholders}` from finding arguments.
    public static func fill(_ template: String, _ args: [String: ArgValue], _ language: Language) -> String {
        var out = ""
        var i = template.startIndex
        while i < template.endIndex {
            let c = template[i]
            if c == "{", let close = template[i...].firstIndex(of: "}") {
                let key = String(template[template.index(after: i)..<close])
                if !key.isEmpty, key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) {
                    out += args[key]?.resolve(language) ?? "{\(key)}"
                    i = template.index(after: close)
                    continue
                }
            }
            out.append(c)
            i = template.index(after: i)
        }
        return out
    }

    public func evidence(_ finding: Finding, _ language: Language) -> EvidenceTexts {
        guard let entry = evidence[finding.id], let t = entry[language.rawValue] ?? entry["cs"] else {
            return EvidenceTexts(title: finding.id, observation: "", implication: "", action: "")
        }
        let a = finding.args
        return EvidenceTexts(title: Self.fill(t.title, a, language), observation: Self.fill(t.observation, a, language),
                             implication: Self.fill(t.implication, a, language), action: Self.fill(t.action, a, language))
    }

    public func consequence(_ finding: Finding, _ language: Language) -> ConsequenceTexts {
        guard let entry = consequences[finding.id] else {
            return ConsequenceTexts(title: finding.id, text: "", severity: .info)
        }
        let t = language == .en ? entry.en : entry.cs
        return ConsequenceTexts(title: Self.fill(t.title, finding.args, language), text: Self.fill(t.text, finding.args, language),
                                severity: entry.severity)
    }

    public func severity(of consequenceID: String) -> Severity {
        consequences[consequenceID]?.severity ?? .info
    }

    public func check(_ finding: Finding, _ language: Language) -> String {
        guard let t = checks[finding.id] else { return finding.id }
        return Self.fill(t.resolve(language), finding.args, language)
    }

    /// Text for an `inc.*` reason; free-text reasons are returned as they are.
    public func incomplete(_ reason: String?, _ language: Language) -> String {
        guard let reason else { return "" }
        return incomplete[reason]?.resolve(language) ?? reason
    }
}
