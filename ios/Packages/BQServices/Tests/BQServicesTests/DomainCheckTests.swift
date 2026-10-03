import BQCore
import Foundation
import Testing
@testable import BQServices

/// Real Quad9 DoH answers captured on 2026-10-03 (EDNS query, ID 0).
enum Quad9Captures {
    /// example.com: NOERROR with two A records.
    static let ok = hex("000081800001000200000001076578616d706c6503636f6d0000010001c00c00010001000000ee00046814179ac00c00010001000000ee0004ac4293f30000290200000000000000")
    /// isitblocked.org (Quad9's test domain): NXDOMAIN, empty authority, EDE 17 "Filtered".
    static let blocked = hex("0000810300010000000000010b69736974626c6f636b6564036f7267000001000100002904d0000000000006000f00020011")
    /// A name that does not exist: NXDOMAIN with the .cz SOA in the authority section.
    static let nxdomain = hex("000081830001000000010001196e6f6e6578697374656e742d62712d746573742d313233343502637a0000010001c0260006000100000384002c0161026e73036e6963c0260a686f73746d6173746572c03f6ac0428f000003840000012c00093a80000003840000290200000000000000")
}

@Suite("DNS messages and Quad9")
struct DNSMessageTests {
    @Test func queryEncoding() throws {
        let q = try DNSMessage.query(name: "Example.COM.", type: DNSMessage.typeA)
        #expect(q.count % 128 == 0) // EDNS padding hides the name length
        #expect(Array(q[0..<12]) == [0, 0, 0x01, 0x00, 0, 1, 0, 0, 0, 0, 0, 1])
        #expect(Array(q[12..<29]) == [7] + Array("example".utf8) + [3] + Array("com".utf8) + [0, 0, 1, 0, 1])
        let parsed = try DNSMessage.parse(q)
        #expect(parsed.questions == [.init(name: "example.com", type: 1, qclass: 1)])
        #expect(parsed.additionals.count == 1)
        #expect(parsed.additionals[0].type == DNSMessage.typeOPT)
        #expect(parsed.additionals[0].rclass == 1232)
        #expect(!parsed.isResponse)
    }

    @Test func invalidNamesAreNotEncoded() {
        for name in ["", ".", "a..b", String(repeating: "a", count: 64) + ".cz", "bad name.cz", "ž.cz",
                     (0..<50).map { _ in "abcde" }.joined(separator: ".")] {
            #expect(throws: DNSError.self, "\(name)") { try DNSMessage.query(name: name, type: 1) }
        }
    }

    @Test func parsesCompressedNames() throws {
        let ok = try DNSMessage.parse(Quad9Captures.ok)
        #expect(ok.isResponse)
        #expect(ok.rcode == 0)
        #expect(ok.answers.count == 2)
        #expect(ok.answers.allSatisfy { $0.name == "example.com" && $0.type == 1 && $0.data.count == 4 })
        let nx = try DNSMessage.parse(Quad9Captures.nxdomain)
        #expect(nx.rcode == 3)
        #expect(nx.authorities.first?.type == DNSMessage.typeSOA)
        #expect(nx.authorities.first?.name == "cz")
    }

    @Test func extendedDNSErrors() throws {
        let blocked = try DNSMessage.parse(Quad9Captures.blocked)
        #expect(blocked.rcode == 3)
        #expect(blocked.authorities.isEmpty)
        #expect(blocked.extendedErrors.map(\.infoCode) == [17])
    }

    @Test func pointerLoopsAndForwardPointersAreRejected() {
        // Header with one question whose name is a pointer to itself (offset 12).
        let selfLoop: [UInt8] = [0, 0, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 12, 0, 1, 0, 1]
        #expect(throws: DNSError.badPointer) { try DNSMessage.parse(selfLoop) }
        let forward: [UInt8] = [0, 0, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0, 0xC0, 16, 0, 1, 0, 1, 1, 0x61, 0]
        #expect(throws: DNSError.badPointer) { try DNSMessage.parse(forward) }
        let reservedLabelType: [UInt8] = [0, 0, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0, 0x40, 0, 0, 1, 0, 1]
        #expect(throws: DNSError.badPointer) { try DNSMessage.parse(reservedLabelType) }
    }

