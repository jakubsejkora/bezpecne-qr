import Foundation

/// The single entry point: payload (+ optional inspection and printed context) → `Analysis`.
///
/// Typical flow: `analyze(code)` immediately after a scan (offline, instant), then — if
/// `analysis.linkTarget` is set — run the link inspector and call `analyze(code, inspection:)`
/// again with its result.
public struct Analyzer: Sendable {
    public let rules: RuleSet
    let gate: LinkGate

    public init(rules: RuleSet = .bundled) {
        self.rules = rules
        self.gate = LinkGate(rules: rules)
    }

    public func analyze(_ code: ScannedCode, inspection: Inspection? = nil, printed: PrintedContext? = nil,
                        options: AnalysisOptions = AnalysisOptions(), now: Date = Date(), id: UUID = UUID()) -> Analysis {
        var parsed = Classifier(rules: rules).parse(code)
        let detector = Detector(rules: rules, now: now)
        var evidence: [Finding] = []
        var consequences = parsed.consequences
        var checks = parsed.checks
        var engine = Analyzer.defaultEngine(parsed.type)
        var completeness = Analyzer.defaultCompleteness(parsed)
        var linkTarget: URL?
        var openURL: URL?
        var scannedHost: String?
        var scannedRegistrable: String?

        // ── Type-specific evidence ───────────────────────────────────────────
        switch parsed.content {
        case .link(let info):
            scannedHost = info.host
            scannedRegistrable = info.registrable
            evidence += detector.hostEvidence(host: info.host, scheme: info.scheme, port: info.port, userinfo: info.userinfo, scanned: true)
            if let inner = info.inner, let innerHost = URL(string: inner)?.asciiHost {
                evidence += detector.hostEvidence(host: DomainKit.asciiHost(innerHost))
            }
            // http links open the HTTPS variant only once the inspection showed it works (below).
            openURL = URL(string: info.scheme == "webcal" ? info.url : Analyzer.openableString(info))
        case .store(let info):
            scannedHost = info.host
            scannedRegistrable = info.registrable
            evidence += detector.hostEvidence(host: info.host)
            openURL = URL(string: info.url)
        case .messenger(let info):
            scannedHost = info.host
            scannedRegistrable = info.registrable
            evidence += detector.hostEvidence(host: info.host)
            openURL = URL(string: info.url)
            if info.kind == "group-invite" {
                consequences.append(Finding("csq.group_invite"))
            } else {
                consequences.append(Finding("csq.opens_chat", ["service": .text(info.service), "target": .text(info.target)]))
            }
        case .appInstall(let info):
            if let host = info.host { evidence += detector.hostEvidence(host: host) }
            openURL = URL(string: code.text.trimmed())
        case .login:
            // tg://, sgnl://, discord.com/ra/… — handed to the app only after a deliberate confirmation.
            // WhatsApp's "2@…" device-link payload is not a URL: there is nothing to open.
            if let url = URL(string: code.text.trimmed()), url.scheme != nil { openURL = url }
        case .email(let info):
            if !info.host.isEmpty { evidence += detector.hostEvidence(host: info.host).filter { !$0.id.hasPrefix("url.transport") } }
            openURL = URL(string: LinkParser.percentEncodeNonASCII(code.text.trimmed()))
        case .intent(let info):
            if let host = info.host { evidence += detector.hostEvidence(host: host) }
            openURL = info.fallback.flatMap(URL.init(string:))
            scannedHost = info.host
            scannedRegistrable = info.registrable
        case .payment(let info):
            evidence += detector.paymentEvidence(info)
        case .sms(let info):
            evidence += detector.smsEvidence(info)
        case .phone(let info):
            evidence += detector.phoneEvidence(info)
        case .dataURI(let info):
            evidence += detector.embeddedHTMLEvidence(info)
        case .contact(var info):
            checks.append(Finding("chk.fields_checked"))
            for url in info.urls {
                guard let p = LinkParser.pieces(url.contains("://") ? url : "https://" + url) else { continue }
                let found = detector.hostEvidence(host: p.host, scheme: p.scheme, port: p.port, userinfo: p.userinfo, scanned: true)
                    .filter { $0.id != "url.transport.http" }
                if !found.isEmpty, info.flaggedUrl == nil {
                    info.flaggedUrl = url
                    info.host = p.host
                    info.registrable = DomainKit.registrable(p.host, privateSuffixes: rules.freeHosts)
                    evidence += found
                }
            }
            let premiumPhones = info.tels.filter { tel in
                let digits = tel.filter { $0.isNumber || $0 == "+" }
                return PhoneFormat.czechNational(digits).map { $0.hasPrefix("90") || $0.hasPrefix("976") } ?? false
            }
            if premiumPhones.isEmpty { checks.append(Finding("chk.no_premium")) }
            parsed.content = .contact(info)
        case .text(let info):
            if let phrase = detector.safeAccountMatch([info.text]) {
                evidence.append(Finding("pay.safe_account_instruction", ["text": .text(phrase)]))
            }
            for link in parsed.embeddedLinks {
                if let p = LinkParser.pieces(link) {
                    evidence += detector.hostEvidence(host: p.host, scheme: p.scheme, port: p.port, userinfo: p.userinfo, scanned: true)
                }
            }
        default:
            break
        }

        // ── Link inspection (gate + network results) ─────────────────────────
        if let target = parsed.inspectTarget {
            let decision = gate.evaluate(target, hop: 0)
            switch decision {
            case .fetch, .upgrade:
                linkTarget = target
                if let inspection {
                    completeness = inspection.completeness ?? completeness
                } else if options.offline {
                    completeness = Completeness(.incomplete, reason: "inc.offline")
                } else if !options.pageFetch {
                    completeness = Completeness(.incomplete, reason: "inc.checks_disabled")
                } else {
                    completeness = Completeness(.incomplete, reason: "inc.pending")
                }
            case .skip(let reason, let manual):
                linkTarget = target
                completeness = Completeness(.skipped, reason: reason, manual: manual)
            case .billingStop(let host):
                linkTarget = target
                if gate.isOperatorHost(host), !gate.isBillingHost(host) {
                    // The scanned link is the operator's own website: explain, don't alarm.
                    completeness = Completeness(.incomplete, reason: "inc.operator_skipped")
                    consequences.append(Finding("csq.operator_site", ["host": .text(host)]))
                } else {
                    completeness = Completeness(.incomplete, reason: "inc.billing_stop")
                    consequences.append(Finding("csq.billing_gateway", ["host": .text(host)]))
                }
            case .notNeeded:
                linkTarget = target
                completeness = Completeness(.notNeeded, reason: Analyzer.notNeededReason(parsed))
            case .refuse(let refusal):
                completeness = Completeness(.incomplete, reason: Analyzer.refusalReason(refusal))
            }
            if var inspection {
                inspection.chain = annotate(inspection.chain)
                let found = detector.inspectionFindings(inspection, scannedHost: scannedHost)
                // Destination hosts (after redirects) get the same lexical rules as the scanned one.
                var hosts: [String] = inspection.chain.compactMap { URL(string: $0.url)?.asciiHost }
                if let final = inspection.final?.host { hosts.append(final.lowercased()) }
                for host in Set(hosts) where host != scannedHost {
                    evidence += detector.hostEvidence(host: host)
                }
                evidence += found.evidence
                consequences += found.consequences
                checks += found.checks
                // The HTTPS variant of an http:// link worked: we checked (and open) that one instead.
                if let first = inspection.chain.first, first.kind == .httpsUpgrade, let status = first.status, status < 400 {
                    evidence.removeAll { $0.id == "url.transport.http" }
                    if case .link(let info) = parsed.content, let upgraded = info.upgraded { openURL = URL(string: upgraded) }
                }
                if inspection.domain?.quad9 == .blocked, inspection.page == nil, inspection.completeness == nil {
                    completeness = Completeness(.notNeeded, reason: "inc.domain_blocked")
                }
            }
        } else if parsed.type == .appInstall {
            completeness = Completeness(.notNeeded, reason: "inc.not_loaded_manifest")
        }

        if let printed {
            evidence += detector.printedFindings(printed, scannedRegistrable: scannedRegistrable,
                                                 finalRegistrable: inspection?.final?.registrable)
        }

        // ── Normalise, choose the engine and score ───────────────────────────
        evidence = Analyzer.dedupe(evidence)
        consequences = Analyzer.dedupe(consequences)
        checks = Analyzer.dedupe(checks)
        evidence.sort { (rules.weights.signals[$0.id]?.weight ?? 0) > (rules.weights.signals[$1.id]?.weight ?? 0) }
        consequences.sort { rules.texts.severity(of: $0.id) < rules.texts.severity(of: $1.id) }
        if parsed.type == .contact || parsed.type == .text, let first = evidence.first {
            engine = Analyzer.engine(forSignal: first.id)
        }
        if parsed.invalid { checks.removeAll { $0.id == "chk.format_only" } }

        let assessment = Scorer(weights: rules.weights).assess(engine: engine, evidence: evidence, completeness: completeness)
        var normalizedInspection = inspection
        if var ins = normalizedInspection {
            ins.chain = annotate(ins.chain)
            // A price with an interval only matters as a phone-bill subscription; otherwise (a shop's
            // own programme, a newspaper offer) it isn't quoted as the page's "small print".
            if ins.page?.offer != nil, !consequences.contains(where: { $0.id == "csq.subscription_charge" }) {
                ins.page?.offer = nil
            }
            normalizedInspection = ins
        }
        return Analysis(id: id, code: code, type: parsed.type, subtype: parsed.subtype, content: parsed.content, engine: engine,
                        sensitivity: parsed.sensitivity, evidence: evidence, consequences: consequences, checks: checks,
                        completeness: completeness, inspection: normalizedInspection, assessment: assessment,
                        invalid: parsed.invalid, decodeOnly: parsed.decodeOnly, linkTarget: linkTarget, openURL: openURL)
    }

