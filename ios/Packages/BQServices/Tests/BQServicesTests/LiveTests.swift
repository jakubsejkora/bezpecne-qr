import BQCore
import Foundation
import Testing
@testable import BQServices

/// Real network. Run with `BQ_LIVE_TESTS=1 swift test --filter Live`.
@Suite("Live network", .enabled(if: liveTestsEnabled), .serialized)
struct LiveTests {
    @Test func safeFetcherExampleCom() async throws {
        let response = try await SafeFetcher().fetch(FetchRequest(url: URL(string: "https://www.example.com/")!, deadline: .now + .seconds(5)))
        print("LIVE SafeFetcher example.com:", response.status, response.bodyState, response.body.count, "bytes via", response.remoteAddress ?? "?",
              "content-encoding:", response.headers["content-encoding"] ?? "identity")
        #expect(response.status == 200)
        #expect(response.bodyState == .complete)
        #expect(String(decoding: response.body, as: UTF8.self).contains("Example Domain"))
    }

    @Test func cancellationAndDeadlineOnALiveConnection() async throws {
        // httpbin waits 3 s before answering: cancel after the connection is up, then let a deadline expire.
        let fetcher = SafeFetcher()
        let task = Task { await fetchResult(fetcher, FetchRequest(url: URL(string: "https://httpbin.org/delay/3")!, timeout: .seconds(6))) }
        try await Task.sleep(for: .milliseconds(800))
        let start = ContinuousClock.now
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        print("LIVE cancel resumed after", ContinuousClock.now - start)
        #expect(ContinuousClock.now - start < .milliseconds(300))

        let timed = ContinuousClock.now
        await #expect(throws: FetchError.timeout) {
            try await fetcher.fetch(FetchRequest(url: URL(string: "https://httpbin.org/delay/3")!, timeout: .seconds(1)))
        }
        print("LIVE deadline after", ContinuousClock.now - timed)
        #expect(ContinuousClock.now - timed < .milliseconds(1300))
    }

    /// incomplete-chain.badssl.com omits its intermediate certificate. The system's default evaluation
    /// downloads it (an unvetted request to a URL the peer chose); ours never does, so both clients fail.
    @Test func noIssuerDownloads() async throws {
        let url = URL(string: "https://incomplete-chain.badssl.com/")!
        await #expect(throws: FetchError.tlsFailed) { try await SafeFetcher().fetch(FetchRequest(url: url, timeout: .seconds(5))) }
        await #expect(throws: (any Error).self) { try await URLSessionEndpointClient.shared.send(URLRequest(url: url)) }
        let (_, ok) = try await URLSessionEndpointClient.shared.send(URLRequest(url: URL(string: "https://dns.quad9.net/")!))
        print("LIVE endpoint client with our trust evaluation, dns.quad9.net:", ok.statusCode)
        #expect(ok.statusCode < 500)
    }

    @Test func systemResolver() async throws {
        let addresses = try await SystemResolver().resolve("www.example.com", deadline: .now + .seconds(3))
        print("LIVE resolver www.example.com:", addresses.map(\.description))
        #expect(!addresses.isEmpty)
        #expect(addresses.allSatisfy { $0.isPublic })
        await #expect(throws: FetchError.nameNotResolved) {
            try await SystemResolver().resolve("neexistujici-domena-bq-2026.cz", deadline: .now + .seconds(3))
        }
    }

    @Test func inspectPragueParking() async {
        let inspector = LinkInspector()
        let result = await inspector.inspect(URL(string: "https://parking.praha.eu/")!, options: InspectionOptions()) { step in
            print("LIVE progress:", step)
        }
        print("LIVE parking.praha.eu chain:", result.chain.map { "\($0.status.map(String.init) ?? "-") \($0.kind?.rawValue ?? "") \($0.stopped?.rawValue ?? "") \($0.url)" })
        print("LIVE final:", result.final as Any)
        print("LIVE title:", result.page?.title as Any, "asks:", result.page?.asks as Any, "lines:", result.page?.extract.count as Any)
        print("LIVE extract:", result.page?.extract.prefix(8) as Any)
        print("LIVE domain:", result.domain as Any)
        print("LIVE completeness:", result.completeness as Any)
        #expect(result.chain.count >= 2) // parking.praha.eu redirects
        #expect(result.final != nil)
        #expect(result.page?.extract.isEmpty == false)
    }

    @Test func quad9() async {
        let client = Quad9Client()
        let ok = await client.check("example.com", deadline: .now + .seconds(4))
        let blocked = await client.check("isitblocked.org", deadline: .now + .seconds(4))
        let nonexistent = await client.check("neexistujici-domena-bq-2026.cz", deadline: .now + .seconds(4))
        print("LIVE Quad9 example.com:", ok, "isitblocked.org:", blocked, "nonexistent:", nonexistent)
        #expect(ok == .ok)
        #expect(blocked == .blocked)
        #expect(nonexistent == .ok)
    }

    @Test func rdapRohlik() async {
        // rdap.nic.cz rate-limits per IP (503 when exceeded) and the end-to-end suite queries it in
        // the same run, so a fresh client retries after a pause. A 503 is reported as unknown by design.
        var registration = RDAPRegistration()
        for attempt in 1...4 {
            registration = await RDAPClient().lookup("rohlik.cz", deadline: .now + .seconds(5))
            print("LIVE RDAP rohlik.cz attempt \(attempt):", registration)
            if registration.registered != nil { break }
            try? await Task.sleep(for: .seconds(5))
        }
        #expect(registration.registered != nil)
        #expect(registration.registry == "CZ.NIC")
        let com = await RDAPClient().lookup("example.com", deadline: .now + .seconds(10))
        print("LIVE RDAP example.com:", com)
        #expect(com.registry == "Verisign")
    }
}