    @Test func implausibleOrTruncatedMessages() {
        #expect(throws: DNSError.truncated) { try DNSMessage.parse([0, 0, 0x81]) }
        let huge: [UInt8] = [0, 0, 0x81, 0x80, 0xFF, 0xFF, 0xFF, 0xFF, 0, 0, 0, 0] + Array(repeating: 0, count: 20)
        #expect(throws: DNSError.implausibleCounts) { try DNSMessage.parse(huge) }
        #expect(throws: DNSError.truncated) { try DNSMessage.parse(Array(Quad9Captures.ok.dropLast(5))) }
        // A label running past the end.
        let label: [UInt8] = [0, 0, 0x81, 0x80, 0, 1, 0, 0, 0, 0, 0, 0, 63, 0x61, 0x62, 0, 1, 0, 1]
        #expect(throws: DNSError.truncated) { try DNSMessage.parse(label) }
    }

    @Test func quad9Interpretation() throws {
        #expect(Quad9Client.interpret(try DNSMessage.parse(Quad9Captures.ok), name: "example.com") == .answer(.ok, ttl: 238))
        #expect(Quad9Client.interpret(try DNSMessage.parse(Quad9Captures.blocked), name: "isitblocked.org") == .answer(.blocked, ttl: 300))
        // NXDOMAIN with an SOA is an ordinary non-existent name, not a block.
        #expect(Quad9Client.interpret(try DNSMessage.parse(Quad9Captures.nxdomain), name: "nonexistent-bq-test-12345.cz") == .answer(.ok, ttl: 300))
        // The block rule without EDE: NXDOMAIN and an empty authority section.
        var noEDE = try DNSMessage.parse(Quad9Captures.blocked)
        noEDE.additionals = []
        #expect(Quad9Client.interpret(noEDE, name: "isitblocked.org") == .answer(.blocked, ttl: 300))
        // Censorship (EDE 16) is a legal block, not threat intelligence.
        var censored = noEDE
        censored.additionals = [.init(name: ".", type: 41, rclass: 1232, ttl: 0, data: [0, 15, 0, 2, 0, 16])]
        #expect(Quad9Client.interpret(censored, name: "isitblocked.org") == .answer(.unknown, ttl: 300))
        // Answers to another question, SERVFAIL and queries (not responses) are unusable.
        #expect(Quad9Client.interpret(try DNSMessage.parse(Quad9Captures.ok), name: "example.org") == .failed(backoff: false))
        var servfail = try DNSMessage.parse(Quad9Captures.ok)
        servfail.flags = 0x8182
        #expect(Quad9Client.interpret(servfail, name: "example.com") == .failed(backoff: false))
        #expect(Quad9Client.interpret(try DNSMessage.parse(try DNSMessage.query(name: "example.com", type: 1)), name: "example.com") == .failed(backoff: false))
    }

