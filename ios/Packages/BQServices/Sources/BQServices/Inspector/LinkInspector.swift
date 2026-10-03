import BQCore
import Foundation

/// Inspects a scanned link before anything opens: walks its redirects itself (no cookies, no
/// JavaScript, no identity), stops where the eligibility gate says so, reads what the landing page
/// asks for and runs the public domain checks — all within fixed budgets. Never throws; every
/// outcome is an `Inspection`.
///
/// Rules applied on every hop (the scanned link is hop 0):
/// - `LinkGate.evaluate` runs before each request and is obeyed: `http` links are upgraded to
///   HTTPS (cleartext is never loaded), tokens and sign-in paths are skipped, private/local
///   targets are refused and operator / carrier-billing hosts are never contacted.
/// - Each request goes through `HTTPTransport` (`SafeFetcher`): one bound, vetted connection.
/// - Redirects come from `Location` (301/302/303/307/308), `<meta http-equiv="refresh">` with a
///   delay of at most 10 s, and the inner URL of a known open redirector that shows a page.
///   JavaScript redirects are noted as candidates only.
public actor LinkInspector {
    private let transport: any HTTPTransport
    private let vetter: any HostVetting
    private let domainChecker: any DomainChecking
    private let reachability: any NetworkReachability
    private let rules: RuleSet
    private let gate: LinkGate
    private let analyzer: PageAnalyzer

    /// Meta refreshes up to this delay are followed as redirects.
    static let maxRefreshDelay: Double = 10
    /// How long the walk waits for Quad9 before loading the scanned link anyway.
    static let quad9Wait: Duration = .milliseconds(2500)

    public init(transport: any HTTPTransport = SafeFetcher(), vetter: any HostVetting = AddressVetter(),
                domainChecker: any DomainChecking = DomainChecker(), reachability: any NetworkReachability = SystemReachability(),
                rules: RuleSet = .bundled) {
        self.transport = transport
        self.vetter = vetter
        self.domainChecker = domainChecker
        self.reachability = reachability
        self.rules = rules
        gate = LinkGate(rules: rules)
        analyzer = PageAnalyzer(rules: rules)
    }

    /// - Parameters:
    ///   - url: the scanned link.
    ///   - manualOverride: the user asked for a one-shot inspection of a link skipped for a
    ///     sign-in keyword (never overrides tokens, billing stops or refusals).
    ///   - progress: called as steps begin; may be called from any thread.
    public func inspect(_ url: URL, options: InspectionOptions = InspectionOptions(), manualOverride: Bool = false,
                        progress: @escaping @Sendable (InspectionProgress) -> Void = { _ in }) async -> Inspection {
        let deadline = ContinuousClock.now + options.overallDeadline
        guard options.pageFetch || options.domainChecks else {
            return Inspection(completeness: Completeness(.incomplete, reason: IncompleteReason.checksDisabled))
        }

        let first = gate.evaluate(url, hop: 0, manualOverride: manualOverride)
        // Refused links (private or local addresses, other schemes, ambiguous URLs): nothing leaves the device.
        if case .refuse(let refusal) = first {
            return Inspection(chain: [Hop(url: LinkInspector.display(url), stopped: .gate)],
                              completeness: Completeness(.incomplete, reason: IncompleteReason.refused(refusal)))
        }
        let scannedHost = LinkInspector.host(of: first, fallback: url)
        progress(.checkingAddress(shortLink: scannedHost.map(isShortener) ?? false))

        if await reachability.isOffline() {
            return Inspection(completeness: Completeness(.incomplete, reason: IncompleteReason.offline))
        }

        // The scanned name is resolved and vetted before it may leave the device: a name that points
        // into a private network (split DNS, e.g. printer.company.cz → 10.0.0.5) is never sent to
        // Quad9 or a registry, and never loaded — also when only the domain checks are on.
        var checkDomain = options.domainChecks
        if let host = scannedHost {
            switch await vetting(host, deadline: .earliest(deadline, .now + options.hopDeadline)) {
            case .publicName:
                break
            case .privateName:
                return Inspection(chain: [Hop(url: LinkInspector.display(url), stopped: .gate)],
                                  completeness: Completeness(.incomplete, reason: IncompleteReason.refusedLocal))
            case .undetermined:
                checkDomain = false
            }
        }

        // Public checks for the scanned link's domain start now and run alongside everything else.
        let checks = checkDomain
            ? scannedHost.flatMap(domainTarget).map { ScannedChecks($0, checker: domainChecker, deadline: deadline) }
            : nil
        defer { checks?.cancel() }
        if checks != nil { progress(.checkingDomain) }

        // The gate stopped the scanned link itself: only the domain checks run.
        switch first {
        case .skip(let reason, let manual):
            return Inspection(chain: [Hop(url: LinkInspector.display(url), stopped: .gate)], domain: await checks?.facts(),
                              completeness: Completeness(.skipped, reason: reason, manual: manual))
        case .notNeeded:
            return Inspection(chain: [Hop(url: LinkInspector.display(url), stopped: .gate)], domain: await checks?.facts(),
                              completeness: Completeness(.notNeeded, reason: IncompleteReason.notLoaded(url)))
        case .billingStop(let host):
            // The operator's own website gets its own explanation (as in BQCore's Analyzer); a billing
            // gateway is a billing stop.
            let reason = gate.isOperatorHost(host) && !gate.isBillingHost(host) ? IncompleteReason.operatorSkipped : IncompleteReason.billingStop
            return Inspection(chain: [Hop(url: LinkInspector.display(url), stopped: .billing)], domain: await checks?.facts(),
                              completeness: Completeness(.incomplete, reason: reason))
        case .fetch, .upgrade, .refuse:
            break
        }
        guard options.pageFetch else {
            return Inspection(domain: await checks?.facts(), completeness: Completeness(.incomplete, reason: IncompleteReason.checksDisabled))
        }

        // A protective-DNS block on the scanned domain: the page is not loaded at all.
        if await checks?.verdict() == .blocked {
            return Inspection(domain: await checks?.facts(), completeness: Completeness(.notNeeded, reason: IncompleteReason.domainBlocked))
        }

        var walk = Walk(start: url, firstDecision: first, options: options, deadline: deadline, manualOverride: manualOverride)
        await run(&walk, progress: progress)
        let domain = await destinationFacts(walk.destination, scanned: checks, deadline: deadline)
        return Inspection(chain: walk.chain, final: walk.final, page: walk.page, domain: domain, completeness: walk.completeness)
    }

    /// Domain facts for the furthest destination the walk reached or tried to reach (the scanned
    /// domain when the walk stayed there or got nowhere).
    private func destinationFacts(_ destination: URL?, scanned: ScannedChecks?, deadline: Deadline) async -> DomainFacts? {
        guard let scanned, !Task.isCancelled else { return nil }
        guard let host = destination?.asciiHost, let target = domainTarget(host), target.host != scanned.target.host,
              await vetting(target.host, deadline: deadline) == .publicName else {
            return await scanned.facts()
        }
        let checker = domainChecker
        if target.registrable == scanned.target.registrable {
            // Same domain, another host: the registration is shared, the Quad9 verdict is per host.
            return await scanned.facts(verdict: await checker.quad9(target.host, deadline: deadline))
        }
        scanned.cancelRegistration()
        async let verdict = checker.quad9(target.host, deadline: deadline)
        async let registration = target.sharedHosting ? RDAPRegistration() : checker.registration(target.registrable, deadline: deadline)
        let (v, r) = await (verdict, registration)
        return DomainFacts(name: target.registrable, registered: r.registered, registry: r.registry, quad9: v)
    }

    private enum NameVetting {
        case publicName, privateName, undetermined
    }

    /// Whether a name may be sent to the public checks: only when it resolved, through the system
    /// resolver, to vetted public addresses. Private answers keep it on the device and end the
    /// inspection; any other outcome (no such name, resolver failure, timeout, unverifiable answers)
    /// keeps it on the device too.
    private func vetting(_ host: String, deadline: Deadline) async -> NameVetting {
        do {
            _ = try await vetter.vet(host, deadline: deadline)
            return .publicName
        } catch {
            return error == .nonPublicAddress ? .privateName : .undetermined
        }
    }

    // MARK: - The redirect walk

    private struct Walk {
        var current: URL
        var decision: LinkGate.Decision?
        let options: InspectionOptions
        let deadline: Deadline
        let manualOverride: Bool

        var hopIndex = 0
        var chain: [Hop] = []
        var visited = Set<String>()
        var requests = 0
        var bytesLeft: Int
        var redirects = 0
        var previousHost: String?
        var final: Endpoint?
        var page: PageFacts?
        var completeness = Completeness.complete
        /// Set as soon as any response body (or page analysis) along the walk was incomplete: the
        /// inspection can't end complete after that, wherever the walk goes next.
        var degraded: Completeness?
        /// The last URL we contacted or tried to contact (for the domain checks).
        var destination: URL?

        init(start: URL, firstDecision: LinkGate.Decision, options: InspectionOptions, deadline: Deadline, manualOverride: Bool) {
            current = start
            decision = firstDecision
            self.options = options
            self.deadline = deadline
            self.manualOverride = manualOverride
            bytesLeft = options.maxTotalBytes
        }

        mutating func stop(_ hop: Hop, _ completeness: Completeness) {
            chain.append(hop)
            self.completeness = completeness.state == .complete ? degraded ?? completeness : completeness
        }

        /// Records the first reason the walk can no longer end complete.
        mutating func degrade(_ reason: String) {
            if degraded == nil { degraded = Completeness(.incomplete, reason: reason) }
        }
    }

    private func run(_ walk: inout Walk, progress: @Sendable (InspectionProgress) -> Void) async {
        while true {
            let decision = walk.decision ?? gate.evaluate(walk.current, hop: walk.hopIndex, manualOverride: walk.manualOverride)
            walk.decision = nil
            let display = LinkInspector.display(walk.current)

            let target: URL
            var upgraded = false
            switch decision {
            case .fetch(let u):
                target = LinkInspector.withoutFragment(u)
            case .upgrade(let u):
                target = LinkInspector.withoutFragment(u)
                upgraded = true
            case .billingStop:
                return walk.stop(Hop(url: display, stopped: .billing), Completeness(.incomplete, reason: IncompleteReason.billingStop))
            case .skip(let reason, let manual):
                return walk.stop(Hop(url: display, stopped: .gate), Completeness(.skipped, reason: reason, manual: manual))
            case .notNeeded:
                return walk.stop(Hop(url: display, stopped: .gate), Completeness(.notNeeded, reason: IncompleteReason.notLoaded(walk.current)))
            case .refuse(let refusal):
                // A redirect or refresh that hands over to an app store (apps.apple.com → itms-appss://)
                // ends the walk where it should: complete — unless something earlier in the walk
                // was incomplete, which `stop` keeps.
                if walk.hopIndex > 0, refusal == .unsupportedScheme, LinkInspector.isStoreHandOff(walk.current) {
                    return walk.stop(Hop(url: display, stopped: .gate), .complete)
                }
                return walk.stop(Hop(url: display, stopped: .gate), Completeness(.incomplete, reason: IncompleteReason.refused(refusal)))
            }

            let host = target.asciiHost ?? ""
            let key = LinkInspector.loopKey(target)
            var kind: Hop.Kind? = upgraded ? .httpsUpgrade : nil
            let recorded = LinkInspector.display(target)
            if walk.visited.contains(key) {
                return walk.stop(Hop(url: recorded, kind: kind, stopped: .loop), Completeness(.incomplete, reason: IncompleteReason.redirectLimit))
            }
            if walk.requests >= walk.options.maxRequests || walk.bytesLeft <= 0 {
                return walk.stop(Hop(url: recorded, kind: kind, stopped: .budget), Completeness(.incomplete, reason: IncompleteReason.redirectLimit))
            }
            if walk.deadline.hasPassed || Task.isCancelled {
                return walk.stop(Hop(url: recorded, kind: kind, stopped: .timeout), Completeness(.incomplete, reason: IncompleteReason.timeout))
            }
            walk.visited.insert(key)
            walk.requests += 1

            // A page may be as large as the page budget whether or not it is compressed.
            let pageBytes = min(walk.options.maxPageBytes, walk.bytesLeft)
            let request = FetchRequest(
                url: target,
                deadline: .earliest(walk.deadline, .now + walk.options.hopDeadline),
                limits: FetchLimits(maxCompressedBytes: max(FetchLimits().maxCompressedBytes, pageBytes), maxDecodedBytes: pageBytes),
                bodyPolicy: .htmlOnly
            )
            let response: HTTPResponse
            do {
                response = try await transport.fetch(request)
            } catch {
                if error != .nonPublicAddress, error != .unverifiableAddress { walk.destination = target }
                let (stop, reason) = await failure(error, upgraded: upgraded)
                return walk.stop(Hop(url: recorded, kind: kind, stopped: stop), Completeness(.incomplete, reason: reason))
            }
            walk.destination = target
            walk.bytesLeft -= response.body.count
            // Kinds, first one wins: HTTPS upgrade, short link / curated relationship, then how it redirects.
            if kind == nil { kind = hopKind(host: host, previousHost: walk.previousHost) }
            var hop = Hop(url: recorded, status: response.status, kind: kind)

            // A body that did not arrive completely is accounted for before anything is read from it:
            // whatever follows — this page, a page we can't recognize, or navigation it leads to — can't
            // make the inspection complete.
            switch response.bodyState {
            case .truncated, .interrupted: walk.degrade(IncompleteReason.pageTruncated)
            case .timedOut: walk.degrade(IncompleteReason.timeout)
            case .complete, .skipped: break
            }
            let stalled = response.bodyState == .timedOut

            // Where does this response send the browser next?
            var next: URL?
            if response.isRedirect, let location = response.headers["location"] {
                guard let resolved = LinkInspector.resolve(location: location, against: target) else {
                    walk.chain.append(hop)
                    return walk.stop(Hop(url: LinkInspector.sanitizedLocation(location), stopped: .gate),
                                     Completeness(.incomplete, reason: IncompleteReason.refusedAmbiguous))
                }
                if hop.kind == nil, OpenRedirect.innerTarget(of: target) != nil { hop.kind = .openRedirect }
                next = resolved
            } else if (200..<300).contains(response.status), let inner = OpenRedirect.innerTarget(of: target) {
                // A known open redirector showing an interstitial: its inner URL is where the user goes.
                if hop.kind == nil { hop.kind = .openRedirect }
                next = inner
            } else if LinkInspector.isHTML(response) {
                progress(.readingPage)
                let analysis = analyzer.analyze(response.body, charset: response.charset, url: target,
                                                refreshHeader: response.headers["refresh"], deadline: walk.deadline)
                if analysis.truncated {
                    // Not examined to the end: a limit, or the deadline / cancellation stopped the analysis.
                    walk.degrade(walk.deadline.hasPassed ? IncompleteReason.timeout : IncompleteReason.pageTruncated)
                }
                if let refresh = analysis.refresh, refresh.delay <= LinkInspector.maxRefreshDelay,
                   let destination = refresh.url, LinkInspector.loopKey(destination) != key {
                    if hop.kind == nil { hop.kind = .metaRefresh }
                    next = destination
                } else {
                    walk.final = endpoint(target)
                    walk.page = analysis.facts
                    if stalled { hop.stopped = .timeout }
                    // "Script only" is judged on a page we read completely; otherwise the earlier reason stands.
                    let scriptOnly = walk.degraded == nil && analysis.scriptOnly
                    return walk.stop(hop, scriptOnly ? Completeness(.incomplete, reason: IncompleteReason.jsOnly) : .complete)
                }
            } else {
                // A final response that is not a page (a file, an image, an empty 204…) — or one whose
                // body stalled before it could be recognized.
                walk.final = endpoint(target)
                if stalled { hop.stopped = .timeout }
                return walk.stop(hop, .complete)
            }

            guard let next else { return }
            walk.chain.append(hop)
            walk.redirects += 1
            progress(.followingRedirects(count: walk.redirects))
            walk.previousHost = host
            walk.current = next
            walk.hopIndex += 1
        }
    }

    /// How a failed request is recorded. An upgraded `http` link whose HTTPS variant fails is
    /// reported as such (`inc.https_failed`): the original cleartext link is never tried.
    private func failure(_ error: FetchError, upgraded: Bool) async -> (Hop.Stop, String?) {
        let stop: Hop.Stop
        switch error {
        case .timeout: stop = .timeout
        case .tlsFailed, .unsupportedProtocol: stop = .tlsFailed
        case .nonPublicAddress, .unverifiableAddress: stop = .gate
        default: stop = .error
        }
        switch error {
        case .cancelled:
            return (stop, nil)
        case .nonPublicAddress:
            return (stop, IncompleteReason.refusedLocal)
        case .unverifiableAddress:
            return (stop, IncompleteReason.fetchFailed)
        case .offline:
            return (stop, IncompleteReason.offline)
        case .nameNotResolved, .resolverFailed, .connectionFailed, .timeout:
            // The network may have dropped while we were walking.
            if await reachability.isOffline() { return (stop, IncompleteReason.offline) }
        default:
            break
        }
        if upgraded { return (stop, IncompleteReason.httpsFailed) }
        return (stop, error == .timeout ? IncompleteReason.timeout : IncompleteReason.fetchFailed)
    }

    // MARK: - Helpers

    /// Awaits a background check; cancelling the inspection cancels the check.
    fileprivate static func value<T: Sendable>(of task: Task<T, Never>?) async -> T? {
        guard let task else { return nil }
        return await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
    }

    private func isShortener(_ host: String) -> Bool {
        rules.shorteners.contains { DomainKit.host(host, isWithin: $0) } || rules.qrRedirectors.contains { DomainKit.host(host, isWithin: $0) }
    }

    private func hopKind(host: String, previousHost: String?) -> Hop.Kind? {
        if isShortener(host) { return .shortener }
        if let previousHost, rules.parking.contains(where: { city in
            city.relationships.contains { $0.count == 2 && $0[0].lowercased() == previousHost && $0[1].lowercased() == host }
        }) {
            return .curatedRelationship
        }
        return nil
    }

    private func endpoint(_ url: URL) -> Endpoint {
        let host = url.asciiHost ?? ""
        return Endpoint(url: LinkInspector.display(url), host: host,
                        registrable: DomainKit.registrable(host, privateSuffixes: rules.freeHosts))
    }

    /// What the public checks may be asked about; nil for IP literals and local names.
    private func domainTarget(_ host: String) -> DomainTarget? {
        guard PublicName.isEligible(host, rules: rules) else { return nil }
        // Tenants of free-hosting platforms share the platform's registration, whose date says
        // nothing about the tenant: RDAP is not asked for them (Quad9 still is).
        let shared = rules.freeHosts.contains { host != $0 && DomainKit.host(host, isWithin: $0) }
        return DomainTarget(host: host, registrable: DomainKit.registrable(host, privateSuffixes: rules.freeHosts), sharedHosting: shared)
    }

    private static func host(of decision: LinkGate.Decision, fallback: URL) -> String? {
        switch decision {
        case .fetch(let u), .upgrade(let u): return u.asciiHost
        default: return fallback.asciiHost
        }
    }

    /// An app-store scheme from BQCore's approved list (`Analyzer.storeSchemes`).
    static func isStoreHandOff(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return Analyzer.storeSchemes.contains(scheme)
    }

    /// The URL as recorded in the chain: no credentials, no fragment.
    static func display(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.user = nil
        c.password = nil
        c.fragment = nil
        return c.string ?? url.absoluteString
    }

    /// The fragment never leaves the device; requests and the chain are recorded without it.
    static func withoutFragment(_ url: URL) -> URL {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.fragment != nil else { return url }
        c.fragment = nil
        return c.url ?? url
    }

    /// Identity of a request for loop detection: scheme, host, port, path and query.
    static func loopKey(_ url: URL) -> String {
        guard var c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        c.fragment = nil
        c.user = nil
        c.password = nil
        c.encodedHost = c.encodedHost?.lowercased()
        c.scheme = c.scheme?.lowercased()
        if c.path.isEmpty { c.path = "/" }
        return c.string ?? url.absoluteString
    }

    /// Resolves a `Location` value. Values a browser could read differently from us (backslashes,
    /// whitespace, control characters) are refused rather than guessed.
    static func resolve(location raw: String, against base: URL) -> URL? {
        let value = raw.trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
        guard !value.isEmpty, !value.contains("\\"),
              !value.unicodeScalars.contains(where: { $0.properties.isWhitespace || $0.properties.generalCategory == .control }) else {
            return nil
        }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    static func sanitizedLocation(_ raw: String) -> String {
        String(raw.unicodeScalars.filter { !$0.properties.isWhitespace && $0.properties.generalCategory != .control }.prefix(2048).map(Character.init))
    }

    /// HTML by `Content-Type`, or sniffed when the type is missing.
    static func isHTML(_ response: HTTPResponse) -> Bool {
        guard response.bodyState != .skipped else { return false }
        if let type = ContentType(response.headers["content-type"]) { return type.isHTML }
        var bytes = response.body.prefix(512).drop(while: { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D || $0 == 0x0C })
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes = bytes.dropFirst(3) }
        let head = String(decoding: bytes.prefix(16), as: UTF8.self).lowercased()
        return ["<!doctype html", "<html", "<head", "<body", "<script", "<title", "<meta", "<div", "<p", "<!--", "<iframe", "<a ", "<br", "<table", "<h1"]
            .contains { head.hasPrefix($0) }
    }
}

