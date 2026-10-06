import BQCore
import SwiftUI

extension Language {
    /// „text“ in Czech, “text” in English.
    func quoted(_ s: String) -> String {
        self == .cs ? "„\(s)“" : "“\(s)”"
    }
}

/// `urlCard`: "Cíl odkazu" with the full destination domain, the observed journey and what the
/// page asks for.
struct LinkCard: View {
    var analysis: Analysis
    var info: LinkInfo
    @Environment(\.bqLanguage) private var lang
    @Environment(\.bqDesign) private var design
    @State private var addressExpanded = false

    var body: some View {
        let inspection = analysis.inspection
        let resolution = analysis.linkResolution
        let final = resolution?.resolved
        // The compact Signal card keeps the ASCII domain visible even though the full URL
        // moved into details, so look-alike IDNs still expose their xn-- form at first sight.
        let observed = final ?? resolution?.lastObserved
        let host = observed?.host ?? info.host
        let registrable = observed?.registrable ?? info.registrable
        // The ASCII form is shown on purpose: it exposes look-alike letters (xn--…).

        VStack(alignment: .leading, spacing: 0) {
            if final == nil {
                Text(lang.t(analysis.completeness.reason == "inc.pending" ? "destination.checking" :
                            resolution?.state == .appHandoff ? "destination.handoff" : "destination.unknown"))
                    .font(.headline).fixedSize(horizontal: false, vertical: true).padding(.bottom, 10)
            }
            CardLabel(text: lang.t(final != nil ? "destination.resolved" : observed != nil ? "destination.observed" : "destination.scanned"))
            HostText(host: host, registrable: registrable, size: 24, relativeTo: .title2, regular: .medium, emphasis: .heavy)
                .foregroundStyle(BQColor.label)
                .padding(.top, 4)
                .padding(.bottom, 6)
            if !analysis.isSensitive {
                Disclosure(title: lang.t("destination.addresses"), isExpanded: $addressExpanded) {
                    VStack(alignment: .leading, spacing: 8) {
                        CardLabel(text: lang.t("destination.originalURL"))
                        MonoText(text: info.url)
                        if let final {
                            CardLabel(text: lang.t("destination.resolvedURL"))
                            MonoText(text: final.url)
                        } else if let observed, observed.url != info.url {
                            CardLabel(text: lang.t("destination.observed"))
                            MonoText(text: observed.url)
                        }
                        SubHeading(text: lang.t("url.journey"))
                        JourneyView(stops: JourneyView.stops(analysis, info, lang))
                    }.padding(.vertical, 8)
                }
            }
            if let userinfo = info.userinfo {
                FinePrint(icon: Symbol.caution, text: "\(userinfo)@ — \(lang.t("url.userinfo"))")
            }
            if let inner = info.inner {
                FinePrint(icon: "link", text: lang.t("url.inner") + ":", bold: inner)
            }
            if design != .signal, info.upgraded != nil, analysis.checks.contains(where: { $0.id == "chk.https_upgraded" }) {
                // Only when the HTTPS variant really worked.
                FinePrint(icon: "lock", text: RuleSet.bundled.texts.check(Finding("chk.https_upgraded"), lang))
            }
            if let page = inspection?.page {
                if !page.asks.isEmpty {
                    SubHeading(text: lang.t("url.asks"))
                    AsksChips(asks: page.asks).padding(.top, 4)
                }
                if let offer = page.offer {
                    Claim(caption: lang.t("url.smallPrint"), text: lang.quoted(offer.text), highlight: true)
                }
            }
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}

/// What a page asks for, as chips (sensitive inputs in caution colours).
struct AsksChips: View {
    var asks: [AskKind]
    var allCaution = false
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        FlowLayout(spacing: 6, lineSpacing: 6) {
            if asks.isEmpty {
                Chip(text: lang.t("url.nothing"), icon: Symbol.check, tone: .safe)
            } else {
                ForEach(asks, id: \.self) { ask in
                    Chip(text: lang.t("ask.\(ask.rawValue)"), icon: nil, tone: (allCaution || Self.sensitive.contains(ask)) ? .caution : nil)
                }
            }
        }
    }

    static let sensitive: Set<AskKind> = [.card, .password, .phone, .otp, .recoverySecret, .personalID]
}

/// The observed redirect chain as a timeline (`ol.journey`).
struct JourneyView: View {
    enum State { case normal, final, stopped, unknown }

    struct Stop: Identifiable {
        var id: Int
        var host: String?
        var meta: String?
        var state: State
    }