    // MARK: Helpers

    /// Schemes that hand a link over to an app store (the inspector ends a clean walk there).
    public static let storeSchemes: Set<String> = ["itms-apps", "itms-appss", "itms", "macappstore", "macappstores", "market"]

    /// The scanned URL with IDN hosts in punycode, so the browser opens what we checked.
    static func openableString(_ info: LinkInfo) -> String {
        LinkParser.pieces(info.url)?.url.absoluteString ?? info.url
    }

    static func defaultEngine(_ type: CodeType) -> EngineKind {
        switch type {
        case .url, .appInstall, .webcal, .store, .messenger, .mailto, .dataURI, .intent: return .url
        case .spd, .epc, .spc, .crypto: return .payment
        case .sms: return .sms
        case .tel: return .phone
        case .contact: return .generic
        default: return .none
        }
    }

    static func engine(forSignal id: String) -> EngineKind {
        if id.hasPrefix("pay.") { return .payment }
        if id.hasPrefix("sms.") { return .sms }
        if id.hasPrefix("phone.") { return .phone }
        return .url
    }

    static func defaultCompleteness(_ parsed: Parsed) -> Completeness {
        if parsed.sensitivity != nil, parsed.type != .wifi { return .notNeeded }
        switch parsed.type {
        case .geo, .jsURI, .dataURI, .appInstall: return .notNeeded
        default: return .complete
        }
    }

