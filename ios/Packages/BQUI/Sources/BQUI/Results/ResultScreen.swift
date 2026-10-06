import BQCore
import SwiftUI

/// The whole result sheet: "Kontroluji…" progress, then the verdict, the type card, reasons,
/// consequences, actions and "Podrobnosti kontroly"; plus the page extract ("Výtah ze stránky"),
/// toasts, the hold-to-confirm alternative and the close button. Present it as a full-height sheet.
public struct ResultScreen: View {
    public enum Layout { case full, summary, popup }
    @Bindable private var model: ResultModel
    private var layout: Layout
    private var onExpand: (() -> Void)?
    private var onHeightChange: ((CGFloat) -> Void)?
    @Environment(\.bqSnapshot) private var snapshot
    @Environment(\.bqDesign) private var design
    @Environment(\.bqSignalPreset) private var preset
    @Environment(\.dynamicTypeSize) private var textSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var checkingVisible = false
    /// Bumped once per new verdict: drives the success / warning / error haptic.
    @State private var verdictPulse = 0

    public init(model: ResultModel, layout: Layout = .full, onExpand: (() -> Void)? = nil,
                onHeightChange: ((CGFloat) -> Void)? = nil) {
        self.model = model
        self.layout = layout; self.onExpand = onExpand; self.onHeightChange = onHeightChange
    }
    private var fitting: Bool { layout == .popup && !model.resultExpanded }
    private func measure(_ height: CGFloat) { onHeightChange?(height + 60) }
    private func expand() { model.resultExpanded = true; onExpand?() }

    public var body: some View {
        let lang = model.language
        let analysis = model.analysis
        let showChecking = model.isChecking && analysis.band != .danger && model.capabilities != .imageExtension
        let verdictKey: String? = showChecking ? nil : "\(analysis.code.text.hashValue)-\(analysis.band.rawValue)"

        ZStack(alignment: .bottom) {
            Group {
                if showChecking {
                    SheetPage(back: model.onShowAllCodes, backLabel: model.onShowAllCodes == nil ? nil : lang.t("choose.all"), close: { model.perform(.close) }, fitContent: fitting, onHeightChange: measure) {
                        if layout == .full && !analysis.isSensitive { CaptureHeader() }
                        CheckingView(model: model)
                            .opacity(checkingVisible || snapshot ? 1 : 0)
                    }
                    .transition(.opacity)
                } else {
                    SheetPage(back: model.onShowAllCodes, backLabel: model.onShowAllCodes == nil ? nil : lang.t("choose.all"), close: { model.perform(.close) }, fitContent: fitting, onHeightChange: measure) {
                        ResultContent(model: model)
                    }
                    .transition(.opacity)
                }
            }
            if let toast = model.toast {
                ToastView(toast: toast)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                    .zIndex(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: snapshot || fitting ? nil : .infinity, alignment: .top)
        .overlay {
            ConfettiView(trigger: model.celebration)
        }
        .backgroundPreferenceValue(FadeHeaderHeightKey.self) { headerHeight in
            if design == .signal && preset == .fade && !showChecking {
                let summary = ResultSummary(analysis, texts: FindingTexts(analysis, lang), language: lang, checking: model.isChecking)
                ResultFadeBackdrop(base: summary.surface.start, headerHeight: headerHeight)
            }
        }
        .background(design.background.ignoresSafeArea())
        .environment(\.bqLanguage, lang)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: showChecking)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: model.route)
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .snappy(duration: 0.3), value: model.toast)
        .alert(model.confirmation?.title ?? "", isPresented: Binding(
            get: { model.confirmation != nil },
            set: { if !$0 { model.confirmation = nil } }
        ), presenting: model.confirmation) { confirmation in
            Button(lang.t("alert.cancel"), role: .cancel) {}
            Button(confirmation.confirmTitle, role: .destructive) { model.perform(confirmation.action) }
        } message: { confirmation in
            if let message = confirmation.message { Text(message) }
        }
        .task(id: model.isChecking) {
            checkingVisible = false
            guard model.isChecking else { return }
            // The progress state appears only if checking lasts longer than ~300 ms.
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.2)) { checkingVisible = true }
        }
        .task(id: model.toast?.id) {
            guard let toast = model.toast else { return }
            AccessibilityNotification.Announcement(toast.text).post()
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled, model.toast?.id == toast.id else { return }
            model.toast = nil
        }
        .task(id: verdictKey) { await announce(verdictKey) }
        .sensoryFeedback(trigger: verdictPulse) { _, _ in
            Self.feedback(for: model.analysis, lang)
        }
    }

    /// VoiceOver hears the verdict once, e.g. "Riziko 72 ze 100, nebezpečné"; the haptic plays once.
    private func announce(_ key: String?) async {
        guard let key, model.announcedVerdict != key, !snapshot else { return }
        model.announcedVerdict = key
        verdictPulse += 1
        let analysis = model.analysis
        let lang = model.language
        let text = Verdict(analysis, FindingTexts(analysis, lang), lang).announcement(analysis, lang)
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled, model.announcedVerdict == key else { return }
        AccessibilityNotification.Announcement(text).post()
    }

    private static func feedback(for analysis: Analysis, _ lang: Language) -> SensoryFeedback? {
        let verdict = Verdict(analysis, FindingTexts(analysis, lang), lang)
        switch verdict.tone {
        case .danger: return .error
        case .caution, .alert: return .warning
        case .safe: return .success
        case .incomplete, .info: return nil
        }
    }
}

