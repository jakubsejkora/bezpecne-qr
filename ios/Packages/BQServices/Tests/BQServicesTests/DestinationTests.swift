import BQCore
import Foundation
import Testing
@testable import BQServices

struct DestinationTests {
    private let start = "https://qrco.de/review"
    private let landing = "https://destination-bq.cz/menu"
    private func inspect(_ transport: FakeTransport, url: String? = nil, options: InspectionOptions = .init()) async -> Inspection {
        await LinkInspector(transport: transport, vetter: FakeVetter(), domainChecker: FakeDomainChecker(),
                            reachability: FixedReachability()).inspect(URL(string: url ?? start)!, options: options)
    }
    @Test(arguments: [301, 302, 303, 307, 308])
    func observedDestinationAndOpenActionAgree(_ status: Int) async throws {
        let t = FakeTransport([start: .response(HTTPResponse(status: status, headers: HTTPHeaders([("Location", "/second")]))),
            "https://qrco.de/second": FakeTransport.redirect(landing), landing: FakeTransport.html("<p>Menu</p>")])
        let result = await inspect(t)
        let destination = try #require(result.destination)
        #expect(destination.state == .resolved)
        #expect(destination.scannedURL == start)
        #expect(destination.lastObserved?.url == landing && destination.resolved?.url == landing)
        #expect(destination.allowsDirectOpen)
        let a = Analyzer().analyze(ScannedCode(text: start), inspection: result)
        #expect(a.openURL?.absoluteString == landing)
        #expect(a.resolvedHost == "destination-bq.cz" && !a.opensOriginalLink)
        #expect(try JSONDecoder().decode(Inspection.self, from: JSONEncoder().encode(result)) == result)
    }
    @Test(arguments: [401, 403, 404, 429, 500, 503])
    func httpErrorsDoNotBecomeCompletedDestinations(_ status: Int) async {
        let t = FakeTransport([start: FakeTransport.redirect(landing), landing: FakeTransport.html("<p>Unavailable</p>", status: status)])
        let result = await inspect(t)
        #expect(result.destination?.lastObserved?.url == landing)
        #expect(result.destination?.resolved == nil)
        #expect(result.completeness?.reason == IncompleteReason.httpError)
        #expect(Analyzer().analyze(ScannedCode(text: start), inspection: result).openURL?.absoluteString == start)
    }
    @Test func unsupportedNavigationRemainsUnresolved() async {
        let cases: [(FakeTransport.Reply, String)] = [
            (.response(HTTPResponse(status: 302)), IncompleteReason.redirectMissing),
            (FakeTransport.html("<meta http-equiv=refresh content='30;url=/next'><p>Hello</p>"), IncompleteReason.refreshUnsupported),
            (FakeTransport.html("<meta http-equiv=refresh content='not a refresh'>"), IncompleteReason.refreshUnsupported),
            (.response(HTTPResponse(status: 200, headers: HTTPHeaders([("Content-Type", "text/plain"), ("Refresh", "0; url=/next")]))), IncompleteReason.refreshUnsupported),
            (FakeTransport.html("<meta http-equiv=refresh content='0;url=/next'><script>location.href='https://destination-bq.cz/menu'</script>"), IncompleteReason.jsOnly),
            (FakeTransport.html("<p>A long interstitial message before this website takes you to another destination. This is more than sixty characters.</p><script>location.href='https://destination-bq.cz/menu'</script>"), IncompleteReason.jsOnly),
            (FakeTransport.html("<p>Waiting for your browser</p>"), IncompleteReason.shortenerUnresolved)
        ]
        for (reply, reason) in cases {
            let t = FakeTransport([start: reply])
            let result = await inspect(t)
            #expect(result.completeness?.reason == reason)
            #expect(result.destination?.resolved == nil && result.destination?.allowsDirectOpen == false)
            #expect(t.requested == [start])
        }
    }
    @Test func aStoppedTargetWasNeverObserved() async {
        for target in ["https://pay.dimoco.eu/checkout", "https://destination-bq.cz/?token=123456789012345678901234567890", "https://127.0.0.1/"] {
            let t = FakeTransport([start: FakeTransport.redirect(target)])
            let result = await inspect(t)
            #expect(result.destination?.lastObserved?.url == start)
            #expect(result.destination?.resolved == nil)
            #expect(t.requested == [start])
        }
        let t = FakeTransport([start: FakeTransport.redirect(landing), landing: .failure(.timeout)])
        let result = await inspect(t)
        #expect(result.destination?.lastObserved?.url == start)
        #expect(result.chain.last?.url == landing && result.chain.last?.status == nil)
    }
    @Test func fragmentsAndIncompleteBodiesNeverOptIntoDirectOpening() async {
        let fragment = FakeTransport([start: FakeTransport.redirect(landing + "#section"), landing: FakeTransport.html("<p>Menu</p>")])
        let result = await inspect(fragment)
        #expect(result.destination?.state == .resolved)
        #expect(result.destination?.allowsDirectOpen == false)
        #expect(Analyzer().analyze(ScannedCode(text: start), inspection: result).openURL?.absoluteString == start)
        let originalFragment = await inspect(FakeTransport([landing: FakeTransport.html("<p>Menu</p>")]), url: landing + "#section")
        #expect(originalFragment.destination?.allowsDirectOpen == false)
        let partial = await inspect(FakeTransport([start: FakeTransport.redirect(landing), landing: FakeTransport.html("<p>Partial</p>", bodyState: .truncated)]))
        #expect(partial.destination?.resolved == nil)
        #expect(partial.completeness?.state == .incomplete)
    }
    @Test func checksDisabledAndHandoffsHaveDistinctOutcomes() async {
        let t = FakeTransport([start: FakeTransport.redirect("itms-appss://apps.apple.com/cz/app/id1234567890")])
        let handoff = await inspect(t)
        #expect(handoff.destination?.state == .appHandoff && handoff.destination?.resolved == nil)
        #expect(handoff.destination?.lastObserved?.url == start)
        let disabled = await inspect(t, options: .init(pageFetch: false, domainChecks: false))
        #expect(disabled.destination?.lastObserved == nil)
        #expect(disabled.destination?.state == .unresolved)
    }
    @Test func legacyInspectionCannotChangeOpeningRoute() throws {
        let json = """
        {"chain":[{"url":"https://destination-bq.cz/menu","status":200}],"final":{"url":"https://destination-bq.cz/menu","host":"destination-bq.cz","registrable":"destination-bq.cz"}}
        """
        let old = try JSONDecoder().decode(Inspection.self, from: Data(json.utf8))
        let resolution = old.resolution(scannedURL: start, fallbackCompleteness: .complete)
        #expect(resolution.state == .resolved && !resolution.allowsDirectOpen)
    }
    @Test func versionedInboxPreservesResolvedHostAndAcceptsV1() async throws {
        let result = await inspect(FakeTransport([start: FakeTransport.redirect(landing), landing: FakeTransport.html("<p>Menu</p>")]))
        let a = Analyzer().analyze(ScannedCode(text: start), inspection: result)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inbox = HistoryInbox(directory: dir)
        try inbox.invalidate(enabled: true)
        let generation = try #require(try inbox.begin())
        var e = try #require(HistoryEnvelope(a, generation: generation))
        #expect(e.version == 3 && e.resolvedHost == "destination-bq.cz")
        try inbox.put(e)
        #expect(try inbox.entries().first?.resolvedHost == "destination-bq.cz")
        try inbox.acknowledge([e.id])
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(e)) as? [String: Any])
        json["version"] = 1; json.removeValue(forKey: "resolvedHost")
        let legacy = try JSONDecoder().decode(HistoryEnvelope.self, from: JSONSerialization.data(withJSONObject: json))
        try inbox.put(legacy)
        #expect(try inbox.entries().first?.version == 1)
        #expect(try inbox.entries().first?.resolvedHost == nil)
        try inbox.acknowledge([e.id])
        for invalid in ["destination-bq.cz/path", "user@destination-bq.cz", "destination-bq.cz?secret=x", "127.0.0.1", "localhost"] {
            e.resolvedHost = invalid; try inbox.put(e)
            #expect(try inbox.entries().isEmpty)
        }
    }
}
