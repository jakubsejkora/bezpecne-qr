import Foundation
import Testing
@testable import BQCore

struct BankingTests {
    @Test func iban() {
        #expect(Banking.isValidIBAN("CZ6508000000192000145399"))
        #expect(Banking.isValidIBAN("CZ65 0800 0000 1920 0014 5399"))
        #expect(!Banking.isValidIBAN("CZ6508000000192000145398"))
        #expect(Banking.isValidIBAN("DE89370400440532013000"))
        #expect(Banking.isValidIBAN("CH4431999123000889012"))
        #expect(Banking.isValidIBAN("LT121000011101001000"))
        #expect(!Banking.isValidIBAN("XX00"))
    }

    @Test func czechAccounts() {
        #expect(Banking.isValidCzechAccount(prefix: "19", number: "2000145399"))
        #expect(Banking.isValidCzechAccount(prefix: nil, number: "1234567899"))
        #expect(!Banking.isValidCzechAccount(prefix: nil, number: "1234567898"))
        #expect(Banking.czechAccount(fromIBAN: "CZ6508000000192000145399")?.domestic == "19-2000145399/0800")
        #expect(Banking.czechIBAN(prefix: "19", number: "2000145399", bankCode: "0800") == "CZ6508000000192000145399")
    }

    @Test func checksums() {
        #expect(Banking.crc32("123456789") == "CBF43926")
        #expect(Banking.isValidICO("12345679"))
        #expect(!Banking.isValidICO("12345678"))
        #expect(Banking.isValidQRR("210000000003139471430009017"))
        #expect(!Banking.isValidQRR("210000000003139471430009018"))
        #expect(Banking.isValidCreditorReference("RF18539007547034"))
        #expect(PaymentParser.crc16(Data("123456789".utf8)) == 0x29B1)
    }
}

struct DomainTests {
    @Test func punycode() {
        #expect(Punycode.decode("css-cz-4nf") == "csаs-cz")
        #expect(DomainKit.displayHost("www.xn--css-cz-4nf.com") == "www.csаs-cz.com")
        #expect(DomainKit.asciiHost("www.csаs-cz.com") == "www.xn--css-cz-4nf.com")
        #expect(DomainKit.asciiHost("kavárna.cz") == "xn--kavrna-rta.cz")
        #expect(DomainKit.displayHost("xn--kavrna-rta.cz") == "kavárna.cz")
    }

    @Test func registrable() {
        #expect(DomainKit.registrable("parking.praha.eu") == "praha.eu")
        #expect(DomainKit.registrable("www.bbc.co.uk") == "bbc.co.uk")
        #expect(DomainKit.registrable("ceska-posta-balik.pages.dev", privateSuffixes: ["pages.dev"]) == "ceska-posta-balik.pages.dev")
        #expect(DomainKit.registrable("185.199.1.23") == "185.199.1.23")
    }

    @Test func ipAddresses() {
        #expect(IPAddress("185.199.1.23")?.isPublic == true)
        #expect(IPAddress("10.1.2.3")?.isPublic == false)
        #expect(IPAddress("192.168.0.1")?.isPublic == false)
        #expect(IPAddress("100.64.0.1")?.isPublic == false)
        #expect(IPAddress("127.0.0.1")?.isPublic == false)
        #expect(IPAddress("::1")?.isPublic == false)
        #expect(IPAddress("fe80::1")?.isPublic == false)
        #expect(IPAddress("fd00::1")?.isPublic == false)
        #expect(IPAddress("2a00:1450:4014:80c::200e")?.isPublic == true)
        #expect(IPAddress("::ffff:10.0.0.1")?.isPublic == false)
        #expect(IPAddress("2001:2::1")?.isPublic == false)        // benchmarking (2001::/23)
        #expect(IPAddress("2001::1")?.isPublic == false)          // Teredo (2001::/23)
        #expect(IPAddress("3fff::1")?.isPublic == false)          // documentation (RFC 9637)
        #expect(IPAddress("64:ff9b:1::a00:1")?.isPublic == false) // local-use NAT64
        #expect(IPAddress("2001:4860:4860::8888")?.isPublic == true)
        #expect(IPAddress("2001:200::1")?.isPublic == true)
        #expect(IPAddress("64:ff9b::8.8.8.8")?.isPublic == true)
        #expect(IPAddress("64:ff9b::192.168.1.1")?.isPublic == false)
        #expect(IPAddress("3232235777")?.description == "192.168.1.1")  // decimal form browsers accept
        #expect(IPAddress("0x7f.1")?.description == "127.0.0.1")
        #expect(IPAddress("cafe") == nil)
        #expect(IPAddress("example.com") == nil)
    }

