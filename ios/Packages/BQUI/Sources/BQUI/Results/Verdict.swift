import BQCore
import Foundation

/// Localized texts of an analysis' findings, sorted like the prototype (cards.js).
struct FindingTexts {
    struct Reason: Identifiable {
        var id: String
        var weight: Double
        var texts: EvidenceTexts
        /// ≥ 2 → danger, ≥ 1 → caution, else weak (cards.js `reasonHTML`).
        var tone: Tone? { weight >= 2 ? .danger : weight >= 1 ? .caution : nil }
        var icon: String { weight >= 2 ? Symbol.danger : weight >= 1 ? Symbol.caution : Symbol.info }
    }

    struct Consequence: Identifiable {
        var id: String
        var texts: ConsequenceTexts
        var tone: Tone {
            switch texts.severity {
            case .critical: .alert
            case .warning: .caution
            case .info: .info
            }
        }
    }

    var reasons: [Reason]
    var consequences: [Consequence]
    var checks: [(id: String, text: String)]

    init(_ analysis: Analysis, _ lang: Language, rules: RuleSet = .bundled) {
        let weights = rules.weights.signals
        let texts = rules.texts

        var reasons: [Reason] = []
        for finding in analysis.evidence {
            let weight = weights[finding.id]?.weight ?? 0
            var t = texts.evidence(finding, lang)
            t.title = Typo.prose(t.title, lang)
            t.observation = Typo.prose(t.observation, lang)
            t.implication = Typo.prose(t.implication, lang)
            t.action = Typo.prose(t.action, lang)
            reasons.append(Reason(id: finding.id, weight: weight, texts: t))
        }
        // Strongest first; equal weights keep the analyzer's order (stable sort).
        self.reasons = Self.stableSorted(reasons) { $0.weight > $1.weight }

        var consequences: [Consequence] = []
        for finding in analysis.consequences {
            var t = texts.consequence(finding, lang)
            t.title = Typo.prose(t.title, lang)
            t.text = Typo.prose(t.text, lang)
            consequences.append(Consequence(id: finding.id, texts: t))
        }
        // Most severe first.
        self.consequences = Self.stableSorted(consequences) { $0.texts.severity < $1.texts.severity }

        var checks: [(id: String, text: String)] = []
        for finding in analysis.checks {
            checks.append((finding.id, Typo.prose(texts.check(finding, lang), lang)))
        }
        self.checks = checks
    }

    private static func stableSorted<T>(_ items: [T], by before: (T, T) -> Bool) -> [T] {
        let indexed = Array(items.enumerated())
        let sorted = indexed.sorted { a, b in
            if before(a.element, b.element) { return true }
            if before(b.element, a.element) { return false }
            return a.offset < b.offset
        }
        return sorted.map(\.element)
    }
}

/// The verdict header (cards.js `headerModel`): danger → critical consequence ("alert") → caution →
/// incomplete → informational → safe.
struct Verdict: Equatable {
    enum Effect: Equatable { case pulse, wiggle, draw, none }

    struct VerdictChip: Equatable {
        var tone: Tone
        var text: String
    }

    var tone: Tone
    var icon: String
    var effect: Effect
    var kicker: String?
    var title: String
    var subtitle: String?
    var chip: VerdictChip?

    /// A critical consequence leads the header; the meter then reads "Riziko podvodu".
    var isAlert: Bool { tone == .alert }

    init(_ analysis: Analysis, _ texts: FindingTexts, _ lang: Language) {
        let top = texts.reasons.first?.texts
        let critical = texts.consequences.first { $0.texts.severity == .critical }
        let warning = texts.consequences.first { $0.texts.severity == .warning }
        let typeName = lang.t("type.\(analysis.type.rawValue)")
        let band = analysis.band

        if band == .danger {
            tone = .danger; icon = Symbol.danger; effect = .pulse
            kicker = typeName
            title = lang.t("band.danger")
            subtitle = top.map { Verdict.sentence($0.title) + " " + $0.implication }
            chip = nil
        } else if let critical {
            tone = .alert; icon = Symbol.consequence(critical.id); effect = .wiggle
            kicker = "\(typeName) · \(lang.t("band.alertKicker"))"
            title = critical.texts.title
            subtitle = nil
            chip = nil
        } else if band == .caution {
            tone = .caution; icon = Symbol.caution; effect = .wiggle
            kicker = typeName
            title = lang.t("band.caution")
            subtitle = top?.title
            chip = nil
        } else if band == .incomplete {
            tone = .incomplete; icon = Symbol.incomplete; effect = .none
            kicker = typeName
            title = lang.t("band.incomplete")
            let reason = RuleSet.bundled.texts.incomplete(analysis.completeness.reason, lang)
            subtitle = Typo.prose(reason.isEmpty ? lang.t("band.incompleteSub") : reason, lang)
            chip = nil
        } else if band == .info {
            tone = .info; icon = Symbol.type(analysis.type); effect = .none
            kicker = nil
            title = typeName
            subtitle = nil
            chip = warning.map { VerdictChip(tone: .caution, text: $0.texts.title) }
                ?? VerdictChip(tone: .safe, text: lang.t("band.infoChip"))
        } else {
            tone = .safe; icon = Symbol.safe; effect = .draw
            kicker = typeName
            title = lang.t("band.safe")
            subtitle = Typo.prose(lang.t("band.safeSub"), lang)
            chip = warning.map { VerdictChip(tone: .caution, text: $0.texts.title) }
        }
    }

    /// "Vydává se za značku EasyPark" → "Vydává se za značku EasyPark." (no double punctuation).
    static func sentence(_ s: String) -> String {
        guard let last = s.last else { return s }
        return ".!?…".contains(last) ? s : s + "."
    }

    /// What VoiceOver announces once, e.g. "Riziko 72 ze 100, nebezpečné".
    func announcement(_ analysis: Analysis, _ lang: Language) -> String {
        let a = analysis.assessment
        let showsScore = a.scored && !analysis.decodeOnly && a.score != nil
        if isAlert, showsScore, let score = a.score {
            return lang.t("a11y.verdictAlert", ["title": title, "score": String(score)])
        }
        if showsScore, let score = a.score {
            let bandName = lang.t("band.\(analysis.band.rawValue)").lowercased(with: lang.locale)
            var text = lang.t("a11y.verdictScored", ["score": String(score), "band": bandName])
            if let subtitle, tone != .safe { text += ". " + subtitle }
            return text
        }
        return [title, chip?.text].compactMap { $0 }.joined(separator: ", ")
    }
}
