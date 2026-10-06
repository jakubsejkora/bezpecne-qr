import BQCore

/// Presentation only: no new findings, scores, thresholds or action permissions.
struct ResultSummary {
    let typeName: String
    let verdict: Verdict
    let score: Int?
    let provisional: Bool
    let leadingReason: String?
    let visibleConsequences: [FindingTexts.Consequence]
    let surface: SignalPalette.Surface

    init(_ analysis: Analysis, texts: FindingTexts, language: Language, checking: Bool = false) {
        typeName = language.t("type." + analysis.type.rawValue)
        let currentVerdict = Verdict(analysis, texts, language)
        verdict = currentVerdict
        score = analysis.assessment.scored && !analysis.decodeOnly ? analysis.assessment.score : nil
        provisional = checking || analysis.completeness.state == .incomplete || analysis.completeness.state == .skipped
        let critical = texts.consequences.first { $0.texts.severity == .critical }
        if let critical {
            leadingReason = currentVerdict.isAlert ? critical.texts.text : critical.texts.title
        } else if case .text(let info) = analysis.content, analysis.band == .info {
            leadingReason = language.t(info.entities.contains(where: { $0.kind == "url" }) ? "text.hasLink" : "text.noLink")
        } else if currentVerdict.tone == .incomplete {
            leadingReason = currentVerdict.subtitle
        } else if analysis.band == .danger || analysis.band == .caution {
            leadingReason = texts.reasons.first?.texts.title
        } else {
            leadingReason = texts.consequences.first { $0.texts.severity == .warning }?.texts.title
        }
        // A consequence already stated in full in the header does not need a second panel.
        visibleConsequences = texts.consequences.filter {
            $0.texts.severity != .info && !(currentVerdict.isAlert && $0.id == critical?.id)
        }
        let base: SignalPalette.RGB
        if currentVerdict.tone == .danger { base = score.map(SignalPalette.color(at:)) ?? SignalPalette.color(for: .danger) }
        else if critical != nil { base = SignalPalette.color(for: .alert) }
        else if provisional { base = SignalPalette.color(for: .incomplete) }
        else if let score { base = SignalPalette.color(at: score) }
        else { base = SignalPalette.color(for: .info) }
        surface = SignalPalette.Surface(base)
    }
}

/// Preserve every existing action and its confirmation while reducing initial choice overload.
struct ResultActionGroups {
    let primary: [ActionPlan.Item]
    let secondary: [ActionPlan.Item]
    init(_ plan: ActionPlan) {
        let items = plan.items.filter { !$0.isDismissal }
        let preferred = items.firstIndex {
            if case .button(let b) = $0 { return b.style == .primary }
            return false
        } ?? items.firstIndex {
            switch $0 {
            case .button(let b): b.style != .disabled
            case .row: true
            default: false
            }
        }
        var main: [ActionPlan.Item] = [], more: [ActionPlan.Item] = []
        for (index, item) in items.enumerated() {
            let staysVisible: Bool
            switch item {
            case .hint: staysVisible = true
            case .button(let b): staysVisible = b.style == .disabled || index == preferred
            default: staysVisible = index == preferred
            }
            if staysVisible { main.append(item) } else { more.append(item) }
        }
        primary = main; secondary = more
    }
}