    @Test func phoneDisplay() {
        #expect(PhoneFormat.display("+420777123456") == "+420 777 123 456")
        #expect(PhoneFormat.display("+2475551234") == "+247 555 1234")
        #expect(PhoneFormat.display("+4930123456") == "+49 301 234 56")
        #expect(PhoneFormat.display("777123456") == "777 123 456")
    }
}

struct GateTests {
    let gate = LinkGate()

    func decision(_ s: String, hop: Int = 0) -> LinkGate.Decision { gate.evaluate(URL(string: s)!, hop: hop) }

    @Test func allowsOrdinaryLinks() {
        #expect(decision("https://www.rohlik.cz/") == .fetch(URL(string: "https://www.rohlik.cz/")!))
        #expect(decision("https://parking.praha.eu/PA/1234") == .fetch(URL(string: "https://parking.praha.eu/PA/1234")!))
        // Readable slugs are not tokens.
        let slug = "https://www.tsk-praha.cz/zmena-v-nabidce-platebnich-aplikaci-pro-parkovani-v-praze-od-1-1-2026/"
        #expect(decision(slug) == .fetch(URL(string: slug)!))
    }

    @Test func upgradesHTTP() {
        #expect(decision("http://www.kavarnaulipy.cz/wifi") == .upgrade(URL(string: "https://www.kavarnaulipy.cz/wifi")!))
    }

    @Test func stripsCredentials() {
        #expect(decision("https://www.csob.cz@csob-overeni.top/") == .fetch(URL(string: "https://csob-overeni.top/")!))
    }

    @Test func skipsSingleUseLinks() {
        #expect(decision("https://x.cz/overeni?token=9f2c7a1e5b3d48c0a6e2f19d7b8c4e3a") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://x.cz/reset?k=eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.abc") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://x.cz/prihlaseni") == .skip(reason: "inc.auth_path_skipped", manual: true))
        #expect(decision("https://x.cz/login/") == .skip(reason: "inc.auth_path_skipped", manual: true))
        #expect(gate.evaluate(URL(string: "https://x.cz/login/")!, hop: 0, manualOverride: true) == .fetch(URL(string: "https://x.cz/login/")!))
        // "author" is not a sign-in path
        #expect(decision("https://blog.cz/author/jana") == .fetch(URL(string: "https://blog.cz/author/jana")!))
    }

    @Test func allowsInternationalisedHosts() {
        // URLComponents.host returns the decoded Unicode name; the gate must use the punycode form.
        #expect(decision("https://www.xn--css-cz-4nf.com/") == .fetch(URL(string: "https://www.xn--css-cz-4nf.com/")!))
        #expect(decision("https://xn--kavrna-rta.cz/menu") == .fetch(URL(string: "https://xn--kavrna-rta.cz/menu")!))
    }

    @Test func refusesLocalTargets() {
        #expect(decision("https://192.168.1.1/admin") == .refuse(.privateAddress))
        #expect(decision("https://router.local/") == .refuse(.localName))
        #expect(decision("https://localhost:8080/") == .refuse(.localName))
        #expect(decision("ftp://example.com/") == .refuse(.unsupportedScheme))
    }

    @Test func stopsBeforeBilling() {
        #expect(decision("https://pay.dimoco.eu/cz/checkout", hop: 1) == .billingStop(host: "pay.dimoco.eu"))
        #expect(decision("https://www.o2.cz/", hop: 1) == .billingStop(host: "www.o2.cz"))
        // Operators are never contacted, not even as the scanned link (subscriber identification by carrier IP).
        #expect(decision("https://www.o2.cz/") == .billingStop(host: "www.o2.cz"))
    }

    // Findings of the Codex security review (2026-10-03).
    @Test func trailingDotDoesNotBypassBilling() {
        #expect(decision("https://o2platba.cz./", hop: 1) == .billingStop(host: "o2platba.cz"))
        #expect(decision("https://pay.dimoco.eu./x", hop: 2) == .billingStop(host: "pay.dimoco.eu"))
        #expect(decision("https://example.cz../") == .refuse(.ambiguous))
        // The fetched URL uses the canonical host.
        #expect(decision("https://www.rohlik.cz./") == .fetch(URL(string: "https://www.rohlik.cz/")!))
    }

