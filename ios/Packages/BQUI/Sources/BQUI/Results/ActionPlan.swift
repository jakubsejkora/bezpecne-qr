import BQCore
import Foundation

/// Which buttons a result offers (cards.js `actions()`), as data so it can be tested.
/// "Nejdřív vysvětli, co se stane. Pak nabídni další krok."
struct ActionPlan {
    enum Style: Equatable { case primary, secondary, plain, disabled }

    enum Behavior: Equatable {
        case perform(ResultAction)
        /// Opens "Výtah ze stránky" inside the sheet.
        case pageExtract
        case none
    }

    struct Button: Identifiable, Equatable {
        var id: String
        var title: String
        var icon: String?
        var style: Style
        var behavior: Behavior
    }

    /// What a hold-to-confirm button does once confirmed.
    enum HoldKind: Equatable { case open, proceed, call, sms, install, subscribe }

    /// "Podržet 2 s …" with its accessible alternative ("Nebo otevřít přes potvrzení").
    struct Hold: Identifiable, Equatable {
        var id: String
        var title: String
        var kind: HoldKind
        var action: ResultAction
        var alternativeTitle: String
        var confirmTitle: String
        var confirmMessage: String?
        var confirmButton: String
    }

    enum Item: Identifiable, Equatable {
        case button(Button)
        /// Two buttons side by side (stacked at accessibility sizes).
        case row([Button])
        case hold(Hold)
        case hint(String)

        var id: String {
            switch self {
            case .button(let b): b.id
            case .row(let bs): bs.map(\.id).joined(separator: "+")
            case .hold(let h): "hold-" + h.id
            case .hint(let t): "hint-" + t
            }
        }
    }

    var items: [Item]

