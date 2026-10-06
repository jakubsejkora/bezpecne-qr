#if DEBUG || DESIGN_REVIEW
import BQCore
import BQUI
import SwiftUI

/// Design review only. Choices live in this view; no consent, identifiers or reports are saved.
/// Live onboarding must not offer this until the reporting contract and service exist.
struct SharingOnboardingPreview: View {
    let close: () -> Void
    @State private var step = Step.intro
    @State private var reports = false
    @State private var diagnostics = false
    @State private var details = false
    @Environment(\.bqDesign) private var design
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var headingFocused: Bool
    private let lang = Language.preferred
    private enum Step: Hashable { case intro, choices, finished }

    private func t(_ key: String) -> String { L10n.t("sharingPreview." + key, lang) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if step == .intro { introduction }
                else if step == .choices { choices }
                else { completion }
            }.padding(.bottom, 24)
        }
        .scrollBounceBehavior(.basedOnSize).id(step)
        .safeAreaInset(edge: .top, spacing: 0) { chrome }
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .background(design.background.ignoresSafeArea()).foregroundStyle(design.ink)
        .onChange(of: step) { _, _ in headingFocused = true }
    }

    private var chrome: some View {
        HStack(spacing: 12) {
            Text(t("preview"))
                .font(.caption.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("sharing.previewNotice")
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44).background(design.surface, in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(L10n.t("act.close", lang))
                .accessibilityIdentifier("sharing.close")
        }.padding(.horizontal, 22).padding(.vertical, 8).background(design.background)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                if !typeSize.isAccessibilitySize {
                    HStack {
                        Text(t("eyebrow")).font(.caption.weight(.bold)).textCase(.uppercase).tracking(1)
                        Spacer()
                        Image(systemName: "person.2.fill").font(.system(size: 28, weight: .semibold)).accessibilityHidden(true)
                    }
                }
                Text(t("title"))
                    .font(.system(.largeTitle, weight: .heavy)).tracking(-1.1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
                Text(t("benefit")).font(.title3.weight(.medium)).fixedSize(horizontal: false, vertical: true)
            }.padding(26).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(DesignDirection.signal.accentInk).background(DesignDirection.signal.accent)

            VStack(alignment: .leading, spacing: 24) {
                fact("link", "introReports", "introReportsText")
                Divider()
                fact("hand.raised", "introChoice", "introChoiceText")
                Text(t("noExtras")).font(.footnote).foregroundStyle(design.ink.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
            }.padding(26)
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 22) {
            title(t("choicesTitle"))
            Text(t("choicesText")).font(.body).fixedSize(horizontal: false, vertical: true)
            option("reports", "reportsText", selection: $reports, id: "sharing.reports")
            Divider()
            option("diagnostics", "diagnosticsText", selection: $diagnostics, id: "sharing.diagnostics")
            Divider()
            DisclosureGroup(t("details"), isExpanded: $details) {
                VStack(alignment: .leading, spacing: 18) {
                    fact("link", "reportFields", "reportFieldsText")
                    fact("chart.bar", "diagnosticFields", "diagnosticFieldsText")
                    Text(t("excluded")).font(.footnote).fixedSize(horizontal: false, vertical: true)
                }.padding(.top, 16)
            }.font(.headline).tint(design.ink)
            Text(t("optional")).font(.footnote).foregroundStyle(design.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }.padding(26)
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 24) {
            Image(systemName: "checkmark.circle").font(.system(size: 50, weight: .light)).accessibilityHidden(true)
            title(t("doneTitle"))
            Text(t("doneText")).font(.title3).fixedSize(horizontal: false, vertical: true)
            LabeledContent(t("reports"), value: L10n.t(reports ? "common.yes" : "common.no", lang))
            LabeledContent(t("diagnostics"), value: L10n.t(diagnostics ? "common.yes" : "common.no", lang))
        }.padding(26).accessibilityIdentifier("sharing.finished")
    }

    private func title(_ text: String) -> some View {
        Text(text).font(.system(.largeTitle, weight: .heavy)).tracking(-0.8)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader).accessibilityFocused($headingFocused)
    }
    private func fact(_ symbol: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 15) {
            if !typeSize.isAccessibilitySize {
                Image(systemName: symbol).font(.system(size: 22, weight: .medium))
                    .frame(width: 30, height: 30).accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(t(title)).font(.headline)
                Text(t(body)).font(.subheadline).foregroundStyle(design.ink.opacity(0.78))
            }.fixedSize(horizontal: false, vertical: true)
        }.accessibilityElement(children: .combine)
    }
    private func option(_ title: String, _ body: String, selection: Binding<Bool>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: selection) {
                Text(t(title)).font(.headline).fixedSize(horizontal: false, vertical: true)
            }.tint(Color(red: 0.17, green: 0.48, blue: 0.08)).accessibilityIdentifier(id)
                .accessibilityHint(t(body))
            Text(t(body)).font(.subheadline).foregroundStyle(design.ink.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
    private var actions: some View {
        VStack(spacing: 6) {
            Button(t(step == .finished ? "close" : typeSize.isAccessibilitySize ? "nextShort" : step == .intro ? "continue" : "confirm")) {
                if step == .finished { close() }
                else { step = step == .intro ? .choices : .finished }
            }.buttonStyle(PrimaryButtonStyle()).accessibilityIdentifier("sharing.continue")
            if step != .finished {
                Button(t(typeSize.isAccessibilitySize ? "skipShort" : "skip")) {
                    reports = false; diagnostics = false; step = .finished
                }.font(.body.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 44)
                    .buttonStyle(.plain).accessibilityIdentifier("sharing.skip")
            }
        }.id(step).padding(.horizontal, 22).padding(.vertical, 12).background(design.background)
    }
}
#endif
