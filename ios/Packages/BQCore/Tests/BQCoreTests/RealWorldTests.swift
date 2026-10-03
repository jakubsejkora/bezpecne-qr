import Foundation
import Testing
@testable import BQCore

/// Payload variants seen in the wild that the corpus doesn't cover.
struct RealWorldTests {
    let analyzer = Analyzer()

    func analyze(_ s: String) -> Analysis { analyzer.analyze(ScannedCode(text: s)) }

    @Test func spdVariants() throws {
        let iban = Banking.czechIBAN(prefix: nil, number: "1234567899", bankCode: "0100")
        // Lower-case header, IBAN+BIC, trailing newline
        let a = analyze("spd*1.0*ACC:\(iban)+KOMBCZPP*AM:99.9*CC:CZK*X-VS:42\n")
        #expect(a.type == .spd)
        guard case .payment(let p) = a.content else { Issue.record("not a payment"); return }
        #expect(p.bic == "KOMBCZPP")
        #expect(p.amount == "99.90")
        #expect(p.bankName == "Komerční banka, a.s.")
        #expect(!a.invalid)
        #expect(a.band == .safe)
        // Percent-encoded asterisk in the message
        let b = analyze("SPD*1.0*ACC:\(iban)*AM:10*MSG:FAKTURA %2A 12")
        guard case .payment(let q) = b.content else { Issue.record("not a payment"); return }
        #expect(q.message == "FAKTURA * 12")
        // Conflicting duplicate fields block the payment
        #expect(analyze("SPD*1.0*ACC:\(iban)*AM:10*AM:20").invalid)
    }

    @Test func spdCRC() {
        let iban = Banking.czechIBAN(prefix: nil, number: "1234567899", bankCode: "0100")
        let body = "SPD*1.0*ACC:\(iban)*AM:100.00*CC:CZK"
        let good = body + "*CRC32:" + Banking.crc32(body)
        #expect(!analyze(good).invalid)
        #expect(analyze(body + "*CRC32:DEADBEEF").invalid)
    }

    @Test func linkVariants() {
        let upper = analyze("HTTPS://WWW.KAVARNAULIPY.CZ/menu")
        #expect(upper.type == .url)
        guard case .link(let l) = upper.content else { return }
        #expect(l.host == "www.kavarnaulipy.cz")
        #expect(analyze("  https://www.rohlik.cz/  \n").type == .url)
        #expect(analyze("www.rohlik.cz").type == .url)
        // A Unicode (IDN) host typed directly is normalised to punycode.
        guard case .link(let idn) = analyze("https://kavárna-u-lípy.cz/").content else { return }
        #expect(idn.host.hasPrefix("xn--"))
        #expect(idn.hostDisplay == "kavárna-u-lípy.cz")
    }

    @Test func wifiEscapes() {
        guard case .wifi(let w) = analyze("WIFI:S:Moje\\;Sit;T:WPA;P:he\\;slo\\\\;;").content else { Issue.record("not wifi"); return }
        #expect(w.ssid == "Moje;Sit")
        #expect(w.password == "he;slo\\")
        #expect(w.security == "WPA2")
        guard case .wifi(let sae) = analyze("WIFI:T:SAE;S:Domov;P:12345678;;").content else { return }
        #expect(sae.security == "WPA3")
    }

    @Test func vcard21QuotedPrintable() {
        let card = "BEGIN:VCARD\r\nVERSION:2.1\r\nN;CHARSET=UTF-8;ENCODING=QUOTED-PRINTABLE:Nov=C3=A1k;Jan\r\nTEL;CELL:+420 777 123 456\r\nEND:VCARD"
        guard case .contact(let c) = analyze(card).content else { Issue.record("not a contact"); return }
        #expect(c.name == "Jan Novák")
        #expect(c.tels == ["+420 777 123 456"])
        #expect(c.format == "vCard 2.1")
    }

    @Test func eventInUTC() {
        let ics = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nSUMMARY:Schůzka\nDTSTART:20261012T160000Z\nDTEND:20261012T170000Z\nEND:VEVENT\nEND:VCALENDAR"
        guard case .event(let e) = analyze(ics).content else { Issue.record("not an event"); return }
        #expect(e.start == "2026-10-12T18:00") // CEST = UTC+2
        #expect(e.summary == "Schůzka")
    }

    @Test func commVariants() {
        guard case .sms(let s) = analyze("sms:+420777123456?body=Ahoj%20sv%C4%9Bte").content else { Issue.record("not sms"); return }
        #expect(s.body == "Ahoj světe")
        guard case .phone(let p) = analyze("tel:777123456").content else { Issue.record("not tel"); return }
        #expect(p.numberDisplay == "777 123 456")
        #expect(p.country == "CZ")
        guard case .email(let m) = analyze("mailto:info@kavarnaulipy.cz").content else { Issue.record("not mail"); return }
        #expect(m.to == "info@kavarnaulipy.cz")
        let premium = analyze("SMSTO:90211999:START")
        guard case .sms(let ps) = premium.content else { return }
        #expect(ps.premium?.billing == "received")
        #expect(ps.premium?.price == "999 Kč")
        #expect(premium.evidence.map(\.id).contains("sms.activation_keyword"))
    }