    init(_ a: Analysis, verdict: Verdict, texts: FindingTexts, lang: Language, contactSaved: Bool, capabilities: ResultCapabilities = .app) {
        var out: [Item] = []
        let t = { (key: String) in lang.t(key) }
        let danger = a.band == .danger
        let caution = a.band == .caution
        let critical = verdict.isAlert
        let hasPage = a.inspection?.page != nil
        let topConsequence = texts.consequences.first?.texts.text

        func button(_ id: String, _ title: String, _ style: Style, _ icon: String? = nil, _ behavior: Behavior) -> Item {
            .button(Button(id: id, title: title, icon: icon, style: style, behavior: behavior))
        }
        let back = button("back", t("act.back"), .primary, nil, .perform(.backToScanning))
        let understand = button("close", t("act.understand"), .primary, nil, .perform(.close))

        func hold(_ id: String, _ titleKey: String, _ kind: HoldKind, _ action: ResultAction) -> Item {
            let alternative: String
            let confirmTitle: String
            let confirmButton: String
            var message = topConsequence
            switch kind {
            case .open:
                alternative = t("act.holdAlt"); confirmTitle = t("alert.openTitle"); confirmButton = t("alert.open")
                message = t("alert.openText")
            case .proceed:
                alternative = t("act.holdAltContinue"); confirmTitle = t("confirm.continueTitle"); confirmButton = t("confirm.continueButton")
            case .call:
                alternative = t("act.holdAltCall"); confirmTitle = t("confirm.callTitle"); confirmButton = t("confirm.callButton")
            case .sms:
                alternative = t("act.holdAltSms"); confirmTitle = t("confirm.smsTitle"); confirmButton = t("confirm.smsButton")
            case .install:
                alternative = t("act.holdAltInstall"); confirmTitle = t("confirm.installTitle"); confirmButton = t("confirm.installButton")
            case .subscribe:
                alternative = t("act.holdAltSubscribe"); confirmTitle = t("confirm.subscribeTitle"); confirmButton = t("confirm.subscribeButton")
            }
            return .hold(Hold(id: id, title: t(titleKey), kind: kind, action: action, alternativeTitle: alternative,
                              confirmTitle: confirmTitle, confirmMessage: message, confirmButton: confirmButton))
        }

        let openURL = a.openURL

        switch a.content {
        case .link, .store, .messenger:
            if a.opensOriginalLink { out.append(.hint(t("destination.originalActionNote"))) }
            if a.type == .webcal {
                out.append(back)
                if let url = openURL { out.append(hold("subscribe", "act.subscribe", .subscribe, .open(url))) }
                break
            }
            let openTitle: String
            var openIcon: String?
            switch a.content {
            case .store: openTitle = t("act.appStore")
            case .messenger(let m): openTitle = lang.t("act.openService", ["service": m.service])
            default: openTitle = t(a.opensOriginalLink ? "destination.openOriginal" : "act.openWeb"); openIcon = "safari"
            }
            guard let url = openURL else { out.append(back); break }
            let open = Behavior.perform(.open(url))
            if a.subtype == .profile {
                out.append(back)
                out.append(hold("install", "act.install", .install, .open(url)))
            } else if a.subtype == .download {
                out.append(back)
                out.append(button("open", t("act.openAnyway"), .plain, nil, open))
            } else if danger {
                out.append(back)
                out.append(hold("open", "act.hold", .open, .open(url)))
            } else if critical {
                out.append(back)
                out.append(hold("open", "act.continueHold", .proceed, .open(url)))
            } else if caution {
                out.append(hasPage ? button("preview", t("act.preview"), .primary, "eye", .pageExtract) : back)
                out.append(button("open", t(a.opensOriginalLink ? "destination.openOriginalAnyway" : "act.openAnyway"), .secondary, nil, open))
            } else if a.band == .incomplete {
                out.append(back)
                out.append(button("open", t(a.opensOriginalLink ? "destination.openOriginalAnyway" : "act.openAnyway"), .secondary, nil, open))
            } else {
                out.append(button("open", openTitle, .primary, openIcon, open))
                if hasPage { out.append(button("preview", t("act.preview"), .secondary, "eye", .pageExtract)) }
            }

        case .appInstall:
            out.append(back)
            if let url = openURL ?? URL(string: a.code.text) {
                out.append(hold("install", "act.install", .install, .open(url)))
            }

        case .payment(let p):
            Self.paymentActions(&out, a, account: p.domestic ?? p.iban, accountKind: p.domestic == nil ? .iban : .account,
                                amount: p.amount, vs: p.vs, blocked: a.invalid || p.amountRaw != nil, lang: lang, back: back)

        case .transfer(let p):
            Self.paymentActions(&out, a, account: p.iban, accountKind: .iban, amount: p.amount, vs: nil,
                                blocked: a.invalid, lang: lang, back: back)

        case .invoice:
            out.append(button("save-qr", t("act.saveQR"), .primary, "square.and.arrow.down", .perform(.saveQRImage)))

        case .crypto(let c):
            let address = c.recipient ?? c.address ?? Self.stripScheme(a.code.text)
            out.append(button("copy-address", t("act.copyAddress"), .secondary, "doc.on.doc", .perform(.copy(address, .cryptoAddress))))
            out.append(back)

        case .payBySquare:
            out.append(button("close", t("act.close"), .primary, nil, .perform(.close)))

        case .sms(let s):
            let action = ResultAction.sms(number: s.number, body: s.body)
            if s.premium != nil {
                out.append(back)
                out.append(hold("sms", "act.holdSms", .sms, action))
            } else {
                out.append(button("sms", t("act.prepareSms"), .primary, "message", .perform(action)))
            }

        case .phone(let p):
            if p.premium != nil || p.mmi != nil || !a.consequences.isEmpty {
                out.append(back)
                out.append(hold("call", "act.holdCall", .call, .call(p.number)))
            } else {
                out.append(button("call", t("act.call"), .primary, "phone", .perform(.call(p.number))))
            }

        case .email(let e):
            let mail = Self.mailURL(e) ?? openURL
            if caution || danger {
                out.append(back)
                if let mail { out.append(button("mail", t("act.compose"), .secondary, nil, .perform(.mail(mail)))) }
            } else if let mail {
                out.append(button("mail", t("act.compose"), .primary, "envelope", .perform(.mail(mail))))
            }

        case .contact:
            if contactSaved {
                out.append(button("contact-saved", t("act.contactSaved"), .disabled, Symbol.check, .none))
            } else {
                out.append(button("add-contact", t("act.addContact"), .primary, "person.crop.circle.badge.plus", .perform(.addContact)))
            }

        case .wifi(let w):
            out.append(button("join", t("act.join"), w.security == "open" ? .secondary : .primary, "wifi", .perform(.joinWiFi)))
            if let password = w.password {
                out.append(button("copy-pw", t("act.copyPw"), .secondary, "doc.on.doc", .perform(.copy(password, .password))))
            }

        case .event:
            out.append(button("add-event", t("act.addEvent"), .primary, "calendar.badge.plus", .perform(.addEvent)))

        case .geo(let g):
            out.append(button("maps", t("act.maps"), .primary, "map",
                              .perform(.openMaps(latitude: g.lat, longitude: g.lon, label: g.label))))

        case .otp:
            out.append(understand)
            out.append(hold("passwords", "act.continueHold", .proceed, .openInPasswords))

        case .login:
            out.append(understand)
            if let url = Self.handOffURL(a) {
                out.append(hold("login", "act.continueHold", .proceed, .open(url)))
            }

        case .otpMigration, .seed, .walletConnect, .healthCertificate, .fido:
            out.append(understand)

        case .dataURI, .script, .intent:
            out.append(back)
            out.append(button("copy-text", t("act.copyText"), .secondary, "doc.on.doc", .perform(.copy(a.code.text, .text))))

        case .text, .emvco, .gs1, .boardingPass:
            out.append(button("copy-text", t("act.copyText"), .secondary, "doc.on.doc", .perform(.copy(a.code.text, .text))))
            out.append(button("close", t("act.close"), .primary, nil, .perform(.close)))
        }
        if capabilities == .imageExtension {
            var filtered: [Item] = []
            func allowed(_ b: Button) -> Bool {
                if case .perform(let action) = b.behavior { return capabilities.supports(action) }
                return true
            }
            for item in out {
                switch item {
                case .button(var b):
                    if allowed(b) {
                        if case .perform(.backToScanning) = b.behavior { b.title = t("act.close") }
                        filtered.append(.button(b))
                    }
                case .row(let buttons):
                    let kept = buttons.filter(allowed); if !kept.isEmpty { filtered.append(.row(kept)) }
                case .hold(let h): if capabilities.supports(h.action) { filtered.append(item) }
                case .hint: break
                }
            }
            if !a.isSensitive, a.openURL != nil {
                filtered.append(button("copy-link", t("destination.copyOriginal"), .secondary, "doc.on.doc", .perform(.copy(a.code.text, .text))))
                if let target = a.linkResolution?.resolved {
                    filtered.append(button("copy-destination", t("destination.copyResolved"), .secondary, "doc.on.doc", .perform(.copy(target.url, .text))))
                }
            }
            filtered.append(.hint(t("share.continueApp")))
            if !filtered.contains(where: { if case .button(let b) = $0, b.style == .primary { return true }; return false }) {
                filtered.insert(button("close-extension", t("act.close"), .primary, nil, .perform(.close)), at: 0)
            }
            out = filtered
        }
        items = out
    }

