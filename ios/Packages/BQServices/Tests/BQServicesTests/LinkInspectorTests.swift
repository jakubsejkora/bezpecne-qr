import BQCore
import Foundation
import Synchronization
import Testing
@testable import BQServices

@Suite("Link inspector")
struct LinkInspectorTests {
    static let menu = "<html><head><title>Kavárna U Lípy — menu</title></head><body><p>Snídaně do 11:00</p><p>Espresso 55 Kč · Cappuccino 69 Kč</p></body></html>"

    private func inspect(_ url: String, transport: FakeTransport, checker: FakeDomainChecker = FakeDomainChecker(),
                         vetter: FakeVetter = FakeVetter(), options: InspectionOptions = InspectionOptions(), manualOverride: Bool = false,
                         offline: Bool = false, progress: @escaping @Sendable (InspectionProgress) -> Void = { _ in }) async -> Inspection {
        let inspector = LinkInspector(transport: transport, vetter: vetter, domainChecker: checker, reachability: FixedReachability(offline: offline))
        return await inspector.inspect(URL(string: url)!, options: options, manualOverride: manualOverride, progress: progress)
    }

    @Test func shortenerRedirectChain() async {
        let transport = FakeTransport([
            "https://qrco.de/bfK7aQ": FakeTransport.redirect("https://www.kavarnaulipy.cz/menu"),
            "https://www.kavarnaulipy.cz/menu": FakeTransport.html(Self.menu),
        ])
        let checker = FakeDomainChecker(registrations: ["kavarnaulipy.cz": RDAPRegistration(registered: "2020-04-14", registry: "CZ.NIC")])
        let steps = Mutex<[InspectionProgress]>([])
        let result = await inspect("https://qrco.de/bfK7aQ", transport: transport, checker: checker, progress: { p in steps.withLock { $0.append(p) } })

        #expect(result.chain == [
            Hop(url: "https://qrco.de/bfK7aQ", status: 302, kind: .shortener),
            Hop(url: "https://www.kavarnaulipy.cz/menu", status: 200),
        ])
        #expect(result.final == Endpoint(url: "https://www.kavarnaulipy.cz/menu", host: "www.kavarnaulipy.cz", registrable: "kavarnaulipy.cz"))
        #expect(result.page?.title == "Kavárna U Lípy — menu")
        #expect(result.page?.extract == ["Snídaně do 11:00", "Espresso 55 Kč · Cappuccino 69 Kč"])
        #expect(result.page?.asks == [])
        #expect(result.domain == DomainFacts(name: "kavarnaulipy.cz", registered: "2020-04-14", registry: "CZ.NIC", quad9: .ok))
        #expect(result.completeness == .complete)
        #expect(transport.requested == ["https://qrco.de/bfK7aQ", "https://www.kavarnaulipy.cz/menu"])
        // Checks ran for the scanned domain first, then for the destination.
        #expect(Set(checker.calls) == ["quad9:qrco.de", "rdap:qrco.de", "quad9:www.kavarnaulipy.cz", "rdap:kavarnaulipy.cz"])
        #expect(steps.withLock { $0 } == [.checkingAddress(shortLink: true), .checkingDomain, .followingRedirects(count: 1), .readingPage])
    }

    @Test func httpLinkIsUpgradedAndCleartextNeverLoaded() async {
        let transport = FakeTransport(["https://www.kavarnaulipy.cz/wifi": FakeTransport.html("<title>Wi‑Fi pro hosty</title><p>Síť: Kavarna_U_Lipy</p>")])
        let result = await inspect("http://www.kavarnaulipy.cz/wifi", transport: transport)
        #expect(result.chain == [Hop(url: "https://www.kavarnaulipy.cz/wifi", status: 200, kind: .httpsUpgrade)])
        #expect(result.completeness == .complete)
        #expect(transport.requested == ["https://www.kavarnaulipy.cz/wifi"])

        let failing = FakeTransport { _ in .failure(.tlsFailed) }
        let failed = await inspect("http://185.199.1.23/platba", transport: failing)
        #expect(failed.chain == [Hop(url: "https://185.199.1.23/platba", kind: .httpsUpgrade, stopped: .tlsFailed)])
        #expect(failed.completeness == Completeness(.incomplete, reason: "inc.https_failed"))
        #expect(failing.requested == ["https://185.199.1.23/platba"])
        #expect(failed.domain == nil) // IP literal: no public checks
    }

    @Test func billingHostIsNeverContacted() async {
        let transport = FakeTransport([
            "https://hudba-zdarma-cz.top/go": FakeTransport.redirect("https://pay.dimoco.eu/cz/checkout"),
        ])
        let checker = FakeDomainChecker()
        let result = await inspect("https://hudba-zdarma-cz.top/go", transport: transport, checker: checker)
        #expect(result.chain == [
            Hop(url: "https://hudba-zdarma-cz.top/go", status: 302),
            Hop(url: "https://pay.dimoco.eu/cz/checkout", stopped: .billing),
        ])
        #expect(result.final == nil)
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.billing_stop"))
        #expect(!transport.requested.contains { $0.contains("dimoco") })
        #expect(result.domain?.name == "hudba-zdarma-cz.top")
        #expect(!checker.calls.contains { $0.contains("dimoco") })

        // Operator sites reached by a redirect are stopped too.
        let operatorTransport = FakeTransport(["https://soutez-bq.top/": FakeTransport.redirect("https://www.o2.cz/premium?x=1")])
        let toOperator = await inspect("https://soutez-bq.top/", transport: operatorTransport)
        #expect(toOperator.chain.last == Hop(url: "https://www.o2.cz/premium?x=1", stopped: .billing))
        #expect(operatorTransport.requested == ["https://soutez-bq.top/"])
    }

    @Test func tokenLinkIsSkippedButTheDomainIsChecked() async {
        let transport = FakeTransport { _ in .failure(.connectionFailed) }
        let checker = FakeDomainChecker()
        let result = await inspect("https://moje.muj-energie-ucet-portal.cz/overeni?token=9f2c7a1e5b3d48c0a6e2f19d7b8c4e3a",
                                   transport: transport, checker: checker)
        #expect(transport.requested.isEmpty)
        #expect(result.completeness == Completeness(.skipped, reason: "inc.token_skipped", manual: false))
        #expect(result.chain.map(\.stopped) == [.gate])
        #expect(result.domain?.name == "muj-energie-ucet-portal.cz")
        #expect(result.domain?.quad9 == .ok)
        #expect(Set(checker.calls) == ["quad9:moje.muj-energie-ucet-portal.cz", "rdap:muj-energie-ucet-portal.cz"])
    }

    @Test func signInPathIsSkippedUnlessTheUserAsks() async {
        let transport = FakeTransport(["https://www.ceska-sporitelna-bq.com/prihlaseni": FakeTransport.html("<title>Přihlášení</title><input type=password name=p>")])
        let skipped = await inspect("https://www.ceska-sporitelna-bq.com/prihlaseni", transport: transport)
        #expect(skipped.completeness == Completeness(.skipped, reason: "inc.auth_path_skipped", manual: true))
        #expect(transport.requested.isEmpty)
        let manual = await inspect("https://www.ceska-sporitelna-bq.com/prihlaseni", transport: transport, manualOverride: true)
        #expect(manual.completeness == .complete)
        #expect(manual.page?.asks == [.password])
        #expect(transport.requested.count == 1)
    }

    @Test func downloadsAreNotNeeded() async {
        let transport = FakeTransport { _ in .failure(.connectionFailed) }
        let checker = FakeDomainChecker()
        let result = await inspect("https://aplikace-zdarma-cz.xyz/stahnout.apk", transport: transport, checker: checker)
        #expect(result.completeness == Completeness(.notNeeded, reason: "inc.not_loaded_file"))
        #expect(transport.requested.isEmpty)
        #expect(result.domain?.name == "aplikace-zdarma-cz.xyz")
    }

    @Test func refusedLinksSendNothingAtAll() async {
        let transport = FakeTransport { _ in .failure(.connectionFailed) }
        let checker = FakeDomainChecker()
        let vetter = FakeVetter()
        let expected = ["http://192.168.1.1/admin": "inc.refused_local", "https://localhost/": "inc.refused_local",
                        "https://printer.local/": "inc.refused_local", "ftp://example.cz/x": "inc.refused_scheme",
                        "https://exa\\mple.cz/": "inc.refused_ambiguous"]
        for (url, reason) in expected {
            guard let u = URL(string: url) else { continue }
            let result = await LinkInspector(transport: transport, vetter: vetter, domainChecker: checker, reachability: FixedReachability()).inspect(u)
            #expect(result.completeness == Completeness(.incomplete, reason: reason), "\(url)")
            #expect(result.chain.map(\.stopped) == [.gate])
            #expect(result.domain == nil)
        }
        #expect(transport.requested.isEmpty)
        #expect(checker.calls.isEmpty)
        #expect(vetter.calls.isEmpty) // not even resolved
    }

    @Test func redirectLoop() async {
        let transport = FakeTransport([
            "https://a-bq.cz/": FakeTransport.redirect("https://b-bq.cz/x"),
            "https://b-bq.cz/x": FakeTransport.redirect("/../"),
        ])
        let looping = FakeTransport([
            "https://a-bq.cz/": FakeTransport.redirect("https://b-bq.cz/x"),
            "https://b-bq.cz/x": FakeTransport.redirect("https://A-BQ.cz/#again"),
        ])
        let result = await inspect("https://a-bq.cz/", transport: looping)
        #expect(result.chain == [
            Hop(url: "https://a-bq.cz/", status: 302),
            Hop(url: "https://b-bq.cz/x", status: 302),
            Hop(url: "https://a-bq.cz/", stopped: .loop),
        ])
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.redirect_limit"))
        #expect(looping.requested.count == 2)
        _ = transport
    }

    @Test func requestBudget() async {
        let transport = FakeTransport { url in
            let n = Int(url.lastPathComponent) ?? 0
            return FakeTransport.redirect("https://redir-bq.cz/\(n + 1)")
        }
        var options = InspectionOptions()
        options.maxRequests = 4
        let result = await inspect("https://redir-bq.cz/0", transport: transport, options: options)
        #expect(transport.requested.count == 4)
        #expect(result.chain.count == 5)
        #expect(result.chain.last == Hop(url: "https://redir-bq.cz/4", stopped: .budget))
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.redirect_limit"))

        // The default budget is 10 requests.
        let unbounded = FakeTransport { url in FakeTransport.redirect("https://redir-bq.cz/\((Int(url.lastPathComponent) ?? 0) + 1)") }
        _ = await inspect("https://redir-bq.cz/0", transport: unbounded)
        #expect(unbounded.requested.count == 10)
    }

    @Test func timeouts() async {
        let timingOut = FakeTransport { _ in .failure(.timeout) }
        let result = await inspect("https://ceskaposta-doplatek.top/", transport: timingOut)
        #expect(result.chain == [Hop(url: "https://ceskaposta-doplatek.top/", stopped: .timeout)])
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.timeout"))

        // The overall deadline ends an endless slow chain on time.
        let slow = FakeTransport { url in
            .delayed(.milliseconds(150), HTTPResponse(status: 302, headers: HTTPHeaders([("Location", "https://slow-bq.cz/\((Int(url.lastPathComponent) ?? 0) + 1)")])))
        }
        var options = InspectionOptions()
        options.overallDeadline = .milliseconds(700)
        let start = ContinuousClock.now
        let slowResult = await inspect("https://slow-bq.cz/0", transport: slow, options: options)
        #expect(ContinuousClock.now - start < .seconds(2))
        #expect(slowResult.chain.last?.stopped == .timeout)
        #expect(slowResult.completeness == Completeness(.incomplete, reason: "inc.timeout"))
        #expect((3...6).contains(slow.requested.count))
    }

    @Test func openRedirectInnerHop() async {
        let interstitial = "<html><body><p>Redirect Notice</p><a href='https://ceskaposta-doplatek.top/'>https://ceskaposta-doplatek.top/</a></body></html>"
        let transport = FakeTransport([
            "https://www.google.com/url?q=https://ceskaposta-doplatek.top/": FakeTransport.html(interstitial),
            "https://ceskaposta-doplatek.top/": FakeTransport.html("<title>Česká pošta — doplatek</title><p>Uhraďte doplatek 29 Kč.</p><input name=cardnumber>"),
        ])
        let checker = FakeDomainChecker()
        let result = await inspect("https://www.google.com/url?q=https://ceskaposta-doplatek.top/", transport: transport, checker: checker)
        #expect(result.chain == [
            Hop(url: "https://www.google.com/url?q=https://ceskaposta-doplatek.top/", status: 200, kind: .openRedirect),
            Hop(url: "https://ceskaposta-doplatek.top/", status: 200),
        ])
        #expect(result.final?.host == "ceskaposta-doplatek.top")
        #expect(result.page?.brandClaim == "Česká pošta")
        #expect(result.page?.asks == [.card])
        #expect(result.domain?.name == "ceskaposta-doplatek.top")

        // When the inner target times out, the domain checks still describe it.
        let timeout = FakeTransport { url in
            url.host() == "www.google.com" ? FakeTransport.html(interstitial) : .failure(.timeout)
        }
        let timedOut = await inspect("https://www.google.com/url?q=https://ceskaposta-doplatek.top/", transport: timeout)
        #expect(timedOut.chain.last == Hop(url: "https://ceskaposta-doplatek.top/", stopped: .timeout))
        #expect(timedOut.final == nil)
        #expect(timedOut.domain?.name == "ceskaposta-doplatek.top")
        #expect(timedOut.completeness == Completeness(.incomplete, reason: "inc.timeout"))
    }

    @Test func metaRefresh() async {
        let transport = FakeTransport([
            "https://parking-bq.cz/qr": FakeTransport.html("<meta http-equiv='refresh' content='1;url=/platba'><p>Přesměrování…</p>"),
            "https://parking-bq.cz/platba": FakeTransport.html("<title>Platba</title><input name=spz>"),
        ])
        let result = await inspect("https://parking-bq.cz/qr", transport: transport)
        #expect(result.chain == [
            Hop(url: "https://parking-bq.cz/qr", status: 200, kind: .metaRefresh),
            Hop(url: "https://parking-bq.cz/platba", status: 200),
        ])
        #expect(result.page?.asks == [.licencePlate])

        // A slow refresh is not a redirect; a refresh to itself is a reload.
        let slow = FakeTransport(["https://slow-refresh-bq.cz/": FakeTransport.html("<meta http-equiv='refresh' content='30;url=/jinam'><p>Obsah</p>")])
        #expect(await inspect("https://slow-refresh-bq.cz/", transport: slow).chain.count == 1)
        let reload = FakeTransport(["https://reload-bq.cz/": FakeTransport.html("<meta http-equiv='refresh' content='0'><p>Obsah</p>")])
        #expect(await inspect("https://reload-bq.cz/", transport: reload).final?.host == "reload-bq.cz")
    }

    @Test func togglesStopTheirTraffic() async {
        let transport = FakeTransport { _ in .failure(.connectionFailed) }
        let checker = FakeDomainChecker()
        let noFetch = await inspect("https://www.kavarnaulipy.cz/menu", transport: transport, checker: checker,
                                    options: InspectionOptions(pageFetch: false))
        #expect(transport.requested.isEmpty)
        #expect(noFetch.chain.isEmpty)
        #expect(noFetch.completeness == Completeness(.incomplete, reason: "inc.checks_disabled"))
        #expect(noFetch.domain?.name == "kavarnaulipy.cz")

        let pages = FakeTransport(["https://www.kavarnaulipy.cz/menu": FakeTransport.html(Self.menu)])
        let quiet = FakeDomainChecker()
        let noChecks = await inspect("https://www.kavarnaulipy.cz/menu", transport: pages, checker: quiet,
                                     options: InspectionOptions(domainChecks: false))
        #expect(quiet.calls.isEmpty)
        #expect(noChecks.domain == nil)
        #expect(noChecks.completeness == .complete)

        let none = await inspect("https://www.kavarnaulipy.cz/menu", transport: transport, checker: checker,
                                 options: InspectionOptions(pageFetch: false, domainChecks: false))
        #expect(none.completeness == Completeness(.incomplete, reason: "inc.checks_disabled"))
        #expect(transport.requested.isEmpty)
        #expect(checker.calls.count == 2) // only the first inspection's checks
    }

    @Test func quad9BlockMeansThePageIsNotLoaded() async {
        let transport = FakeTransport { _ in FakeTransport.html("<p>phish</p>") }
        let checker = FakeDomainChecker(verdicts: ["edalnice-uhrada.cz": .blocked],
                                        registrations: ["edalnice-uhrada.cz": RDAPRegistration(registered: "2026-09-20", registry: "CZ.NIC")])
        let result = await inspect("https://edalnice-uhrada.cz/", transport: transport, checker: checker)
        #expect(transport.requested.isEmpty)
        #expect(result.chain.isEmpty)
        #expect(result.domain == DomainFacts(name: "edalnice-uhrada.cz", registered: "2026-09-20", registry: "CZ.NIC", quad9: .blocked))
        #expect(result.completeness == Completeness(.notNeeded, reason: "inc.domain_blocked"))
    }

    @Test func curatedParkingRelationship() async {
        let transport = FakeTransport([
            "https://parking.praha.eu/PA/1234": FakeTransport.redirect("https://vph.zpspraha.cz/PA/1234"),
            "https://vph.zpspraha.cz/PA/1234": FakeTransport.html(Pages.parking),
        ])
        let result = await inspect("https://parking.praha.eu/PA/1234", transport: transport)
        #expect(result.chain == [
            Hop(url: "https://parking.praha.eu/PA/1234", status: 302),
            Hop(url: "https://vph.zpspraha.cz/PA/1234", status: 200, kind: .curatedRelationship),
        ])
        #expect(result.final?.registrable == "zpspraha.cz")
        #expect(result.page?.asks == [.licencePlate, .card])
    }

    @Test func unsafeRedirectTargets() async {
        // A redirect into the local network.
        let toPrivate = FakeTransport(["https://redir-bq.cz/": FakeTransport.redirect("http://10.0.0.1/admin")])
        let privateResult = await inspect("https://redir-bq.cz/", transport: toPrivate)
        #expect(privateResult.chain.last == Hop(url: "http://10.0.0.1/admin", stopped: .gate))
        #expect(privateResult.completeness == Completeness(.incomplete, reason: "inc.refused_local"))
        #expect(toPrivate.requested == ["https://redir-bq.cz/"])

        // A Location a browser could read differently.
        let ambiguous = FakeTransport(["https://redir-bq.cz/": FakeTransport.redirect("https:\\\\evil-bq.top/")])
        let ambiguousResult = await inspect("https://redir-bq.cz/", transport: ambiguous)
        #expect(ambiguousResult.chain.last?.stopped == .gate)
        #expect(ambiguousResult.completeness == Completeness(.incomplete, reason: "inc.refused_ambiguous"))

        // A redirect to a download or a calendar is not loaded.
        let toFile = FakeTransport(["https://short-bq.cz/a": FakeTransport.redirect("https://cdn-bq.cz/App.APK"),
                                    "https://short-bq.cz/b": FakeTransport.redirect("https://cdn-bq.cz/akce.ics")])
        #expect(await inspect("https://short-bq.cz/a", transport: toFile).completeness == Completeness(.notNeeded, reason: "inc.not_loaded_file"))
        #expect(await inspect("https://short-bq.cz/b", transport: toFile).completeness == Completeness(.notNeeded, reason: "inc.not_loaded_calendar"))
        #expect(toFile.requested == ["https://short-bq.cz/a", "https://short-bq.cz/b"])
        #expect(ambiguous.requested.count == 1)

        // A public name whose DNS points into the local network (reported by SafeFetcher).
        let rebinding = FakeTransport { _ in .failure(.nonPublicAddress) }
        let rebound = await inspect("https://rebind-bq.cz/", transport: rebinding)
        #expect(rebound.chain == [Hop(url: "https://rebind-bq.cz/", stopped: .gate)])
        #expect(rebound.completeness == Completeness(.incomplete, reason: "inc.refused_local"))
    }

    @Test func pageOutcomes() async {
        let jsOnly = FakeTransport(["https://js-bq.cz/": FakeTransport.html("<script>location.href='https://next-bq.top/'</script>")])
        let js = await inspect("https://js-bq.cz/", transport: jsOnly)
        #expect(js.completeness == Completeness(.incomplete, reason: "inc.js_only"))
        #expect(js.final?.host == "js-bq.cz")
        #expect(jsOnly.requested == ["https://js-bq.cz/"]) // the candidate is not followed

        let truncated = FakeTransport(["https://big-bq.cz/": FakeTransport.html("<p>Začátek</p>", bodyState: .truncated)])
        #expect(await inspect("https://big-bq.cz/", transport: truncated).completeness == Completeness(.incomplete, reason: "inc.page_truncated"))
        // A complete body the analyzer could not read to the end is incomplete too.
        let long = FakeTransport(["https://long-bq.cz/": FakeTransport.html((0...10_000).map { "<p>řádek \($0)</p>" }.joined())])
        #expect(await inspect("https://long-bq.cz/", transport: long).completeness == Completeness(.incomplete, reason: "inc.page_truncated"))

        let pdf = FakeTransport(["https://doc-bq.cz/a.pdf": .response(HTTPResponse(status: 200, headers: HTTPHeaders([("Content-Type", "application/pdf")]), bodyState: .skipped))])
        let pdfResult = await inspect("https://doc-bq.cz/a.pdf", transport: pdf)
        #expect(pdfResult.completeness == .complete)
        #expect(pdfResult.page == nil)
        #expect(pdfResult.final?.host == "doc-bq.cz")

        let notFound = FakeTransport { _ in FakeTransport.html("<title>Stránka nenalezena</title><p>Tato stránka už neexistuje.</p>", status: 404) }
        let gone = await inspect("https://ceska-posta-balik.pages.dev/", transport: notFound)
        #expect(gone.chain == [Hop(url: "https://ceska-posta-balik.pages.dev/", status: 404)])
        #expect(gone.final?.registrable == "ceska-posta-balik.pages.dev")
        #expect(gone.page?.extract == ["Tato stránka už neexistuje."])
    }

    @Test func freeHostingTenantsAreNotSentToRDAP() async {
        let transport = FakeTransport { _ in FakeTransport.html("<p>x</p>") }
        let checker = FakeDomainChecker()
        let result = await inspect("https://ceska-posta-balik.pages.dev/", transport: transport, checker: checker)
        #expect(checker.calls == ["quad9:ceska-posta-balik.pages.dev"])
        #expect(result.domain == DomainFacts(name: "ceska-posta-balik.pages.dev", registered: nil, registry: nil, quad9: .ok))
    }

    @Test func offlineAndNetworkFailures() async {
        let transport = FakeTransport { _ in .failure(.connectionFailed) }
        let checker = FakeDomainChecker()
        let offline = await inspect("https://www.kavarnaulipy.cz/menu", transport: transport, checker: checker, offline: true)
        #expect(offline.completeness == Completeness(.incomplete, reason: "inc.offline"))
        #expect(transport.requested.isEmpty)
        #expect(checker.calls.isEmpty)

        let refused = await inspect("https://www.kavarnaulipy.cz/menu", transport: transport)
        #expect(refused.chain == [Hop(url: "https://www.kavarnaulipy.cz/menu", stopped: .error)])
        #expect(refused.completeness == Completeness(.incomplete, reason: "inc.fetch_failed"))

        let tls = FakeTransport { _ in .failure(.tlsFailed) }
        #expect(await inspect("https://bad-cert-bq.cz/", transport: tls).chain.first?.stopped == .tlsFailed)
    }

    @Test func credentialsAreStrippedFromTheRecordedChain() async {
        let transport = FakeTransport(["https://csob-overeni.top/": FakeTransport.html("<title>ČSOB Internetbanking — přihlášení</title><input type=password name=pin>")])
        let result = await inspect("https://www.csob.cz@csob-overeni.top/#x", transport: transport)
        #expect(transport.requested == ["https://csob-overeni.top/"])
        #expect(result.chain == [Hop(url: "https://csob-overeni.top/", status: 200)])
        #expect(result.page?.brandClaim == "ČSOB")
        #expect(result.final?.registrable == "csob-overeni.top")
    }

    @Test func cancellationStopsQuickly() async {
        let slow = FakeTransport { _ in .delayed(.seconds(5), HTTPResponse(status: 200)) }
        let inspector = LinkInspector(transport: slow, vetter: FakeVetter(), domainChecker: FakeDomainChecker(), reachability: FixedReachability())
        let task = Task { await inspector.inspect(URL(string: "https://slow-bq.cz/")!) }
        try? await Task.sleep(for: .milliseconds(100))
        let start = ContinuousClock.now
        task.cancel()
        let result = await task.value
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(result.completeness?.state == .incomplete)
    }

    // MARK: Split DNS (names that resolve into a private network)

    @Test func privateNamesNeverReachThePublicChecks() async {
        let transport = FakeTransport { _ in FakeTransport.html("<p>x</p>") }
        let checker = FakeDomainChecker()
        let vetter = FakeVetter(["printer.company.cz": .nonPublicAddress])
        for options in [InspectionOptions(), InspectionOptions(pageFetch: false)] {
            let result = await inspect("https://printer.company.cz/status", transport: transport, checker: checker, vetter: vetter, options: options)
            #expect(result.completeness == Completeness(.incomplete, reason: "inc.refused_local"))
            #expect(result.chain == [Hop(url: "https://printer.company.cz/status", stopped: .gate)])
            #expect(result.domain == nil)
        }
        // Also for links the gate stops anyway (a token link, a download).
        for url in ["https://printer.company.cz/scan?token=9f2c7a1e5b3d48c0a6e2f19d7b8c4e3a", "https://printer.company.cz/driver.apk"] {
            let result = await inspect(url, transport: transport, checker: checker, vetter: vetter)
            #expect(result.completeness?.reason == "inc.refused_local")
        }
        #expect(checker.calls.isEmpty)
        #expect(transport.requested.isEmpty)
    }

    @Test func namesThatCannotBeVettedStayOnTheDevice() async {
        let transport = FakeTransport { _ in FakeTransport.html("<title>Ahoj</title>") }
        let checker = FakeDomainChecker()
        // DNS timed out: no public checks, but the fetch (which vets again) still runs.
        let slow = await inspect("https://slow-dns-bq.cz/", transport: transport, checker: checker,
                                 vetter: FakeVetter(["slow-dns-bq.cz": .timeout]))
        #expect(checker.calls.isEmpty)
        #expect(slow.domain == nil)
        #expect(transport.requested == ["https://slow-dns-bq.cz/"])
        // A name that doesn't resolve at all is not anyone's private name: checks run.
        let gone = await inspect("https://smazana-bq.cz/", transport: FakeTransport { _ in .failure(.nameNotResolved) }, checker: checker,
                                 vetter: FakeVetter(["smazana-bq.cz": .nameNotResolved]))
        #expect(gone.domain?.name == "smazana-bq.cz")
    }

    @Test func privateRedirectTargetsAreNotChecked() async {
        // The fetch of the redirect target fails because it resolves privately; the vetter agrees.
        let transport = FakeTransport { url in
            url.host() == "short-bq.cz" ? FakeTransport.redirect("https://intranet.company.cz/") : .failure(.nonPublicAddress)
        }
        let checker = FakeDomainChecker()
        let result = await inspect("https://short-bq.cz/x", transport: transport, checker: checker,
                                   vetter: FakeVetter(["intranet.company.cz": .nonPublicAddress]))
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.refused_local"))
        #expect(!checker.calls.contains { $0.contains("company.cz") })
        #expect(result.domain?.name == "short-bq.cz")
    }

    @Test func operatorLinksAreStoppedAtTheScannedHop() async {
        let transport = FakeTransport { _ in FakeTransport.html("<p>x</p>") }
        let checker = FakeDomainChecker()
        let result = await inspect("https://www.o2.cz/premium-sms", transport: transport, checker: checker)
        #expect(result.chain == [Hop(url: "https://www.o2.cz/premium-sms", stopped: .billing)])
        #expect(result.completeness == Completeness(.incomplete, reason: "inc.billing_stop"))
        #expect(transport.requested.isEmpty)
        #expect(result.domain?.name == "o2.cz") // only the name goes to the public checks
    }

    // MARK: Incompleteness survives page-derived navigation

    @Test func metaRefreshFromAPartialPageStaysIncomplete() async {
        for (state, reason) in [(HTTPResponse.BodyState.truncated, "inc.page_truncated"), (.interrupted, "inc.page_truncated"), (.timedOut, "inc.timeout")] {
            let transport = FakeTransport([
                "https://cut-bq.cz/": FakeTransport.html("<meta http-equiv=refresh content='0;url=/next'><p>Začátek", bodyState: state),
                "https://cut-bq.cz/next": FakeTransport.html("<title>Hotovo</title><p>Obsah</p>"),
            ])
            let result = await inspect("https://cut-bq.cz/", transport: transport)
            #expect(result.chain == [Hop(url: "https://cut-bq.cz/", status: 200, kind: .metaRefresh), Hop(url: "https://cut-bq.cz/next", status: 200)])
            #expect(result.page?.title == "Hotovo")
            #expect(result.completeness == Completeness(.incomplete, reason: reason), "\(state)")
        }
        // A complete page with a meta refresh still ends complete.
        let whole = FakeTransport([
            "https://whole-bq.cz/": FakeTransport.html("<meta http-equiv=refresh content='0;url=/next'>"),
            "https://whole-bq.cz/next": FakeTransport.html("<title>Hotovo</title>"),
        ])
        #expect(await inspect("https://whole-bq.cz/", transport: whole).completeness == .complete)
    }
}
