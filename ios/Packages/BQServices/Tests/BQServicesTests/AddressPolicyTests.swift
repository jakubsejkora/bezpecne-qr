import BQCore
import Foundation
import Testing
@testable import BQServices

@Suite("Address vetting and binding")
struct AddressPolicyTests {
    private func ips(_ list: [String]) -> [BQCore.IPAddress] { list.compactMap { BQCore.IPAddress($0) } }

    @Test func everyAddressMustBePublic() throws {
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["10.0.0.1"])) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "10.0.0.1"])) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "::1"])) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["93.184.215.14", "fe80::1"])) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["::ffff:192.168.1.1"])) }
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["64:ff9b::a00:1"])) } // well-known NAT64 of 10.0.0.1
        #expect(throws: FetchError.nonPublicAddress) { try AddressPolicy.vet(ips(["100.64.1.1"])) }
        #expect(throws: FetchError.nameNotResolved) { try AddressPolicy.vet([]) }
    }

    @Test func onlyIPv4AnswersAreConnectedTo() throws {
        // A translator with any prefix may turn an IPv6 answer into a private IPv4 destination:
        // 2001:470:64::c0a8:101 is global unicast, yet through 2001:470:64::/96 it reaches 192.168.1.1.
        #expect(BQCore.IPAddress("2001:470:64::c0a8:101")!.isPublic)
        #expect(try AddressPolicy.vet(ips(["93.184.215.14", "2001:470:64::c0a8:101", "104.20.23.154"]))
            == ips(["93.184.215.14", "104.20.23.154"]))
        #expect(throws: FetchError.unverifiableAddress) { try AddressPolicy.vet(ips(["2001:470:64::c0a8:101"])) }
        #expect(throws: FetchError.unverifiableAddress) { try AddressPolicy.vet(ips(["2606:4700::1111", "2606:4700::1001"])) }
    }

    @Test func raceCandidates() {
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

    @Test func vetterNeverUsesIPv6Answers() async throws {
        let resolver = FakeResolver(answers: ["tiskarna-bq.cz": ["2001:470:64::c0a8:101"], "dual-bq.cz": ["93.184.215.14", "2606:4700::1111"]])
        let vetter = AddressVetter(resolver: resolver)
        await #expect(throws: FetchError.unverifiableAddress) { try await vetter.vet("tiskarna-bq.cz", deadline: .now + .seconds(2)) }
        await #expect(throws: FetchError.unverifiableAddress) { try await vetter.vet("[2001:470:64::c0a8:101]", deadline: .now + .seconds(2)) }
        await #expect(throws: FetchError.unverifiableAddress) { try await vetter.vet("[2606:4700::1111]", deadline: .now + .seconds(2)) }
        #expect(try await vetter.vet("dual-bq.cz", deadline: .now + .seconds(2)) == [BQCore.IPAddress("93.184.215.14")!])
        #expect(!resolver.calls.contains("ipv4only.arpa")) // no NAT64 discovery anymore
    }

    // MARK: SafeFetcher never connects to a refused name

    private func fetcher(_ answers: [String: [String]], counter: ConnectionCounter) -> SafeFetcher {
        SafeFetcher(vetter: testVetter(answers), configuration: .init(), connector: counter.connector)
    }

    @Test func publicNameResolvingToAPrivateAddressIsNeverContacted() async {
        let counter = ConnectionCounter()
        let safe = fetcher(["tiskarna-kancelar.cz": ["10.0.0.1"], "mixed.cz": ["93.184.215.14", "192.168.0.10"]], counter: counter)
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

    @Test func ipv6OnlyNamesAreNeverContacted() async {
        let counter = ConnectionCounter()
        let safe = fetcher(["rebind-bq.cz": ["2001:470:64::c0a8:101"]], counter: counter)
        await #expect(throws: FetchError.unverifiableAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://rebind-bq.cz/")!, deadline: .now + .seconds(2)))
        }
        await #expect(throws: FetchError.unverifiableAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://[2001:470:64::c0a8:101]/")!, deadline: .now + .seconds(2)))
        }
        #expect(counter.value == 0)
    }

    @Test func systemResolverResultsAreVettedToo() async {
        // "localhost" resolves offline through the hosts file — to loopback, which must be refused.
        let counter = ConnectionCounter()
        let resolver = SystemResolver()
        let safe = SafeFetcher(vetter: AddressVetter(resolver: resolver), configuration: .init(), connector: counter.connector)
        await #expect(throws: FetchError.nonPublicAddress) {
            try await safe.fetch(FetchRequest(url: URL(string: "https://localhost/")!, deadline: .now + .seconds(2)))
        }
        #expect(counter.value == 0)
    }

    @Test func resolverFailuresAreNotNonExistence() {
        #expect(SystemResolver.failure(status: EAI_NONAME) == .nameNotResolved)
        #expect(SystemResolver.failure(status: EAI_NODATA) == .nameNotResolved)
        #expect(SystemResolver.failure(status: EAI_AGAIN) == .resolverFailed)
        #expect(SystemResolver.failure(status: EAI_FAIL) == .resolverFailed)
        #expect(SystemResolver.failure(status: EAI_SYSTEM) == .resolverFailed)
    }

    @Test func vetterRejectsBracketedNames() async throws {
        let resolver = FakeResolver(answers: ["o2platba.cz": ["93.184.215.14"]])
        let vetter = AddressVetter(resolver: resolver)
        for host in ["[o2platba.cz]", "[1.2.3.4]", "[o2platba.cz", "o2platba.cz]"] {
            await #expect(throws: FetchError.invalidRequest, "\(host)") { try await vetter.vet(host, deadline: .now + .seconds(2)) }
        }
        #expect(resolver.calls.isEmpty)
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
        let vetter = AddressVetter(resolver: SlowResolver())
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