    private static func paymentActions(_ out: inout [Item], _ a: Analysis, account: String, accountKind: CopyKind,
                                       amount: String?, vs: String?, blocked: Bool, lang: Language, back: Item) {
        if blocked {
            out.append(.button(Button(id: "blocked", title: lang.t("act.blocked"), icon: Symbol.danger, style: .disabled, behavior: .none)))
            out.append(.button(Button(id: "rescan", title: lang.t("act.rescan"), icon: nil, style: .primary, behavior: .perform(.backToScanning))))
            return
        }
        if a.band == .danger {
            out.append(back)
            return
        }
        var row = [Button(id: "copy-account", title: lang.t("act.copyAccount"), icon: "doc.on.doc", style: .secondary,
                          behavior: .perform(.copy(account, accountKind)))]
        if let amount, let copyable = copyableAmount(amount, lang) {
            row.append(Button(id: "copy-amount", title: lang.t("act.copyAmount"), icon: "doc.on.doc", style: .secondary,
                              behavior: .perform(.copy(copyable, .amount))))
        }
        out.append(.row(row))
        if let vs {
            out.append(.button(Button(id: "copy-vs", title: lang.t("act.copyVS"), icon: "doc.on.doc", style: .secondary,
                                      behavior: .perform(.copy(vs, .variableSymbol)))))
        }
        let caution = a.band == .caution
        out.append(.button(Button(id: "save-qr", title: lang.t("act.saveQR"), icon: "square.and.arrow.down",
                                  style: caution ? .secondary : .primary, behavior: .perform(.saveQRImage))))
        out.append(.hint(lang.t("act.saveQRHint")))
        if caution { out.insert(back, at: 0) }
    }

    /// "480.50" → "480,50" (cs) / "480.50" (en); whole amounts without decimals. No grouping, so
    /// banking apps accept the pasted value.
    static func copyableAmount(_ value: String, _ lang: Language) -> String? {
        guard let decimal = Decimal(string: value, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
        let formatter = NumberFormatter()
        formatter.locale = lang.locale
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        let whole = decimal == Decimal(Int(truncating: decimal as NSDecimalNumber))
        formatter.minimumFractionDigits = whole ? 0 : 2
        formatter.maximumFractionDigits = 8
        return formatter.string(from: decimal as NSDecimalNumber)
    }

    /// A `mailto:` URL built from the parsed fields (also works for MATMSG codes).
    static func mailURL(_ e: EmailInfo) -> URL? {
        var c = URLComponents()
        c.scheme = "mailto"
        c.path = e.to
        var query: [URLQueryItem] = []
        if let cc = e.cc, !cc.isEmpty { query.append(URLQueryItem(name: "cc", value: cc)) }
        if let s = e.subject, !s.isEmpty { query.append(URLQueryItem(name: "subject", value: s)) }
        if let b = e.body, !b.isEmpty { query.append(URLQueryItem(name: "body", value: b)) }
        c.queryItems = query.isEmpty ? nil : query
        return c.url
    }

    /// For login / device-link codes: the URL to hand to the owning app, if the code is one.
    static func handOffURL(_ a: Analysis) -> URL? {
        if let url = a.openURL { return url }
        guard let url = URL(string: a.code.text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme, !scheme.isEmpty else { return nil }
        return url
    }

    static func stripScheme(_ s: String) -> String {
        guard let colon = s.firstIndex(of: ":") else { return s }
        return String(s[s.index(after: colon)...])
    }
}