    @Test func cryptoVariants() {
        guard case .crypto(let c) = analyze("bitcoin:bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4").content else { Issue.record("not crypto"); return }
        #expect(c.amount == nil)
        #expect(analyze("bitcoin:bc1qxyz?amount=0.1&req-somethingnew=1").invalid)
        guard case .crypto(let e) = analyze("ethereum:0x8e23Ee67d1332aD560396262C48ffbB01f93d052?value=2.5e18").content else { return }
        #expect(e.amount == "2.5")
        #expect(e.unit == "ETH")
    }

    @Test func textAndNumbers() {
        #expect(analyze("12345").type == .text)
        #expect(analyze("Navštivte nás na www.kavarnaulipy.cz!").type == .text)
        let scam = analyze("Váš účet je napaden, převeďte úspory na bezpečný účet.")
        #expect(scam.band == .danger)
        #expect(analyze("Dobrý den").band == .info)
    }

    @Test func noCrashOnGarbage() {
        for s in ["", " ", "http://", "https://@", "SPD*", "WIFI:", "BEGIN:VCARD", "tel:", "sms:", "geo:abc", "otpauth://", "data:",
                  "bitcoin:", "ethereum:", "lightning:lnbc1", "intent://#Intent;end", "MECARD:", "SPC\n", "BCD\n", String(repeating: "A", count: 5000)] {
            _ = analyze(s)
        }
    }

    @Test func shopSubscriptionIsNotCarrierBilling() {
        // rohlik.cz homepage, observed 2026-10-03: a shop programme, no phone sign-up.
        let page = PageFacts(title: "Online supermarket Rohlik.cz", extract: ["4× měsíčně malé nákupy od 1 Kč", "Doprava vždy zdarma"],
                             asks: [], offer: Offer(text: "4× měsíčně malé nákupy od 1 Kč", promise: "Doprava vždy zdarma"))
        let inspection = Inspection(chain: [Hop(url: "https://www.rohlik.cz/", status: 200)],
                                    final: Endpoint(url: "https://www.rohlik.cz/", host: "www.rohlik.cz", registrable: "rohlik.cz"),
                                    page: page, completeness: .complete)
        let a = analyzer.analyze(ScannedCode(text: "https://www.rohlik.cz/"), inspection: inspection)
        #expect(!a.consequences.contains { $0.id == "csq.subscription_charge" })
        #expect(a.inspection?.page?.offer == nil)
        #expect(a.band == .safe)
    }

    @Test func appStoreHandOffIsDecidedByTheInspector() {
        // A clean walk that ends in the store app is complete (the inspector says so)…
        let clean = Inspection(chain: [Hop(url: "https://apps.apple.com/cz/app/id1234567890", status: 301),
                                       Hop(url: "itms-appss://apps.apple.com/cz/app/id1234567890", stopped: .gate)],
                               completeness: .complete)
        #expect(analyzer.analyze(ScannedCode(text: "https://apps.apple.com/cz/app/id1234567890"), inspection: clean).band == .safe)
        // …and a degraded one is not promoted by the analyzer.
        let degraded = Inspection(chain: clean.chain, completeness: Completeness(.incomplete, reason: "inc.refused_scheme"))
        #expect(analyzer.analyze(ScannedCode(text: "https://apps.apple.com/cz/app/id1234567890"), inspection: degraded).completeness.state == .incomplete)
    }

    @Test func operatorWebsiteIsExplainedNotAlarmed() {
        let a = analyzer.analyze(ScannedCode(text: "https://www.o2.cz/"),
                                 inspection: Inspection(chain: [Hop(url: "https://www.o2.cz/", stopped: .billing)],
                                                        completeness: Completeness(.incomplete, reason: "inc.billing_stop")))
        #expect(a.completeness.reason == "inc.operator_skipped")
        #expect(a.consequences.map(\.id) == ["csq.operator_site"])
        #expect(a.inspection?.chain.first?.stopped == .operatorSite)
        // A redirect into a billing host is still the critical warning.
        let b = analyzer.analyze(ScannedCode(text: "https://hudba-zdarma-cz.top/go"),
                                 inspection: Inspection(chain: [Hop(url: "https://hudba-zdarma-cz.top/go", status: 302),
                                                                Hop(url: "https://pay.dimoco.eu/cz/checkout", stopped: .billing)],
                                                        completeness: Completeness(.incomplete, reason: "inc.billing_stop")))
        #expect(b.consequences.map(\.id).contains("csq.billing_gateway"))
    }
}
