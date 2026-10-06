import BQCore
import Foundation
import Testing
@testable import BQUI

/// The result logic ported from prototype/js/cards.js: verdict header, actions and safety rules.
@MainActor
struct ResultLogicTests {
    private func parts(_ id: String, _ lang: Language = .cs) -> (Analysis, FindingTexts, Verdict, ActionPlan) {
        let a = Corpus.analysis(id)
        let texts = FindingTexts(a, lang)
        let verdict = Verdict(a, texts, lang)
        return (a, texts, verdict, ActionPlan(a, verdict: verdict, texts: texts, lang: lang, contactSaved: false))
    }

    @Test("Header tones follow headerModel", arguments: [
        ("url-parking-fake", Tone.danger), ("url-menu-shortener", .safe), ("url-free-hosting", .caution),
        ("url-offline-menu", .incomplete), ("tel-mmi-forward", .alert), ("sms-premium-ano", .alert),
        ("otpauth-migration", .alert), ("login-whatsapp", .alert), ("wifi-wpa2", .info), ("vcard-business", .info),
        ("geo-point", .info), ("spd-basic", .safe), ("url-dcb-billing-stop", .alert),
    ])
    func headerTone(_ id: String, _ tone: Tone) {
        #expect(parts(id).2.tone == tone)
    }

    @Test func informationalChips() {
        #expect(parts("wifi-wpa2").2.chip == Verdict.VerdictChip(tone: .info, text: "Bez varovných znaků"))
        #expect(parts("wifi-open").2.chip?.tone == .caution)
    }

    @Test func dangerSubtitleStatesTheConsequence() {
        let v = parts("url-parking-fake").2
        #expect(v.title == "Nebezpečné")
        #expect(v.subtitle?.contains("EasyPark") == true)
    }

    @Test("VoiceOver hears the verdict once, e.g. “Riziko 99 ze 100, nebezpečné”")
    func announcement() {
        let (a, _, v, _) = parts("url-parking-fake")
        #expect(v.announcement(a, .cs).hasPrefix("Riziko \(a.assessment.score!) ze 100, nebezpečné"))
        let (w, _, wv, _) = parts("wifi-wpa2")
        #expect(wv.announcement(w, .cs) == "Wi‑Fi síť, Bez varovných znaků")
    }

    @Test("Every hold-to-confirm has an accessible alternative and a confirmation", arguments: Corpus.ids)
    func holdsHaveAlternatives(_ id: String) {
        for case .hold(let hold) in parts(id).3.items {
            #expect(!hold.alternativeTitle.isEmpty)
            #expect(!hold.confirmTitle.isEmpty)
            #expect(!hold.confirmButton.isEmpty)
        }
    }

    @Test("Dangerous results never offer a plain “open” button", arguments: Corpus.ids)
    func dangerNeverOpensDirectly(_ id: String) {
        let (a, _, v, plan) = parts(id)
        guard a.band == .danger || v.isAlert else { return }
        for item in plan.items {
            let buttons: [ActionPlan.Button] = switch item {
            case .button(let b): [b]
            case .row(let bs): bs
            default: []
            }
            for b in buttons {
                if case .perform(.open) = b.behavior { Issue.record("\(id) offers \(b.id) without hold-to-confirm") }
                if case .perform(.call) = b.behavior { Issue.record("\(id) offers \(b.id) without hold-to-confirm") }
                if case .perform(.sms) = b.behavior { Issue.record("\(id) offers \(b.id) without hold-to-confirm") }
            }
        }
    }

