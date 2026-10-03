import BQCore
import Foundation
import Testing
@testable import BQServices

@Suite("Address vetting and binding")
struct AddressPolicyTests {
    private func ips(_ list: [String]) -> [BQCore.IPAddress] { list.compactMap { BQCore.IPAddress($0) } }
    private let native = TranslationContext(prefixes: [], trustsIPv6: true)

    @Test func everyAddressMustBePublic() throws {
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["10.0.0.1"]), context: native) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "10.0.0.1"]), context: native) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "::1"]), context: native) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["::ffff:192.168.1.1"]), context: native) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["64:ff9b::a00:1"]), context: native) } // well-known NAT64 of 10.0.0.1
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["fe80::1"]), context: native) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["100.64.1.1"]), context: native) }
        #expect(throws: FetchError.nameNotResolved) { try AddressPolicy.vet([], context: native) }
        #expect(try AddressPolicy.vet(ips(["93.184.215.14", "2606:2800:21f:cb07:6820:80da:af6b:8b2c"]), context: native).count == 2)
    }

    @Test func raceCandidates() {
        #expect(AddressPolicy.candidates(ips(["1.1.1.1", "1.0.0.1", "2606:4700::1111"])) == ips(["1.1.1.1", "2606:4700::1111"]))
        #expect(AddressPolicy.candidates(ips(["2606:4700::1111", "1.1.1.1"])) == ips(["2606:4700::1111", "1.1.1.1"]))
        #expect(AddressPolicy.candidates(ips(["1.1.1.1", "1.0.0.1", "1.1.1.2"])) == ips(["1.1.1.1", "1.0.0.1"]))
        #expect(AddressPolicy.candidates(ips(["1.1.1.1"])) == ips(["1.1.1.1"]))
        #expect(AddressPolicy.candidates([]).isEmpty)
    }

    @Test func bindingAcceptsTheVettedAddressAndItsNAT64Forms() {
        let v4 = BQCore.IPAddress("93.184.215.14")!
        func bound(_ observed: String) -> Bool { AddressPolicy.isBound(observed: BQCore.IPAddress(observed)!, vetted: v4) }
        #expect(bound("93.184.215.14"))
        #expect(bound("64:ff9b::5db8:d70e"))            // well-known prefix /96
        #expect(bound("2001:db8:64::5db8:d70e"))        // network-specific /96
        #expect(bound("2001:db8:122:344:5d:b8d7:e00::")) // /64 (byte 8 is the zero u-octet)
        #expect(!bound("93.184.215.15"))
        #expect(!bound("64:ff9b::5db8:d70f"))
        #expect(!bound("2606:2800:21f:cb07:6820:80da:af6b:8b2c"))
        let v6 = BQCore.IPAddress("2606:2800:21f:cb07:6820:80da:af6b:8b2c")!
        #expect(AddressPolicy.isBound(observed: v6, vetted: v6))
        #expect(!AddressPolicy.isBound(observed: v4, vetted: v6))
    }

    // MARK: NAT64 (RFC 6052 / RFC 7050)

    @Test func prefixDiscoveryFindsEveryLayout() {
        func prefixes(_ address: String) -> [String] { NAT64Prefix.discovered(in: BQCore.IPAddress(address)!).map(\.description) }
        #expect(prefixes("64:ff9b::c000:aa") == ["64:ff9b::/96"])
        #expect(prefixes("2001:470:64::c000:ab") == ["2001:470:64::/96"])
        #expect(prefixes("2001:db8:1c0:0:aa::") == ["2001:db8:100::/40"])
        #expect(prefixes("2001:db8:c000:aa::") == ["2001:db8::/32"])
        #expect(prefixes("2001:db8:122:344:c0:0:aa00:0") == ["2001:db8:122:344::/64"])
        #expect(prefixes("2001:db8::1").isEmpty)
        #expect(prefixes("192.0.0.170").isEmpty)
        // A /64 candidate needs the zero u-octet.
        #expect(prefixes("2001:db8:122:344:ffc0:0:aa00:0").isEmpty)
    }

    @Test func networkSpecificPrefixVetsTheEmbeddedIPv4() throws {
        let nsp = NAT64Prefix.discovered(in: BQCore.IPAddress("2001:470:64::c000:aa")!)
        let context = TranslationContext(prefixes: nsp, trustsIPv6: true)
        // 2001:470:64::c0a8:101 is global unicast, but on this network it reaches 192.168.1.1.
        #expect(BQCore.IPAddress("2001:470:64::c0a8:101")!.isPublic)
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["2001:470:64::c0a8:101"]), context: context) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "2001:470:64::a00:5"]), context: context) }
        // A synthesized address of a public IPv4 and native IPv6 outside the prefix are fine.
        #expect(try AddressPolicy.vet(ips(["2001:470:64::5db8:d70e", "2606:4700::1111"]), context: context).count == 2)
    }

    @Test func unknownTranslationUsesIPv4Only() throws {
        // IPv6-only path, prefix unknown: IPv6 answers can't be vetted.
        #expect(throws: FetchError.unverifiableAddress) { try AddressPolicy.vet(ips(["2001:470:64::c0a8:101"]), context: .unknown) }
        #expect(try AddressPolicy.vet(ips(["93.184.215.14", "2001:470:64::c0a8:101"]), context: .unknown) == ips(["93.184.215.14"]))
        // Non-public answers are refused in any case.
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["10.0.0.1", "2001:db8::1"]), context: .unknown) }
    }

    @Test func discoveryContexts() async {
        // No NAT64: ipv4only.arpa has only its A records.
        let plain = TranslationPrefixes(resolver: FakeResolver(answers: noNAT64), paths: FakePaths())
        #expect(await plain.context(deadline: .now + .seconds(2)) == TranslationContext(prefixes: [], trustsIPv6: true))
        // DNS64 with a network-specific prefix.
        let dns64 = FakeResolver(answers: ["ipv4only.arpa": ["2001:470:64::c000:aa", "2001:470:64::c000:ab", "192.0.0.170"]])
        let nat64 = TranslationPrefixes(resolver: dns64, paths: FakePaths(ipv6Only: true))
        let context = await nat64.context(deadline: .now + .seconds(2))
        #expect(context.prefixes.map(\.description) == ["2001:470:64::/96"])
        #expect(context.trustsIPv6)
        // IPv6-only without a discovered prefix, and failed discovery anywhere: IPv6 is not trusted.
        let noPrefix = TranslationPrefixes(resolver: FakeResolver(answers: noNAT64), paths: FakePaths(ipv6Only: true))
        #expect(await noPrefix.context(deadline: .now + .seconds(2)) == .unknown)
        let failing = TranslationPrefixes(resolver: FakeResolver(answers: [:]), paths: FakePaths())
        #expect(await failing.context(deadline: .now + .seconds(2)) == .unknown)
    }

    @Test func discoveryIsCachedPerNetworkPath() async {
        let resolver = FakeResolver(answers: noNAT64)
        let paths = FakePaths(signature: "wifi-1")
        let translation = TranslationPrefixes(resolver: resolver, paths: paths)
        _ = await translation.context(deadline: .now + .seconds(2))
        _ = await translation.context(deadline: .now + .seconds(2))
        #expect(resolver.calls == ["ipv4only.arpa"])
        paths.set(signature: "cellular-1", ipv6Only: true)
        #expect(await translation.context(deadline: .now + .seconds(2)) == .unknown) // no prefix on an IPv6-only path
        #expect(resolver.calls == ["ipv4only.arpa", "ipv4only.arpa"])
    }

    @Test func vetterAppliesTheNetworkPrefix() async throws {
        let answers = ["ipv4only.arpa": ["2001:470:64::c000:aa"], "tiskarna-bq.cz": ["2001:470:64::c0a8:101"],
                       "obchod-bq.cz": ["2001:470:64::5db8:d70e"], "v6only-bq.cz": ["2606:4700::1111"]]
        let vetter = testVetter(answers, paths: FakePaths(ipv6Only: true))
        await #expect(throws: FetchError.nonPublicAddress) { try await vetter.vet("tiskarna-bq.cz", deadline: .now + .seconds(2)) }
        #expect(try await vetter.vet("obchod-bq.cz", deadline: .now + .seconds(2)).count == 1)
        #expect(try await vetter.vet("v6only-bq.cz", deadline: .now + .seconds(2)).count == 1)
        // IPv6 literals go through the same rules.
        await #expect(throws: FetchError.nonPublicAddress) { try await vetter.vet("2001:470:64::c0a8:101", deadline: .now + .seconds(2)) }

        // Same answers on an IPv6-only network whose prefix could not be discovered.
        let blind = testVetter(answers.filter { $0.key != "ipv4only.arpa" }, paths: FakePaths(ipv6Only: true))
        await #expect(throws: FetchError.unverifiableAddress) { try await blind.vet("tiskarna-bq.cz", deadline: .now + .seconds(2)) }
        await #expect(throws: FetchError.unverifiableAddress) { try await blind.vet("v6only-bq.cz", deadline: .now + .seconds(2)) }
    }

    // MARK: SafeFetcher never connects to a refused name

    private func fetcher(_ answers: [String: [String]], paths: FakePaths = FakePaths(), counter: ConnectionCounter) -> SafeFetcher {
        SafeFetcher(vetter: testVetter(answers, paths: paths), configuration: .init(), connector: counter.connector)
    }

    @Test func publicNameResolvingToAPrivateAddressIsNeverContacted() async {
        let counter = ConnectionCounter()
        let safe = fetcher(noNAT64.merging(["tiskarna-kancelar.cz": ["10.0.0.1"], "mixed.cz": ["93.184.215.14", "192.168.0.10"]]) { $1 },
                           counter: counter)
        for url in ["https://tiskarna-kancelar.cz/", "https://mixed.cz/admin"] {
            await #expect(throws: FetchError.nonPublicAddress) {
                try await safe.fetch(FetchRequest(url: URL(string: url)!, deadline: .now + .seconds(2)))
            }
        }
        await #expect(throws: FetchError.nameNotResolved) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://neexistuje.cz/")!, deadline: .now + .seconds(2)))
        }
        // IP literals are vetted without DNS.
        for url in ["https://127.0.0.1/", "https://[::1]/", "https://2130706433/", "https://169.254.169.254/latest/meta-data"] {
            await #expect(throws: FetchError.nonPublicAddress) {
                try await safe.fetch(FetchRequest(url: URL(string: url)!, deadline: .now + .seconds(2)))
            }
        }
        #expect(counter.value == 0)
    }

    @Test func networkSpecificNAT64AddressIsNeverContacted() async {
        let counter = ConnectionCounter()
        let safe = fetcher(["ipv4only.arpa": ["2001:470:64::c000:aa"], "rebind-bq.cz": ["2001:470:64::c0a8:101"]],
                           paths: FakePaths(ipv6Only: true), counter: counter)
        await #expect(throws: FetchError.nonPublicAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://rebind-bq.cz/")!, deadline: .now + .seconds(2)))
        }
        await #expect(throws: FetchError.nonPublicAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://[2001:470:64::c0a8:101]/")!, deadline: .now + .seconds(2)))
        }
        #expect(counter.value == 0)
    }

    @Test func systemResolverResultsAreVettedToo() async {
        // "localhost" resolves offline through the hosts file — to loopback, which must be refused.
        let counter = ConnectionCounter()
        let resolver = SystemResolver()
        let safe = SafeFetcher(vetter: AddressVetter(resolver: resolver, translation: TranslationPrefixes(resolver: FakeResolver(answers: noNAT64), paths: FakePaths())),
                               configuration: .init(), connector: counter.connector)
        await #expect(throws: FetchError.nonPublicAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://localhost/")!, deadline: .now + .seconds(2)))
        }
        #expect(counter.value == 0)
    }

    @Test func refusesNonHTTPS() async {
        let counter = ConnectionCounter()
        await #expect(throws: FetchError.invalidRequest) {
            try await fetcher([:], counter: counter).fetch(FetchRequest(url: URL(string: "http://example.cz/")!, deadline: .now + .seconds(2)))
        }
        #expect(counter.value == 0)
    }

    @Test func cancellationDuringResolution() async {
        struct SlowResolver: HostResolver {
            func resolve(_ host: String, deadline: Deadline) async throws(FetchError) -> [BQCore.IPAddress] {
                do { try await Task.sleep(for: .seconds(5)) } catch { throw .cancelled }
                return [BQCore.IPAddress("93.184.215.14")!]
            }
        }
        let counter = ConnectionCounter()
        let vetter = AddressVetter(resolver: SlowResolver(), translation: TranslationPrefixes(resolver: FakeResolver(answers: noNAT64), paths: FakePaths()))
        let safe = SafeFetcher(vetter: vetter, configuration: .init(), connector: counter.connector)
        let task = Task { await fetchResult(safe, FetchRequest(url: URL(string: "https://slow-dns-bq.cz/")!)) }
        try? await Task.sleep(for: .milliseconds(50))
        let start = ContinuousClock.now
        task.cancel()
        #expect(await task.value == .failure(.cancelled))
        #expect(ContinuousClock.now - start < .milliseconds(500))
        #expect(counter.value == 0)
    }

    @Test func expiredDeadline() async {
        await #expect(throws: FetchError.timeout) {
            try await SafeFetcher().fetch(FetchRequest(url: URL(string: "https://www.example.com/")!, deadline: .now - .seconds(1)))
        }
    }
}