/// A page of the sheet: the chrome bar on top, scrolling content below. In snapshot mode the
/// content is laid out unconstrained (no scroll view) so it can be rendered whole.
struct SheetPage<Content: View>: View {
    var title: String?
    var back: (() -> Void)?
    var backLabel: String? = nil
    var close: (() -> Void)?
    var fitContent = false
    var onHeightChange: ((CGFloat) -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.bqSnapshot) private var snapshot
    @Environment(\.bqDesign) private var design

    var body: some View {
        if snapshot || fitContent {
            // A scroll view proposes an unlimited height; ImageRenderer would propose the exact
            // measured height instead, so the snapshot fixes the content at its ideal height.
            VStack(spacing: 0) {
                SheetChrome(title: title, back: back, backLabel: backLabel, close: close)
                padded
            }
            .fixedSize(horizontal: false, vertical: true)
        } else {
            ScrollView {
                padded
            }
            .scrollBounceBehavior(.basedOnSize)
            .modifier(TopBar { SheetChrome(title: title, back: back, backLabel: backLabel, close: close) })
        }
    }

    private var padded: some View {
        content
            .padding(.horizontal, design.padding)
            .padding(.top, 2)
            .padding(.bottom, fitContent ? 8 : 24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { onHeightChange?($0) }
    }
}

/// iOS 26: a safe-area bar (content scrolls under it with the system edge effect);
/// iOS 18: a plain safe-area inset.
private struct TopBar<Bar: View>: ViewModifier {
    @ViewBuilder var bar: Bar

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.safeAreaBar(edge: .top) { bar }
        } else {
            content.safeAreaInset(edge: .top, spacing: 0) { bar }
        }
    }
}

/// The result, in the order of screens.js `result()`: header → meter → sticker tip → type card →
/// completeness notice → top reasons → consequences → quick checks → actions → details.
struct ResultContent: View {
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqDesign) private var design

    @ViewBuilder var body: some View {
        if design == .signal { SignalResultContent(model: model) }
        else { comparisonContent }
    }
    @ViewBuilder private var comparisonContent: some View {
        let a = model.analysis
        let texts = FindingTexts(a, lang)
        let verdict = Verdict(a, texts, lang)
        let plan = ActionPlan(a, verdict: verdict, texts: texts, lang: lang, contactSaved: model.contactSaved, capabilities: model.capabilities)
        let showTopReasons = !texts.reasons.isEmpty && a.band != .safe && a.band != .info
        let topCount = showTopReasons ? min(2, texts.reasons.count) : 0

        VStack(alignment: .leading, spacing: 0) {
            if !a.isSensitive { CaptureHeader(showImage: model.capabilities == .imageExtension) }
            VerdictHeader(verdict: verdict)
            if model.isChecking {
                InlineChecking(model: model)
            }
            if Self.showsStickerTip(a, fromCamera: model.fromCamera) {
                Notice(icon: Symbol.sticker, tone: .caution) {
                    Text(Typo.prose(lang.t("scan.stickerTip"), lang)).fixedSize(horizontal: false, vertical: true)
                }
                .blockGap()
            }
            TypeCard(analysis: a, model: model)
            CompletenessNotice(analysis: a) { model.perform(.manualCheck) }
            ActionsView(items: plan.items.filter { model.capabilities == .imageExtension || !$0.isDismissal }, model: model)
            if showTopReasons {
                SectionTitle(text: lang.t("sec.why"))
                ReasonList(reasons: Array(texts.reasons.prefix(topCount)))
                    .bqCard()
                    .blockGap()
            }
            if !texts.consequences.isEmpty {
                SectionTitle(text: lang.t("sec.consequence"))
                ForEach(texts.consequences) { ConsequenceBox(consequence: $0) }
            }
            if a.assessment.scored, !a.decodeOnly, let score = a.assessment.score {
                CompactRiskMeter(score: score, muted: a.band == .incomplete)
            }
            if a.band == .danger, let help = model.onRecoveryHelp {
                Button(lang.t("set.recovery"), action: help).buttonStyle(BQButtonStyle(kind: .plain))
            }
            if (a.band == .safe || a.band == .info), !texts.checks.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    SubHeading(text: lang.t("sec.checked"), top: 0)
                    ChecksList(checks: Array(texts.checks.prefix(3)))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BQColor.card, in: .card(Metrics.cardRadius))
                .blockGap()
            }
            DetailsSection(model: model, texts: texts, shownReasons: topCount)
                .padding(.top, 2)
        }
    }

    /// "Přejeďte po kódu prstem…" — for camera scans of links and payments that aren't clean.
    static func showsStickerTip(_ a: Analysis, fromCamera: Bool) -> Bool {
        fromCamera && stickerTypes.contains(a.type) && !a.isSensitive
            && [.caution, .danger, .incomplete].contains(a.band)
    }

    /// Links and payments — what fake stickers are made of.
    private static let stickerTypes: Set<CodeType> = [.url, .store, .messenger, .intent, .spd, .epc, .spc, .crypto]
}