    var stops: [Stop]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.bqSnapshot) private var snapshot
    @SwiftUI.State private var revealed = Int.max

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(stops) { stop in
                let isLast = stop.id == stops.count - 1
                HStack(alignment: .top, spacing: 12) {
                    dot(stop.state)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 1) {
                        if let host = stop.host {
                            Text(HostFormat.breakable(host))
                                .bqFont(14, .bold, relativeTo: .subheadline)
                                .foregroundStyle(BQColor.label)
                                .accessibilityLabel(host)
                        }
                        if let meta = stop.meta, !meta.isEmpty {
                            Text(meta)
                                .bqFont(13, relativeTo: .footnote)
                                .foregroundStyle(BQColor.label2)
                        }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.bottom, isLast ? 0 : 12)
                .background(alignment: .topLeading) {
                    if !isLast {
                        connector(dashed: stop.state == .stopped || stops[stop.id + 1].state == .unknown
                                  || stops[stop.id + 1].state == .stopped)
                    }
                }
                .opacity(stop.id <= revealed ? 1 : 0)
                .offset(y: stop.id <= revealed ? 0 : 6)
                .accessibilityElement(children: .combine)
            }
        }
        .onAppear {
            guard !reduceMotion, !snapshot, stops.count > 1 else { return }
            revealed = 0
            Task { @MainActor in
                for index in 1..<stops.count {
                    try? await Task.sleep(for: .milliseconds(170))
                    withAnimation(.spring(duration: 0.35)) { revealed = index }
                }
            }
        }
    }

    @ViewBuilder private func dot(_ state: State) -> some View {
        let size: CGFloat = 16
        switch state {
        case .normal:
            Circle().fill(BQColor.card).overlay(Circle().strokeBorder(BQColor.tint, lineWidth: 3)).frame(width: size, height: size)
        case .final:
            Circle().fill(BQColor.tint).frame(width: size, height: size)
        case .stopped:
            Circle().fill(Tone.alert.background).overlay(Circle().strokeBorder(Tone.alert.color, lineWidth: 3)).frame(width: size, height: size)
        case .unknown:
            Circle().fill(BQColor.card)
                .overlay(Circle().strokeBorder(BQColor.label3, style: StrokeStyle(lineWidth: 2.5, dash: [3, 2.5])))
                .frame(width: size, height: size)
        }
    }

    private func connector(dashed: Bool) -> some View {
        GeometryReader { geo in
            Path { p in
                p.move(to: CGPoint(x: 8, y: 21))
                p.addLine(to: CGPoint(x: 8, y: geo.size.height + 1))
            }
            .stroke(dashed ? BQColor.label3 : BQColor.separator,
                    style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: dashed ? [4, 4] : []))
        }
        .accessibilityHidden(true)
    }

    /// Builds the stops from the inspection (cards.js `urlCard` journey).
    static func stops(_ analysis: Analysis, _ info: LinkInfo, _ lang: Language) -> [Stop] {
        var out: [Stop] = []
        let chain = analysis.inspection?.chain ?? []
        let final = analysis.linkResolution?.resolved
        if chain.isEmpty {
            out.append(Stop(id: 0, host: HostFormat.display(info.hostDisplay ?? info.host), meta: nil, state: .normal))
            out.append(Stop(id: 1, host: nil, meta: lang.t("url.unknownTarget"), state: .unknown))
            return out
        }
        for (index, hop) in chain.enumerated() {
            let host = URL(string: hop.url)?.host.map(HostFormat.display) ?? hop.url
            let last = index == chain.count - 1
            // A clean walk that ends by handing the link to App Store / Google Play: that is the destination.
            if last, isStoreHandOff(hop), analysis.completeness.state == .complete {
                out.append(Stop(id: index, host: lang.t("url.storeApp"), meta: lang.t("url.storeHandoff"), state: .final))
                return out
            }
            let state: State = hop.stopped != nil ? .stopped : (last && final != nil ? .final : .normal)
            out.append(Stop(id: index, host: host, meta: meta(hop, lang), state: state))
        }
        if final == nil {
            out.append(Stop(id: out.count, host: nil, meta: lang.t("url.unknownTarget"), state: .unknown))
        }
        return out
    }

    static func isStoreHandOff(_ hop: Hop) -> Bool {
        guard let scheme = URL(string: hop.url)?.scheme?.lowercased() else { return false }
        return Analyzer.storeSchemes.contains(scheme)
    }

    static func meta(_ hop: Hop, _ lang: Language) -> String {
        if let stopped = hop.stopped {
            switch stopped {
            case .billing: return lang.t("url.stoppedBilling")
            case .operatorSite: return lang.t("url.stoppedOperator")
            case .timeout: return lang.t("url.stoppedTimeout")
            case .gate: return lang.t("url.stoppedGate")
            case .tlsFailed: return lang.t("url.stoppedTls")
            case .error: return lang.t("url.stoppedError")
            case .budget: return lang.t("url.stoppedBudget")
            case .loop: return lang.t("url.stoppedLoop")
            }
        }
        var parts: [String] = []
        if let status = hop.status {
            parts.append((300..<400).contains(status) ? "\(status) · \(lang.t("url.redirect"))" : String(status))
        }
        switch hop.kind {
        case .shortener: parts.append(lang.t("url.shortener"))
        case .httpsUpgrade: parts.append(lang.t("url.https"))
        case .openRedirect: parts.append(lang.t("url.openRedirect"))
        case .curatedRelationship: parts.append(lang.t("url.curated"))
        case .metaRefresh: parts.append(lang.t("url.metaRefresh"))
        case nil: break
        }
        return parts.joined(separator: " · ")
    }
}