/// A host the public checks may be asked about.
struct DomainTarget: Sendable, Hashable {
    var host: String
    var registrable: String
    /// A tenant of a free-hosting platform (tenant.pages.dev).
    var sharedHosting: Bool
}

/// The scanned domain's Quad9 and RDAP checks, started before the walk and awaited when needed.
private struct ScannedChecks: Sendable {
    let target: DomainTarget
    private let quad9: Task<DomainFacts.Quad9, Never>
    private let registration: Task<RDAPRegistration, Never>?

    init(_ target: DomainTarget, checker: any DomainChecking, deadline: Deadline) {
        self.target = target
        // The walk waits for this verdict before loading the scanned link, so it gets less time.
        let quad9Deadline = Deadline.earliest(deadline, .now + LinkInspector.quad9Wait)
        quad9 = Task { await checker.quad9(target.host, deadline: quad9Deadline) }
        registration = target.sharedHosting ? nil : Task { await checker.registration(target.registrable, deadline: deadline) }
    }

    func verdict() async -> DomainFacts.Quad9? {
        await LinkInspector.value(of: quad9)
    }

    /// The scanned domain's facts; `verdict` replaces Quad9's answer for another host of it.
    func facts(verdict override: DomainFacts.Quad9? = nil) async -> DomainFacts {
        let verdict: DomainFacts.Quad9?
        if let override { verdict = override } else { verdict = await self.verdict() }
        let r = await LinkInspector.value(of: registration)
        return DomainFacts(name: target.registrable, registered: r?.registered, registry: r?.registry, quad9: verdict)
    }

    func cancelRegistration() { registration?.cancel() }

    func cancel() {
        quad9.cancel()
        registration?.cancel()
    }
}