    @Test("Extension actions stay within host capabilities", arguments: Corpus.ids)
    func extensionCapabilities(_ id: String) {
        let a = Corpus.analysis(id), texts = FindingTexts(Corpus.analysis(id), .en)
        let plan = ActionPlan(a, verdict: Verdict(a, texts, .en), texts: texts, lang: .en, contactSaved: false, capabilities: .imageExtension)
        for item in plan.items {
            let buttons: [ActionPlan.Button] = switch item { case .button(let b): [b]; case .row(let row): row; default: [] }
            for button in buttons {
                if case .perform(let action) = button.behavior { #expect(ResultCapabilities.imageExtension.supports(action)) }
            }
            if case .hold(let hold) = item { #expect(ResultCapabilities.imageExtension.supports(hold.action)) }
        }
        if a.isSensitive { #expect(!plan.items.contains { $0.id == "copy-link" }) }
    }

    @Test func actionsMatchThePrototype() {
        func ids(_ id: String) -> [String] {
            // The original-route notice adds context, not another action.
            parts(id).3.items.filter { $0.id != "hint-" + L10n.t("destination.originalActionNote", .cs) }.map(\.id)
        }
        #expect(ids("url-parking-fake") == ["back", "hold-open"])
        #expect(ids("url-menu-shortener") == ["open", "preview"])
        #expect(ids("url-parking-praha-official") == ["open", "preview"])
        #expect(ids("url-offline-menu") == ["back", "open"])
        #expect(ids("url-dcb-billing-stop") == ["back", "hold-open"])
        #expect(ids("spd-basic") == ["copy-account+copy-amount", "copy-vs", "save-qr", "hint-" + L10n.t("act.saveQRHint", .cs)])
        #expect(ids("spd-state-claim").first == "back")
        #expect(ids("spd-invalid-iban") == ["blocked", "rescan"])
        #expect(ids("malformed-spd") == ["blocked", "rescan"])
        #expect(ids("sms-premium-ano") == ["back", "hold-sms"])
        #expect(ids("tel-mmi-forward") == ["back", "hold-call"])
        #expect(ids("tel-normal") == ["call"])
        #expect(ids("wifi-wpa2") == ["join", "copy-pw"])
        #expect(ids("otpauth-setup") == ["close", "hold-passwords"])
        #expect(ids("login-whatsapp") == ["close"])
        #expect(ids("login-telegram") == ["close", "hold-login"])
        #expect(ids("url-webcal") == ["back", "hold-subscribe"])
        #expect(ids("url-mobileconfig") == ["back", "hold-install"])
        #expect(ids("url-itms-services") == ["back", "hold-install"])
        #expect(ids("vcard-business") == ["add-contact"])
    }

    @Test func copiedValues() {
        let plan = parts("spd-basic").3
        guard case .row(let row) = plan.items.first else { Issue.record("no copy row"); return }
        #expect(row[0].behavior == .perform(.copy("19-2000145399/0800", .account)))
        #expect(row[1].behavior == .perform(.copy("480,50", .amount)))
        #expect(ActionPlan.copyableAmount("12100.00", .cs) == "12100")
        #expect(ActionPlan.copyableAmount("480.5", .en) == "480.50")
        guard case .button(let pw) = parts("wifi-wpa2").3.items.last else { Issue.record("no password copy"); return }
        #expect(pw.behavior == .perform(.copy("kafe-2026", .password)))
    }

    @Test("Opening and copying distinguish the inspected destination from the original route")
    func destinationActionLabels() throws {
        let (resolved, _, _, resolvedPlan) = parts("url-menu-shortener")
        let (unresolved, _, _, originalPlan) = parts("url-offline-menu")
        guard case .button(let open) = resolvedPlan.items.first else { Issue.record("missing open action"); return }
        #expect(open.title == L10n.t("act.openWeb", .cs))
        #expect(open.behavior == .perform(.open(try #require(resolved.openURL))))
        #expect(resolved.openURL?.host == resolved.resolvedHost)
        #expect(originalPlan.items.contains(.hint(L10n.t("destination.originalActionNote", .cs))))
        let buttons = originalPlan.items.compactMap { if case .button(let b) = $0 { return b }; return nil }
        #expect(buttons.contains { $0.title == L10n.t("destination.openOriginalAnyway", .cs) && $0.behavior == .perform(.open(unresolved.openURL!)) })
        let texts = FindingTexts(resolved, .cs)
        let extensionPlan = ActionPlan(resolved, verdict: Verdict(resolved, texts, .cs), texts: texts, lang: .cs,
                                       contactSaved: false, capabilities: .imageExtension)
        #expect(extensionPlan.items.contains { $0.id == "copy-destination" })
        #expect(extensionPlan.items.contains { $0.id == "copy-link" })
    }

    @Test func mailURLIsBuiltFromFields() throws {
        guard case .email(let e) = Corpus.analysis("mailto-lookalike").content else { Issue.record("not e-mail"); return }
        let url = try #require(ActionPlan.mailURL(e))
        #expect(url.scheme == "mailto")
        #expect(url.absoluteString.hasPrefix("mailto:podpora@csob-overeni.top?subject="))
    }

    @Test("Sensitive codes never show their raw content", arguments: Corpus.ids)
    func sensitiveContentHidden(_ id: String) {
        let a = Corpus.analysis(id)
        guard a.isSensitive else { return }
        // The details box renders `sec.rawHidden` instead of `code.text` for these.
        #expect(L10n.t("sec.rawHidden", .cs).contains("skryt"))
        #expect(!ResultContent.showsStickerTip(a, fromCamera: true))
    }

    @Test func stickerTip() {
        #expect(ResultContent.showsStickerTip(Corpus.analysis("url-parking-fake"), fromCamera: true))
        #expect(!ResultContent.showsStickerTip(Corpus.analysis("url-parking-fake"), fromCamera: false))
        #expect(!ResultContent.showsStickerTip(Corpus.analysis("url-menu-shortener"), fromCamera: true))
        #expect(ResultContent.showsStickerTip(Corpus.analysis("spd-foreign-parking"), fromCamera: true))
    }

    @Test func checkingSteps() {
        let m = ResultModel(analysis: Corpus.pendingAnalysis("url-menu-shortener"), fromCamera: true, language: .cs)
        #expect(m.isChecking)
        m.step = .address
        m.step = .domain
        m.step = .redirects(1)
        m.step = .redirects(2)
        m.step = .page
        #expect(m.stepHistory == [.address, .domain, .redirects(2), .page])
        #expect(CheckingView.label(for: .address, m.analysis, .cs) == "Rozbaluji zkrácený odkaz…")
        #expect(CheckingView.label(for: .redirects(2), m.analysis, .cs) == "Sleduji přesměrování — zatím 2")
        m.isChecking = false
        m.isChecking = true
        #expect(m.stepHistory == [.page], "a new check starts from the current step")
    }

    @Test("A reused model forgets revealed secrets when a different code arrives")
    func resetsStateForANewCode() {
        let m = ResultModel(analysis: Corpus.analysis("wifi-wpa2"), fromCamera: true, language: .cs)
        m.revealPassword = true
        m.detailsExpanded = true
        m.analysis = Corpus.analysis("wifi-wpa2")          // the same code re-analysed: keep
        #expect(m.revealPassword && m.detailsExpanded)
        m.analysis = Corpus.analysis("wifi-hidden")        // a different code: reset
        #expect(!m.revealPassword && !m.detailsExpanded)
        m.route = .pageExtract
        m.analysis = Corpus.analysis("url-dcb-subscription")
        #expect(m.route == .result)
    }

    @Test func handlerResults() async {
        final class Handler: ResultActionHandler {
            var performed: [ResultAction] = []
            func perform(_ action: ResultAction, for analysis: Analysis) async -> ActionResult {
                performed.append(action)
                return action == .addContact ? .done(toast: "Uloženo") : .failed("")
            }
        }
        let handler = Handler()
        let m = ResultModel(analysis: Corpus.analysis("vcard-business"), fromCamera: false, language: .cs)
        m.handler = handler
        m.perform(.addContact)
        for _ in 0..<50 where handler.performed.isEmpty || m.toast == nil { await Task.yield() }
        #expect(handler.performed == [.addContact])
        #expect(m.contactSaved)
        #expect(m.celebration == 1)
        #expect(m.toast?.text == "Uloženo")
        m.finish(.joinWiFi, .failed(""))
        #expect(m.toast?.isError == true)
        #expect(m.toast?.text == L10n.t("error.generic", .cs))
    }

    @Test("No UI string is missing for any corpus sample", arguments: [Language.cs, .en])
    func noMissingStrings(_ lang: Language) {
        L10n.missingKeys.removeAll()
        for id in Corpus.ids {
            let a = Corpus.analysis(id)
            let texts = FindingTexts(a, lang)
            let verdict = Verdict(a, texts, lang)
            _ = ActionPlan(a, verdict: verdict, texts: texts, lang: lang, contactSaved: false)
            _ = verdict.announcement(a, lang)
            if case .link(let info) = a.content { _ = JourneyView.stops(a, info, lang) }
        }
        let missing = L10n.missingKeys.subtracting(["does.not.exist"])
        #expect(missing.isEmpty, "missing: \(missing.sorted())")
    }
}