/// "Podrobnosti kontroly": remaining reasons, every check, the raw data (hidden for sensitive
/// codes) and — in DEBUG builds only — the score math.
struct DetailsSection: View {
    var model: ResultModel
    var texts: FindingTexts
    var shownReasons: Int
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqDesign) private var design

    var body: some View {
        let a = model.analysis
        let more = Array(texts.reasons.dropFirst(shownReasons))
        Disclosure(title: lang.t("sec.details"), isExpanded: Binding(
            get: { model.detailsExpanded }, set: { model.detailsExpanded = $0 })) {
            VStack(alignment: .leading, spacing: 0) {
                if design == .signal {
                    if a.assessment.scored, !a.decodeOnly {
                        Text(lang.t("meter.note")).font(.footnote).foregroundStyle(BQColor.label2).padding(.vertical, 10)
                    }
                    if ResultContent.showsStickerTip(a, fromCamera: model.fromCamera) {
                        Notice(icon: Symbol.sticker, tone: .caution) { Text(lang.t("scan.stickerTip")) }.blockGap()
                    }
                    if !texts.consequences.isEmpty {
                        SubHeading(text: lang.t("sec.consequence"), top: 0)
                        ForEach(texts.consequences) { ConsequenceBox(consequence: $0) }
                    }
                }
                if case .link = a.content {
                    if let title = a.inspection?.page?.title { Claim(caption: lang.t("url.claim"), text: lang.quoted(title)) }
                }
                if !more.isEmpty {
                    SubHeading(text: lang.t(design == .signal ? "sec.why" : "sec.more"), top: 0)
                    ReasonList(reasons: more)
                        .padding(.top, 6)
                        .padding(.bottom, 4)
                }
                if !texts.checks.isEmpty {
                    SubHeading(text: lang.t("sec.checked"), top: more.isEmpty ? 0 : 12)
                    ChecksList(checks: texts.checks)
                }
                SubHeading(text: lang.t("sec.raw"), top: more.isEmpty && texts.checks.isEmpty ? 0 : 12)
                if a.isSensitive {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "lock.fill")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                        Text(Typo.prose(lang.t("sec.rawHidden"), lang))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .bqFont(14, relativeTo: .subheadline)
                    .foregroundStyle(BQColor.label2)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(BQColor.card2, in: .card(12))
                    .padding(.top, 6)
                    .padding(.bottom, 4)
                } else {
                    RawBox(text: a.code.text, selectable: true)
                }
                #if DEBUG
                if a.assessment.scored, let math = a.assessment.math {
                    SubHeading(text: lang.t("sec.diag"))
                    RawBox(text: Self.diagnostics(math, score: a.assessment.score), selectable: true)
                }
                #endif
            }
            .padding(.bottom, 14)
        }
    }

    /// "b = -3 · identity 2.5 · … ↵ logit 1.2 → 77 · floor 80 → 80".
    static func diagnostics(_ m: ScoreMath, score: Int?) -> String {
        func n(_ v: Double) -> String {
            let r = (v * 100).rounded() / 100
            return r == r.rounded() ? String(Int(r)) : String(r)
        }
        let groups = m.groups.map { "\($0.group) \(n($0.contribution))" }.joined(separator: " · ")
        var line2 = "logit \(n(m.logit)) → \(n(m.raw))"
        if let cap = m.weakOnlyCapApplied { line2 += " · cap \(n(cap))" }
        if let floor = m.floorApplied { line2 += " · floor \(floor.floor) (\(floor.id))" }
        line2 += " → \(score.map(String.init) ?? "—")"
        return "b = \(n(m.baseline)) · \(groups.isEmpty ? "—" : groups)\n\(line2)"
    }
}

/// `.raw`: the code's content in a monospaced box.
struct RawBox: View {
    var text: String
    var selectable: Bool

    var body: some View {
        let label = Text(text)
            .bqFont(12.5, design: .monospaced, relativeTo: .caption)
            .foregroundStyle(BQColor.label)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BQColor.card2, in: .card(12))
            .padding(.top, 6)
            .padding(.bottom, 4)
        if selectable {
            label.textSelection(.enabled)
        } else {
            label
        }
    }
}

/// While a decisive danger is already shown, the network check may still be running.
struct InlineChecking: View {
    var model: ResultModel
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        HStack(spacing: 10) {
            Spinner()
            Text(CheckingView.label(for: model.stepHistory.last ?? .address, model.analysis, lang))
                .bqFont(14.5, relativeTo: .subheadline)
                .foregroundStyle(BQColor.label2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(BQColor.card, in: .card(14))
        .blockGap()
        .accessibilityElement(children: .combine)
    }
}
