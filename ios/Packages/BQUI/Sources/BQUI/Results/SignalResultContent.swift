import BQCore
import SwiftUI

/// The decision comes first. Full evidence and less common actions remain one tap away.
struct SignalResultContent: View {
    @Bindable var model: ResultModel
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqDesign) private var design
    var body: some View {
        let a = model.analysis
        let texts = FindingTexts(a, lang)
        let summary = ResultSummary(a, texts: texts, language: lang, checking: model.isChecking)
        let plan = ActionPlan(a, verdict: summary.verdict, texts: texts, lang: lang, contactSaved: model.contactSaved, capabilities: model.capabilities)
        let actions = ResultActionGroups(plan)
        VStack(alignment: .leading, spacing: 0) {
            SignalVerdictHeader(summary: summary, bleed: design.padding)
            if model.isChecking { InlineChecking(model: model) }
            TypeCard(analysis: a, model: model)
            CompletenessNotice(analysis: a) { model.perform(.manualCheck) }
            ForEach(summary.visibleConsequences) { ConsequenceBox(consequence: $0) }
            ActionsView(items: actions.primary.filter { !$0.isDismissal }, model: model)
            if !actions.secondary.isEmpty {
                Disclosure(title: lang.t("summary.moreActions"), isExpanded: $model.moreActionsExpanded) {
                    ActionsView(items: actions.secondary.filter { !$0.isDismissal }, model: model).padding(.bottom, 8)
                }.padding(.top, 8)
            }
            if a.inspection?.page != nil {
                Disclosure(title: lang.t("prev.title"), isExpanded: $model.pageExtractExpanded) {
                    PageExtractView(model: model).padding(.vertical, 12)
                }.padding(.top, 8)
            }
            if !a.isSensitive { CaptureHeader(showImage: model.capabilities == .imageExtension) }
            DetailsSection(model: model, texts: texts, shownReasons: 0).padding(.top, 8)
            if a.band == .danger, let help = model.onRecoveryHelp {
                Button(lang.t("set.recovery"), action: help).buttonStyle(BQButtonStyle(kind: .plain))
                    .padding(.top, 8)
            }
        }
    }
}