    @Test func quad9ClientSendsOnePOSTAndCaches() async throws {
        let client = FakeEndpointClient { _ in (200, Data(Quad9Captures.ok), ["Content-Type": "application/dns-message"]) }
        let quad9 = Quad9Client(client: client)
        #expect(await quad9.check("Example.com", deadline: .now + .seconds(2)) == .ok)
        #expect(await quad9.check("example.com", deadline: .now + .seconds(2)) == .ok)
        #expect(client.requests.count == 1)
        let request = try #require(client.requests.first)
        #expect(request.url == Quad9Client.endpoint)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/dns-message")
        let sent = try DNSMessage.parse(Array(try #require(request.httpBody)))
        #expect(sent.questions.first?.name == "example.com")
    }

    @Test func quad9NeverSendsAddressesOrLocalNames() async {
        let client = FakeEndpointClient { _ in (200, Data(Quad9Captures.ok), [:]) }
        let quad9 = Quad9Client(client: client)
        for host in ["93.184.215.14", "[2606:2800::1]", "localhost", "printer.local", "nas", "router.home.arpa", "a.b.internal", "x.onion"] {
            #expect(await quad9.check(host, deadline: .now + .seconds(2)) == .unknown, "\(host)")
        }
        #expect(client.requests.isEmpty)
    }

    @Test func quad9FailuresAreUnknownAndBackOff() async {
        let client = FakeEndpointClient { _ in (503, Data(), [:]) }
        let quad9 = Quad9Client(client: client)
        #expect(await quad9.check("example.com", deadline: .now + .seconds(2)) == .unknown)
        #expect(await quad9.check("example.org", deadline: .now + .seconds(2)) == .unknown)
        #expect(client.requests.count == 1) // backing off

        let broken = FakeEndpointClient { _ in (200, Data([1, 2, 3]), [:]) }
        #expect(await Quad9Client(client: broken).check("example.com", deadline: .now + .seconds(2)) == .unknown)
        let offline = FakeEndpointClient { _ in nil }
        #expect(await Quad9Client(client: offline).check("example.com", deadline: .now + .seconds(2)) == .unknown)
    }
}

@Suite("RDAP")
struct RDAPTests {
    static let rohlik = Data("""
    {"objectClassName":"domain","handle":"rohlik.cz","ldhName":"rohlik.cz",
     "events":[{"eventAction":"expiration","eventDate":"2027-01-24T00:00:00+01:00"},
               {"eventAction":"registration","eventDate":"2004-01-24T20:46:08.123Z"},
               {"eventAction":"last changed","eventDate":"2024-01-01T10:00:00Z"}],
     "status":["active"]}
    """.utf8)

    @Test func registrationDate() {
        #expect(RDAPClient.registrationDate(from: Self.rohlik) == "2004-01-24")
        // A registration late on 13 April UTC is 14 April in Prague (CEST, UTC+2).
        let late = Data(#"{"events":[{"eventAction":"registration","eventDate":"2020-04-13T23:30:00Z"}]}"#.utf8)
        #expect(RDAPClient.registrationDate(from: late) == "2020-04-14")
        let offset = Data(#"{"events":[{"eventAction":"Registration","eventDate":"2026-09-24T08:00:00-04:00"}]}"#.utf8)
        #expect(RDAPClient.registrationDate(from: offset) == "2026-09-24")
        let dateOnly = Data(#"{"events":[{"eventAction":"registration","eventDate":"2026-09-27"}]}"#.utf8)
        #expect(RDAPClient.registrationDate(from: dateOnly) == "2026-09-27")
        for json in [#"{"events":[]}"#, #"{"ldhName":"x.cz"}"#, #"{"events":[{"eventAction":"expiration","eventDate":"2027-01-01T00:00:00Z"}]}"#,
                     #"{"events":[{"eventAction":"registration","eventDate":"yesterday"}]}"#, "not json", "[]"] {
            #expect(RDAPClient.registrationDate(from: Data(json.utf8)) == nil, "\(json)")
        }
    }

    @Test func bundledBootstrap() {
        let b = RDAPBootstrap.bundled
        #expect(b.server(forTLD: "cz")?.absoluteString == "https://rdap.nic.cz/")
        #expect(b.server(forTLD: "COM")?.absoluteString == "https://rdap.verisign.com/com/v1/")
        #expect(b.server(forTLD: "top")?.absoluteString == "https://rdap.zdnsgtld.com/top/")
        #expect(b.server(forTLD: "cc")?.host() == "tld-rdap.verisign.com")
        #expect(b.server(forTLD: "no-such-tld") == nil)
    }

    @Test func registryLabels() {
        let b = RDAPBootstrap.bundled
        #expect(RDAPClient.registryLabel(tld: "cz", server: b.server(forTLD: "cz")!) == "CZ.NIC")
        #expect(RDAPClient.registryLabel(tld: "com", server: b.server(forTLD: "com")!) == "Verisign")
        #expect(RDAPClient.registryLabel(tld: "cc", server: b.server(forTLD: "cc")!) == "Verisign")
        #expect(RDAPClient.registryLabel(tld: "top", server: b.server(forTLD: "top")!) == "ZDNS")
        #expect(RDAPClient.registryLabel(tld: "xyz", server: b.server(forTLD: "xyz")!) == "rdap.centralnic.com")
    }

    @Test func lookupFollowsTheBootstrapAndCaches() async throws {
        let client = FakeEndpointClient { request in
            request.url?.absoluteString == "https://rdap.nic.cz/domain/rohlik.cz" ? (200, RDAPTests.rohlik, [:]) : (404, Data(), [:])
        }
        let rdap = RDAPClient(client: client)
        #expect(await rdap.lookup("Rohlik.cz", deadline: .now + .seconds(3)) == RDAPRegistration(registered: "2004-01-24", registry: "CZ.NIC"))
        #expect(await rdap.lookup("rohlik.cz", deadline: .now + .seconds(3)) == RDAPRegistration(registered: "2004-01-24", registry: "CZ.NIC"))
        #expect(client.requests.count == 1)
        #expect(client.requests.first?.value(forHTTPHeaderField: "Accept")?.contains("application/rdap+json") == true)
    }

    @Test func aRedirectMeansUnknown() async {
        let client = FakeEndpointClient { _ in (302, Data(), ["Location": "https://127.0.0.1/domain/rohlik.cz"]) }
        let rdap = RDAPClient(client: client)
        #expect(await rdap.lookup("rohlik.cz", deadline: .now + .seconds(3)) == RDAPRegistration(registered: nil, registry: "CZ.NIC"))
        #expect(client.requests.map { $0.url?.host() } == ["rdap.nic.cz"])
    }

    @Test func coalescedCallersKeepTheirOwnDeadlines() async {
        let client = FakeEndpointClient(delay: .milliseconds(1500)) { _ in (200, RDAPTests.rohlik, [:]) }
        let rdap = RDAPClient(client: client)
        let unknown = RDAPRegistration(registered: nil, registry: "CZ.NIC")
        // The first caller starts the lookup with plenty of time.
        let first = Task { await rdap.lookup("rohlik.cz", deadline: .now + .seconds(5)) }
        try? await Task.sleep(for: .milliseconds(100))
        // A second caller joins it with a short deadline: it gets "unknown" on time.
        let start = ContinuousClock.now
        #expect(await rdap.lookup("rohlik.cz", deadline: .now + .milliseconds(200)) == unknown)
        #expect(ContinuousClock.now - start < .milliseconds(600))
        // A third joins and is cancelled: it stops waiting at once.
        let third = Task { await rdap.lookup("rohlik.cz", deadline: .now + .seconds(5)) }
        try? await Task.sleep(for: .milliseconds(50))
        let cancelled = ContinuousClock.now
        third.cancel()
        #expect(await third.value == unknown)
        #expect(ContinuousClock.now - cancelled < .milliseconds(400))
        // The shared lookup carries on for the first caller and fills the cache.
        #expect(await first.value == RDAPRegistration(registered: "2004-01-24", registry: "CZ.NIC"))
        #expect(await rdap.lookup("rohlik.cz", deadline: .now + .milliseconds(50)) == RDAPRegistration(registered: "2004-01-24", registry: "CZ.NIC"))
        #expect(client.requests.count == 1)
    }

    @Test func missingDataIsUnknownNeverOld() async {
        let client = FakeEndpointClient { request in
            switch request.url?.host() {
            case "rdap.verisign.com": return (404, Data(), [:])
            case "rdap.zdnsgtld.com": return (429, Data(), ["Retry-After": "120"])
            default: return nil
            }
        }
        let rdap = RDAPClient(client: client)
        #expect(await rdap.lookup("neexistuje-bq.com", deadline: .now + .seconds(3)) == RDAPRegistration(registered: nil, registry: "Verisign"))
        #expect(await rdap.lookup("vyhra-iphone17-cz.top", deadline: .now + .seconds(3)) == RDAPRegistration(registered: nil, registry: "ZDNS"))
        // Throttled: the registry is not asked again for a while.
        #expect(await rdap.lookup("jina-domena.top", deadline: .now + .seconds(3)) == RDAPRegistration(registered: nil, registry: "ZDNS"))
        #expect(client.requests.count == 2)
        // A TLD without an RDAP server, IPs and local names send nothing.
        for name in ["example.invalid-tld-bq", "93.184.215.14", "localhost", "nas.local"] {
            #expect(await rdap.lookup(name, deadline: .now + .seconds(3)) == RDAPRegistration())
        }
        #expect(client.requests.count == 2)
    }

    @Test func queuedLookupsRespectABackOff() async {
        // The first request is throttled; the second, queued for its turn a second later, is not sent.
        let client = FakeEndpointClient { _ in (503, Data(), ["Retry-After": "120"]) }
        let rdap = RDAPClient(client: client)
        async let first = rdap.lookup("a-bq.cz", deadline: .now + .seconds(5))
        async let second = rdap.lookup("b-bq.cz", deadline: .now + .seconds(5))
        let unknown = RDAPRegistration(registered: nil, registry: "CZ.NIC")
        #expect(await [first, second] == [unknown, unknown])
        #expect(client.requests.count == 1)
    }

    @Test func requestsToOneRegistryAreSpacedOut() async {
        let client = FakeEndpointClient { _ in (200, RDAPTests.rohlik, [:]) }
        let rdap = RDAPClient(client: client)
        let start = ContinuousClock.now
        _ = await rdap.lookup("a-bq.cz", deadline: .now + .seconds(5))
        _ = await rdap.lookup("b-bq.cz", deadline: .now + .seconds(5))
        #expect(ContinuousClock.now - start >= .milliseconds(900))
        // Without time for the next slot, the lookup gives up instead of waiting.
        #expect(await rdap.lookup("c-bq.cz", deadline: .now + .milliseconds(100)) == RDAPRegistration(registered: nil, registry: "CZ.NIC"))
        #expect(client.requests.count == 2)
    }
}

/// The real `URLSessionEndpointClient` over a mock URLProtocol: no network involved.
@Suite("Endpoint client", .serialized)
struct EndpointClientTests {
    private func reset(_ replies: [String: MockURLProtocol.Reply]) {
        MockURLProtocol.replies.withLock { $0 = replies }
        MockURLProtocol.log.withLock { $0 = [] }
    }

    @Test func redirectsAreNeverFollowed() async throws {
        reset(["https://rdap.nic.cz/domain/x-bq.cz": .init(status: 302, redirect: URL(string: "https://127.0.0.1/admin")!),
               "https://127.0.0.1/admin": .init(chunks: [Data("secret".utf8)])])
        let client = MockURLProtocol.client(maxResponseBytes: 1024)
        let (_, response) = try await client.send(URLRequest(url: URL(string: "https://rdap.nic.cz/domain/x-bq.cz")!))
        #expect(response.statusCode == 302)
        #expect(MockURLProtocol.log.withLock { $0.map(\.url) } == ["https://rdap.nic.cz/domain/x-bq.cz"])
    }

    @Test func smallBodiesArrive() async throws {
        let body = Data(repeating: 0x61, count: 3000)
        reset(["https://rdap.nic.cz/domain/ok-bq.cz": .init(headers: ["Content-Type": "application/rdap+json"],
                                                           chunks: [body.prefix(1000), body.dropFirst(1000)])])
        let (data, response) = try await MockURLProtocol.client(maxResponseBytes: 4096).send(URLRequest(url: URL(string: "https://rdap.nic.cz/domain/ok-bq.cz")!))
        #expect(response.statusCode == 200)
        #expect(data == body)
    }

    @Test func oversizedBodiesAreCutOffWhileStreaming() async {
        // 64 chunks of 16 KiB (1 MiB) without a Content-Length, against a 64 KiB budget.
        let chunk = Data(repeating: 0x7B, count: 16 * 1024)
        reset(["https://rdap.nic.cz/domain/big-bq.cz": .init(chunks: Array(repeating: chunk, count: 64))])
        let client = MockURLProtocol.client(maxResponseBytes: 64 * 1024)
        await #expect(throws: URLError.self) {
            try await client.send(URLRequest(url: URL(string: "https://rdap.nic.cz/domain/big-bq.cz")!))
        }
        try? await Task.sleep(for: .milliseconds(100))
        let sent = MockURLProtocol.log.withLock { $0.first?.chunksSent ?? 0 }
        #expect(sent < 20, "the download continued after the budget: \(sent) chunks")
    }

    @Test func declaredOversizeFailsBeforeTheBody() async {
        reset(["https://rdap.nic.cz/domain/huge-bq.cz": .init(headers: ["Content-Length": "10000000"],
                                                             chunks: Array(repeating: Data(repeating: 0, count: 1024), count: 5))])
        await #expect(throws: URLError.self) {
            try await MockURLProtocol.client(maxResponseBytes: 64 * 1024).send(URLRequest(url: URL(string: "https://rdap.nic.cz/domain/huge-bq.cz")!))
        }
    }

    @Test func onlyHTTPS() async {
        await #expect(throws: URLError.self) {
            try await MockURLProtocol.client(maxResponseBytes: 1024).send(URLRequest(url: URL(string: "http://rdap.nic.cz/")!))
        }
    }
}
