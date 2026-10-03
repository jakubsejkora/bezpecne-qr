import Foundation
import Testing
@testable import BQServices

@Suite("HTTP request serialization")
struct HTTPRequestTests {
    private func request(_ url: String, userAgent: String = HTTPRequestSerializer.defaultUserAgent) throws -> String {
        let target = try FetchTarget(url: URL(string: url)!)
        return String(decoding: HTTPRequestSerializer.get(target, userAgent: userAgent), as: UTF8.self)
    }

    @Test func exactGET() throws {
        let text = try request("https://www.Example.cz/cesta/a%20b?x=1&y=%C5%A1#fragment")
        let expected = [
            "GET /cesta/a%20b?x=1&y=%C5%A1 HTTP/1.1",
            "Host: www.example.cz",
            "User-Agent: \(HTTPRequestSerializer.defaultUserAgent)",
            "Accept: text/html,application/xhtml+xml,*/*;q=0.8",
            "Accept-Language: cs-CZ,cs;q=0.9,en;q=0.8",
            "Accept-Encoding: gzip, deflate, br",
            "Connection: close",
        ].joined(separator: "\r\n") + "\r\n\r\n"
        #expect(text == expected)
    }

    @Test func neverSendsFragmentCredentialsCookiesOrReferer() throws {
        let text = try request("https://user:secret@bank.example.cz/login#token=abc")
        #expect(!text.contains("fragment"))
        #expect(!text.contains("token=abc"))
        #expect(!text.contains("secret"))
        #expect(!text.contains("user"))
        for header in ["Cookie:", "Referer:", "Authorization:", "Origin:"] { #expect(!text.contains(header)) }
        #expect(text.hasPrefix("GET /login HTTP/1.1\r\nHost: bank.example.cz\r\n"))
    }

    @Test func emptyPathPortsAndIPLiterals() throws {
        #expect(try request("https://example.cz").hasPrefix("GET / HTTP/1.1\r\nHost: example.cz\r\n"))
        #expect(try request("https://example.cz:443/").contains("\r\nHost: example.cz\r\n"))
        #expect(try request("https://example.cz:8443/a").contains("\r\nHost: example.cz:8443\r\n"))
        #expect(try request("https://[2a00:1450:4001:80b::200e]/").contains("\r\nHost: [2a00:1450:4001:80b::200e]\r\n"))
        // Browsers read a bare number as IPv4; the Host header uses the canonical form.
        let decimal = try FetchTarget(url: URL(string: "https://3115782423/")!)
        #expect(decimal.ipLiteral != nil)
        #expect(decimal.hostHeader == "185.183.17.23")
        #expect(decimal.serverName == nil) // no SNI for IP literals
        #expect(try FetchTarget(url: URL(string: "https://example.cz./")!).serverName == "example.cz")
    }

    @Test func internationalizedHostsGoOnTheWireAsPunycode() throws {
        let idn = try FetchTarget(url: URL(string: "https://www.xn--css-cz-4nf.com/prihlaseni")!)
        #expect(idn.host == "www.xn--css-cz-4nf.com")
        #expect(idn.serverName == "www.xn--css-cz-4nf.com")
        let unicode = try FetchTarget(url: URL(string: "https://www.čsob.cz/")!)
        #expect(unicode.host == "www.xn--sob-eqa.cz")
        #expect(unicode.hostHeader == "www.xn--sob-eqa.cz")
    }

    @Test func bracketsOnlyAroundIPv6() throws {
        // Foundation parses these; the name inside must not reach DNS, SNI or Host.
        for url in ["https://[o2platba.cz]/", "https://[s.team]/q/1234567890123456789", "https://[1.2.3.4]/", "https://[example.cz/"] {
            if let u = URL(string: url) {
                #expect(throws: FetchError.invalidRequest, "\(url)") { try FetchTarget(url: u) }
            }
        }
        let v6 = try FetchTarget(url: URL(string: "https://[2606:4700::1111]:8443/x")!)
        #expect(v6.ipLiteral?.family == .v6)
        #expect(v6.hostHeader == "[2606:4700::1111]:8443")
    }

    @Test func refusesWhatShouldNotReachTheWire() {
        for url in ["http://example.cz/", "ftp://example.cz/", "https:///nohost", "https://ex%41mple.cz/", "https://-bad-.cz/",
                    "https://a..b.cz/", "https://exam ple.cz/"] {
            if let u = URL(string: url) {
                #expect(throws: FetchError.invalidRequest, "\(url)") { try FetchTarget(url: u) }
            }
        }
    }

    @Test func userAgentCannotInjectHeaders() throws {
        let text = try request("https://example.cz/", userAgent: "Agent\r\nX-Injected: 1")
        #expect(!text.contains("\r\nX-Injected"))
        #expect(text.contains("User-Agent: AgentX-Injected: 1\r\n"))
    }
}