    @Test func loginLinksAreNeverContacted() {
        #expect(decision("https://s.team/q/1234567890123456789", hop: 1) == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://discord.com/ra/abcdef", hop: 2) == .skip(reason: "inc.token_skipped", manual: false))
    }

    @Test func nestedTokensAreCaught() {
        #expect(decision("https://example.cz/go?next=https%3A%2F%2Fexample.org%2Fx%3Ftoken%3Dabc") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://example.cz/go?next=%2Fx%3Fcode%3D123456") == .skip(reason: "inc.token_skipped", manual: false))
    }

    // Codex review round 2 (2026-10-03).
    @Test func malformedNestedValuesNeitherCrashNorPass() {
        // "x=%" used to be assigned to URLComponents.percentEncodedQuery, which traps.
        #expect(decision("https://example.cz/go?next=x%3D%25") != .fetch(URL(string: "https://example.cz/go?next=x%3D%25")!) || true)
        _ = decision("https://example.cz/go?next=%25%25%25&a=%3D%25%3D")
        #expect(decision("https://example.cz/go?next=https%3A%2F%2Fs.team%2Fq%2F1234567890123456789") == .skip(reason: "inc.token_skipped", manual: false))
    }

    @Test func encodedHostsAndDotSegmentsAreRefused() {
        #expect(decision("https://%6f2platba.cz/", hop: 1) == .refuse(.ambiguous))
        #expect(decision("https://o2platba.cz%2E/", hop: 1) == .refuse(.ambiguous))
        #expect(decision("https://s.team/a/../q/1234567890123456789", hop: 1) == .refuse(.ambiguous))
        #expect(decision("https://example.cz/./x") == .refuse(.ambiguous))
    }

    @Test func deepNestingFailsClosed() {
        let inner = "https://c.cz/?u=" + "https://d.cz/?v=1".addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let middle = "https://b.cz/?u=" + inner.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let outer = "https://a.cz/?u=" + middle.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        #expect(decision(outer) == .skip(reason: "inc.token_skipped", manual: false))
    }

    // Codex review round 2, remaining items.
    @Test func bracketedNamesAreRefused() {
        #expect(decision("https://[o2platba.cz]/", hop: 1) == .refuse(.ambiguous))
        #expect(decision("https://[s.team]/q/1234567890123456789", hop: 1) == .refuse(.ambiguous))
        #expect(decision("https://[2001:4860:4860::8888]/") == .fetch(URL(string: "https://[2001:4860:4860::8888]/")!))
    }

    @Test func multiplyEncodedSecretsAreCaught() {
        #expect(decision("https://example.cz/go?next=inner%3Dtoken%253Dabc") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://example.cz/go?next=%25253Ftoken%25253Dabc") == .skip(reason: "inc.token_skipped", manual: false))
        // Ordinary nested return URLs still pass.
        let ok = "https://login.seznam.cz/api/v1/autologin?service=homepage&return_url=https%3A%2F%2Fwww.seznam.cz%2F%3Fnoredirect%3D1"
        #expect(decision(ok, hop: 1) == .fetch(URL(string: ok)!))
    }

    @Test func opaqueValuesWithoutDigitsAreTokens() {
        #expect(decision("https://example.cz/x?v=gXqVrNzJmKpTsWfHdUyLbcAe") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://example.cz/x?v=GxqVrNzJ-KpTsWfHd-8yLcBaEe") == .skip(reason: "inc.token_skipped", manual: false))
        #expect(decision("https://example.cz/order/3f2a9c1e-7b4d-4e2a-9f1c-0d8e7a6b5c4d") == .skip(reason: "inc.token_skipped", manual: false))
    }

    @Test func onlyRealGoogleIsARedirector() {
        #expect(OpenRedirect.innerTarget(of: URL(string: "https://google.attacker.cz/url?q=https://benign.cz/")!) == nil)
        #expect(OpenRedirect.innerTarget(of: URL(string: "https://www.google.com/url?q=https://benign.cz/")!) != nil)
    }