/// `webcal://` calendar subscription.
struct WebcalCard: View {
    var info: LinkInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: "webcal", icon: "calendar")
            HostText(host: HostFormat.display(info.hostDisplay ?? info.host), registrable: info.registrable, size: 24,
                     relativeTo: .title2, regular: .medium, emphasis: .heavy)
                .foregroundStyle(BQColor.label)
                .padding(.top, 10)
                .padding(.bottom, 6)
            MonoText(text: info.url)
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}

/// `itms-services://` app install outside the App Store.
struct AppInstallCard: View {
    var info: AppInstallInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: info.scheme, icon: "arrow.down.app")
            SubHeading(text: "Manifest")
            if let host = info.host {
                HostText(host: HostFormat.display(host), registrable: info.registrable, size: 24, relativeTo: .title2,
                         regular: .medium, emphasis: .heavy)
                    .foregroundStyle(BQColor.label)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
            }
            if let manifest = info.manifest {
                MonoText(text: manifest)
            }
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}

/// `.product-card` for App Store / Google Play links.
struct StoreCard: View {
    var info: StoreInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        ProductCardLayout(icon: "bag.fill", gradient: [BQColor.hex(0x1C9BF0), BQColor.hex(0x5856D6)]) {
            Text(info.store)
                .bqFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(BQColor.label)
            if let appId = info.appId {
                CardLabel(text: "\(lang.t("store.appId")): \(appId)")
            }
            MonoText(text: info.url)
                .padding(.top, 2)
        }
    }
}

/// Chat links (wa.me, t.me, signal.me).
struct MessengerCard: View {
    var info: MessengerInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        ProductCardLayout(icon: "bubble.left.and.bubble.right.fill", gradient: [color, color]) {
            Text(info.service)
                .bqFont(22, .bold, relativeTo: .title2)
                .foregroundStyle(BQColor.label)
            Text(attributedTarget)
                .bqFont(13, .semibold, relativeTo: .footnote)
                .foregroundStyle(BQColor.label2)
            if let text = info.text, !text.isEmpty {
                ChatBubble(text: text, color: BQColor.iMessageBlue)
                    .padding(.top, 8)
            }
        }
    }

    private var attributedTarget: AttributedString {
        var target = AttributedString(info.target)
        target.inlinePresentationIntent = .stronglyEmphasized
        return AttributedString("\(lang.t("chat.target")): ") + target
    }

    private var color: Color {
        switch info.service.lowercased() {
        case "whatsapp": BQColor.hex(0x25D366)
        case "signal": BQColor.hex(0x3A76F0)
        default: BQColor.hex(0x2AABEE)
        }
    }
}

/// The square icon + text layout of `.product-card`.
struct ProductCardLayout<Content: View>: View {
    var icon: String
    var gradient: [Color]
    /// False when embedded in a larger card.
    var card = true
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(alignment: .center, spacing: 14))
        let row = layout {
            Image(systemName: icon)
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: gradient, startPoint: .topLeading, endPoint: .bottomTrailing), in: .card(16))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if card {
            row
                .bqCard(radius: Metrics.typeCardRadius)
                .blockGap()
        } else {
            row
        }
    }
}

/// An outgoing message bubble (`.bubble`).
struct ChatBubble: View {
    var text: String
    var color: Color = BQColor.smsGreen

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 36)
            Text(text)
                .bqFont(16, relativeTo: .callout)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(color, in: UnevenRoundedRectangle(topLeadingRadius: 20, bottomLeadingRadius: 20,
                                                              bottomTrailingRadius: 6, topTrailingRadius: 20, style: .continuous))
        }
    }
}

/// Android `intent://` links with a fallback address.
struct IntentCard: View {
    var info: IntentInfo
    @Environment(\.bqLanguage) private var lang

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TypeChip(text: "Android intent", icon: Symbol.type(.intent))
            if let package = info.package {
                KeyValueList(rows: [KeyValue(key: lang.t("intent.package"), value: HostFormat.breakable(package), mono: true)])
            }
            if let fallback = info.fallback {
                SubHeading(text: lang.t("intent.fallback"))
                if let host = info.host {
                    HostText(host: HostFormat.display(host), registrable: info.registrable, size: 24, relativeTo: .title2,
                             regular: .medium, emphasis: .heavy)
                        .foregroundStyle(BQColor.label)
                        .padding(.top, 4)
                        .padding(.bottom, 6)
                }
                MonoText(text: fallback)
            }
        }
        .bqCard(radius: Metrics.typeCardRadius)
        .blockGap()
    }
}