    static func notNeededReason(_ parsed: Parsed) -> String {
        if parsed.type == .webcal { return "inc.not_loaded_calendar" }
        if parsed.subtype == .profile { return "inc.not_loaded_profile" }
        return "inc.not_loaded_file"
    }

    static func refusalReason(_ refusal: LinkGate.Refusal) -> String {
        switch refusal {
        case .privateAddress, .localName: return "inc.refused_local"
        case .unsupportedScheme: return "inc.refused_scheme"
        case .ambiguous, .invalid: return "inc.refused_ambiguous"
        }
    }

    static func dedupe(_ findings: [Finding]) -> [Finding] {
        var seen = Set<String>()
        return findings.filter { seen.insert($0.id).inserted }
    }

    /// Marks shortener and curated-relationship hops (the inspector doesn't know these lists), and
    /// an operator website stopped as the scanned link itself.
    func annotate(_ chain: [Hop]) -> [Hop] {
        var out = chain
        if let first = out.first, first.stopped == .billing, let host = URL(string: first.url)?.asciiHost,
           gate.isOperatorHost(host), !gate.isBillingHost(host) {
            out[0].stopped = .operatorSite
        }
        for i in out.indices where out[i].kind == nil {
            guard let host = URL(string: out[i].url)?.asciiHost else { continue }
            if rules.shorteners.contains(host) || rules.qrRedirectors.contains(host) {
                out[i].kind = .shortener
            } else if i > 0, let previous = URL(string: out[i - 1].url)?.asciiHost,
                      rules.parking.contains(where: { city in city.relationships.contains { $0.first == previous && $0.last == host } }) {
                out[i].kind = .curatedRelationship
            }
        }
        return out
    }
}