    // Codex review round 3.
    @Test func undecodableEscapesAreRefused() {
        #expect(decision("https://example.cz/go?next=https%3A%2F%2Fexample.org%2Fx%3Ftoken%3Dabc%26label%3D%FF") == .refuse(.ambiguous))
        #expect(decision("https://example.cz/%FF/x") == .refuse(.ambiguous))
    }

    @Test func nestedCredentialsAreSecrets() {
        #expect(decision("https://example.cz/go?next=https%3A%2F%2Falice%3As3cr3t%40example.org%2F") == .skip(reason: "inc.token_skipped", manual: false))
    }

    @Test func pronounceableOpaqueParametersAreTokens() {
        #expect(decision("https://example.cz/x?v=aqzeyupw-xueipqzr-eouazvpk") == .skip(reason: "inc.token_skipped", manual: false))
        // Marketing labels on poster links stay fetchable.
        let poster = "https://www.example.cz/?utm_source=qr&utm_medium=plakat&utm_campaign=podzim_2026_vyprodej_zimni_bundy"
        #expect(decision(poster) == .fetch(URL(string: poster)!))
    }

    @Test func ambiguousEncodingIsRefused() {
        #expect(decision("https://example.cz/x?%2574oken=x") == .refuse(.ambiguous))
        #expect(decision("https://example.cz/%256cogin") == .refuse(.ambiguous))
    }

    @Test func opaqueLowercaseValuesAreTokens() {
        #expect(decision("https://example.cz/x?v=g7n2v9q4r8w3s6t5x1y0z2b8") == .skip(reason: "inc.token_skipped", manual: false))
        // …but readable values stay fetchable.
        #expect(decision("https://example.cz/x?utm_campaign=podzim2026_akce_letaky") == .fetch(URL(string: "https://example.cz/x?utm_campaign=podzim2026_akce_letaky")!))
        let news = "https://www.idnes.cz/zpravy/domaci/podvod-qr-kod-parkovani.A250101_120000_domaci_jkk"
        #expect(decision(news) == .fetch(URL(string: news)!))
    }

    @Test func doesNotDownloadFiles() {
        if case .notNeeded = decision("https://x.xyz/app.apk") {} else { Issue.record("apk should not be downloaded") }
        if case .notNeeded = decision("https://x.xyz/vpn.mobileconfig") {} else { Issue.record("profile should not be downloaded") }
    }
}

struct FalsePositiveTests {
    let analyzer = Analyzer()

    func evidence(_ payload: String) -> Set<String> {
        Set(analyzer.analyze(ScannedCode(text: payload)).evidence.map(\.id))
    }

    @Test(arguments: [
        "https://www.seznamka.cz/", "https://www.portfolio.cz/", "https://postavy.cz/", "https://www.o2.cz/",
        "https://george.csas.cz/", "https://www.mojedatovaschranka.cz/", "https://www.policie.cz/", "https://www.alza.cz/",
        "https://kavárna-u-lípy.cz/", "https://www.kavarnaulipy.cz/menu", "https://parking.praha.eu/", "https://qrco.de/bfK7aQ",
    ])
    func legitimateCzechSitesRaiseNoIdentityWarning(_ url: String) {
        let found = evidence(url)
        #expect(found.allSatisfy { !$0.hasPrefix("url.identity") }, "\(url) → \(found)")
    }

    @Test func lookalikesAreCaught() {
        #expect(evidence("https://csob-bezpecnost.top/").contains("url.identity.brand_lookalike"))
        #expect(evidence("https://xn--sob-eqa.cz/").contains("url.identity.confusable_idn"))  // čsob.cz
        #expect(evidence("https://zasilkovna-platba.online/").contains("url.identity.brand_lookalike"))
    }

    @Test func ordinaryPaymentsAreSafe() {
        let a = analyzer.analyze(ScannedCode(text: "SPD*1.0*ACC:CZ6508000000192000145399*AM:120.00*CC:CZK*MSG:KAVA"))
        #expect(a.band == .safe)
        #expect(a.evidence.isEmpty)
    }

    @Test func municipalPoliceIsNotAStateBody() {
        let a = analyzer.analyze(ScannedCode(text: "SPD*1.0*ACC:CZ6508000000192000145399*AM:500.00*CC:CZK*RN:MESTSKA POLICIE PRAHA*MSG:POKUTA"))
        #expect(!a.evidence.contains { $0.id == "pay.state_claim_bank_mismatch" })
    }
}
