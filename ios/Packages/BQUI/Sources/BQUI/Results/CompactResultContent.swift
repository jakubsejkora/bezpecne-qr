import BQCore
import SwiftUI

struct CompactResultContent: View {
    @Bindable var model: ResultModel
    let popup: Bool
    let expand: () -> Void
    @Environment(\.bqDesign) private var design
    @Environment(\.bqLanguage) private var lang
    var body: some View {
        let a = model.analysis
        let texts = FindingTexts(a, lang)
        let summary = ResultSummary(a, texts: texts, language: lang, checking: model.isChecking)
        let actions = ResultActionGroups(ActionPlan(a, verdict: summary.verdict, texts: texts, lang: lang,
            contactSaved: model.contactSaved, capabilities: model.capabilities))
        VStack(alignment: .leading, spacing: 0) {
            if design == .signal { SignalVerdictHeader(summary: summary, bleed: design.padding) }
            else { VerdictHeader(verdict: summary.verdict) }
            if model.isChecking { InlineChecking(model: model) }
            if popup, case .link(let info) = a.content {
                let destination = a.linkResolution
                let endpoint = destination?.resolved ?? destination?.lastObserved
                VStack(alignment: .leading, spacing: 6) {
                    CardLabel(text: lang.t(destination?.resolved != nil ? "destination.resolved" : endpoint != nil ? "destination.observed" : "destination.scanned"))
                    HostText(host: endpoint?.host ?? info.host, registrable: endpoint?.registrable ?? info.registrable,
                             size: 24, relativeTo: .title2, regular: .medium, emphasis: .heavy)
                    if destination?.resolved == nil {
                        Text(lang.t(destination?.state == .appHandoff ? "destination.handoff" : "destination.unknown"))
                            .font(.subheadline.weight(.semibold))
                    }
                }.padding(.vertical, 8).blockGap()
            } else { TypeCard(analysis: a, model: model) }
            CompletenessNotice(analysis: a) { model.perform(.manualCheck) }
            ForEach(summary.visibleConsequences) { ConsequenceBox(consequence: $0) }
            if !popup {
                ActionsView(items: actions.primary.filter { !$0.isDismissal }, model: model)
            }
            Button(action: expand) {
                HStack { Text(lang.t("result.details")); Spacer(); Image(systemName: "arrow.up.right") }
                    .font(.headline).frame(minHeight: 48).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(design.ink).accessibilityIdentifier("result.details")
        }
    }
}

extension ActionPlan.Item {
    var isDismissal: Bool {
        guard case .button(let b) = self, case .perform(let action) = b.behavior else { return false }
        return action == .close || action == .backToScanning
    }
}
