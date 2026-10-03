import BQCore
import Foundation
import Testing
@testable import BQServices

/// Realistic pages for the analyzer. Domains are synthetic (see shared/testdata/samples.json).
enum Pages {
    /// (a) "Vyhrajte iPhone" carrier-billing subscription page (corpus url-dcb-subscription).
    static let dcb = """
    <!DOCTYPE html>
    <html lang="cs"><head>
    <meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Gratulujeme! Vyhrajte iPhone 17</title>
    <style>.small{font-size:9px;color:#bbb}</style>
    <script async src="https://cdn.track-cz.top/px.js"></script>
    </head>
    <body>
    <div class="hero">
      <h1>Gratulujeme! Jste dnešní vybraný návštěvník.</h1>
      <p>Vyhrajte iPhone 17 <b>zdarma</b> — stačí zadat číslo.</p>
      <img src="/iphone.png" alt="iPhone 17">
    </div>
    <form action="/subscribe" method="post">
      <label for="msisdn">Telefonní číslo:</label>
      <input id="msisdn" name="msisdn" type="tel" placeholder="+420" autocomplete="off">
      <input type="hidden" name="cid" value="8812">
      <button type="submit">Pokračovat</button>
    </form>
    <p class="small">Předplatné 99&nbsp;Kč/týden, účtováno operátorem. Zrušíte SMS STOP na 90211.</p>
    <!-- <p>Hidden comment text</p> -->
    </body></html>
    """

    /// (b) Official-looking parking payment page (corpus url-parking-praha-official).
    static let parking = """
    <!doctype html><html lang="cs"><head><meta charset="utf-8"><title>Virtuální parkovací hodiny</title></head>
    <body><header><nav><a href="/">Úvod</a> <a href="/napoveda">Nápověda</a></nav></header>
    <main>
      <h1>Parkovací automat č. 1234</h1>
      <p>Zóna: modrá</p>
      <p>Zadejte SPZ a délku stání</p>
      <form action="https://vph.zpspraha.cz/PA/1234/platba" method="post">
        <label>SPZ vozidla <input name="spz" required></label>
        <label for="delka">Délka stání</label>
        <select id="delka" name="delka"><option>30 minut — 20 Kč</option><option>1 hodina — 40 Kč</option></select>
        <fieldset><legend>Platební karta</legend>
          <input name="cardnumber" autocomplete="cc-number" placeholder="Číslo karty">
          <input name="exp" autocomplete="cc-exp" placeholder="MM/RR">
          <input name="cvc" autocomplete="cc-csc" placeholder="CVC">
        </fieldset>
        <input type="submit" value="Zaplatit">
      </form>
      <p>Cena: 40 Kč za hodinu. Platbu potvrdíte v aplikaci banky.</p>
    </main></body></html>
    """

    /// (c) EasyPark-branded card phishing page (corpus url-parking-fake).
    static let easyparkPhish = """
    <html><head><meta charset="utf-8"><title>EasyPark — Zaplaťte parkovné</title>
    <meta property="og:site_name" content="EasyPark"></head>
    <body>
    <img src="logo.svg" alt="EasyPark logo">
    <h2>Zaplaťte parkovné v zóně P1</h2>
    <form action="https://pay-gateway.easypark-platba.top/collect.php" method="post">
      <div><span>Číslo karty</span><input type="tel" name="cc_num" inputmode="numeric"></div>
      <div><span>Platnost</span><input name="cc_exp" placeholder="MM/RR"></div>
      <div><span>CVC</span><input name="cvv2" maxlength="4"></div>
      <button>Zaplatit 40 Kč</button>
    </form>
    <p style="display:none">Toto je bezpečná platební brána EasyPark.</p>
    </body></html>
    """

    /// (d) A streaming service that clearly discloses a free trial.
    static let freeTrial = """
    <html><head><meta charset="utf-8"><title>Hudební knihovna Plus</title></head>
    <body>
    <h1>Hudba bez reklam</h1>
    <p>Vyzkoušejte prémiový účet 7 dní zdarma.</p>
    <p>Po skončení zkušebního období 149 Kč/měsíc, předplatné lze kdykoli zrušit v nastavení.</p>
    <form action="/start"><label>E-mail <input type="email" name="email"></label><button>Začít zkušební období</button></form>
    </body></html>
    """
}

@Suite("Page analyzer")
struct PageAnalyzerTests {
    let analyzer = PageAnalyzer()

    private func analyze(_ html: String, url: String = "https://example-page.cz/", charset: String? = nil, refresh: String? = nil) -> PageAnalysis {
        analyzer.analyze(Data(html.utf8), charset: charset, url: URL(string: url)!, refreshHeader: refresh)
    }

    @Test func dcbSubscriptionPage() {
        let a = analyze(Pages.dcb, url: "https://vyhra-iphone17-cz.top/lp?c=cz")
        let f = a.facts
        #expect(f.title == "Gratulujeme! Vyhrajte iPhone 17")
        #expect(f.extract == [
            "Gratulujeme! Jste dnešní vybraný návštěvník.",
            "Vyhrajte iPhone 17 zdarma — stačí zadat číslo.",
            "Telefonní číslo: [          ]",
            "[ Pokračovat ]",
            "Předplatné 99 Kč/týden, účtováno operátorem. Zrušíte SMS STOP na 90211.",
        ])
        #expect(f.asks == [.phone])
        let offer = f.offer
        #expect(offer != nil)
        #expect(offer?.text == "Předplatné 99 Kč/týden, účtováno operátorem")
        #expect(offer?.promise == "Vyhrajte iPhone 17 zdarma")
        #expect(offer?.highlight == [4])
        #expect(f.brandClaim == nil)
        #expect(f.foreignFormHosts.isEmpty)
        #expect(!a.scriptOnly)
    }

    @Test func officialParkingPage() {
        let f = analyze(Pages.parking, url: "https://vph.zpspraha.cz/PA/1234").facts
        #expect(f.title == "Virtuální parkovací hodiny")
        #expect(f.asks == [.licencePlate, .card])
        #expect(f.offer == nil)
        #expect(f.extract.contains("SPZ vozidla: [          ]"))
        #expect(f.extract.contains("Délka stání: [          ]"))
        #expect(f.extract.contains("Číslo karty: [          ]"))
        #expect(f.extract.contains("[ Zaplatit ]"))
        #expect(!f.extract.contains { $0.contains("30 minut") }) // option texts are not page text
        #expect(f.foreignFormHosts.isEmpty)
        #expect(f.brandClaim == nil)
    }

    @Test func easyParkCardPhishing() {
        let f = analyze(Pages.easyparkPhish, url: "https://easypark-platba.cc/praha").facts
        #expect(f.brandClaim == "EasyPark")
        #expect(f.asks == [.card])
        #expect(f.extract.contains("Číslo karty: [          ]"))
        #expect(f.extract.contains("CVC: [          ]"))
        #expect(f.extract.contains("[ Zaplatit 40 Kč ]"))
        #expect(!f.extract.contains { $0.contains("bezpečná platební brána") }) // display:none
        #expect(f.foreignFormHosts == ["pay-gateway.easypark-platba.top"])
        #expect(f.offer == nil)
    }

    @Test func disclosedFreeTrial() {
        let f = analyze(Pages.freeTrial).facts
        let offer = f.offer
        #expect(offer?.text == "Po skončení zkušebního období 149 Kč/měsíc, předplatné lze kdykoli zrušit v nastavení")
        #expect(offer?.promise == nil)
        #expect(offer?.highlight == [2])
        #expect(f.asks == [.email])
    }

    @Test func promises() {
        // A free claim elsewhere on the page is the promise the charge contradicts.
        let deceptive = analyze("<h1>Hudba zdarma navždy!</h1><p>Aktivací souhlasíte: 99 Kč týdně.</p><input type=tel name=phone>").facts.offer
        #expect(deceptive?.text == "Aktivací souhlasíte: 99 Kč týdně")
        #expect(deceptive?.promise == "Hudba zdarma navždy")
        // In the charge's own sentence it is a disclosure ("free, then 99 a week").
        let disclosed = analyze("<p>Hudba zdarma, poté 99 Kč týdně.</p><input type=tel name=phone>").facts.offer
        #expect(disclosed?.text == "Hudba zdarma, poté 99 Kč týdně")
        #expect(disclosed?.promise == nil)
        // Negated claims are not promises.
        #expect(analyze("<p>Služba není zdarma.</p><p>Cena 99 Kč/týden.</p>").facts.offer?.promise == nil)
    }

    @Test func longSentencesAreQuotedAroundThePrice() {
        let words = (1...40).map { "slovo\($0)" }.joined(separator: " ")
        let offer = analyze("<p>\(words) a předplatné stojí 99 Kč/týden a dále \(words).</p>").facts.offer
        #expect(offer != nil)
        #expect((offer?.text.count ?? 0) <= 160)
        #expect(offer?.text.contains("99 Kč/týden") == true)
        #expect(offer?.text.hasPrefix("…") == true)
        #expect(offer?.text.hasSuffix("…") == true)
    }

    @Test func notOffers() {
        // A menu, a delivery threshold, cancellation instructions, a newspaper menu item and a
        // number word that contains "den" are not recurring charges.
        let pages = [
            "<p>Espresso 55 Kč · Cappuccino 69 Kč</p><p>Snídaně do 11:00</p>",
            "<p>Doprava zdarma nad 1 000 Kč</p>",
            "<p>Předplatné zrušíte zasláním STOP na 90211.</p><input type=tel name=tel>",
            "<nav><a href=/predplatne>Předplatné</a> <a href=/sport>Sport</a></nav><p>Zprávy dne</p>",
            "<p>Vybrali jsme jeden dárek za 99 Kč.</p>",
            "<p>Bez předplatného, platíte jen jednou 99 Kč.</p>",
        ]
        for html in pages { #expect(analyze(html).facts.offer == nil, "\(html)") }
        // A bare subscription mention counts on a sign-up page (phone field present).
        #expect(analyze("<p>Kliknutím aktivujete předplatné služby.</p><input type=tel name=msisdn>").facts.offer?.text
            == "Kliknutím aktivujete předplatné služby")
    }

    @Test func offerFarDownThePageIsStillInTheExtract() {
        let filler = (1...60).map { "<p>Odstavec číslo \($0) s nějakým obsahem.</p>" }.joined()
        let f = analyze("<h1>Soutěž</h1>\(filler)<p>Služba stojí 6 Kč/den, platba mobilem.</p>").facts
        #expect(f.extract.count == 40)
        #expect(f.offer?.text == "Služba stojí 6 Kč/den, platba mobilem")
        #expect(f.offer?.highlight == [39])
        #expect(f.extract[39] == "Služba stojí 6 Kč/den, platba mobilem.")
    }

    @Test func fieldLabels() {
        let html = """
        <form>
          <input id="a" name="x1"><label for="a">Jméno</label>
          <p>Telefon: <input name="t" type="tel"></p>
          <input name="kod" aria-label="Kód z SMS">
          <input name="heslo" type="password" placeholder="Heslo">
          <input name="recovery_phrase" placeholder="Zadejte 12 slov">
          <label>Rodné číslo <input name="rc"></label>
          <input name="mail" type="email">
          <input type="checkbox" id="agree"><label for="agree">Souhlasím s podmínkami</label>
          <input type="image" alt="Odeslat formulář" src="go.png">
        </form>
        """
        let f = analyze(html).facts
        #expect(f.extract == [
            "Jméno: [          ]",
            "Telefon: [          ]",
            "Kód z SMS: [          ]",
            "Heslo: [          ]",
            "Zadejte 12 slov: [          ]",
            "Rodné číslo: [          ]",
            "mail: [          ]",
            "Souhlasím s podmínkami",
            "[ Odeslat formulář ]",
        ])
        #expect(f.asks == [.phone, .otp, .password, .recoverySecret, .personalID, .email])
    }

    @Test func instructionsInTextCountAsAsks() {
        let f = analyze("<p>Přihlaste se do internetového bankovnictví</p><p>Identifikační číslo · PIN</p><p>Pro ověření zadejte číslo karty</p>").facts
        #expect(f.asks == [.card])
        #expect(analyze("<p>Stačí zadat číslo.</p>").facts.asks.isEmpty)
    }

    @Test func brandClaims() {
        #expect(analyze("<title>Zásilkovna — vaše zásilka čeká</title>").facts.brandClaim == "Zásilkovna")
        #expect(analyze("<title>Internetbanking — přihlášení</title><h1>ČSOB Identity</h1>").facts.brandClaim == "ČSOB")
        #expect(analyze("<title>Platba</title><img alt='Logo Česká pošta'>").facts.brandClaim == "Česká pošta")
        #expect(analyze("<title>Portfolio</title><p>EasyPark v textu se nepočítá</p>").facts.brandClaim == nil)
        #expect(analyze("<title>Zprávy</title><img alt='Šlágr oslaví svých 15 let v O2 areně'>").facts.brandClaim == nil)
    }

    @Test func installLinksRemoteAccessAndForms() {
        let html = """
        <base href="https://cdn.example-page.cz/app/">
        <p>Pro pomoc nainstalujte AnyDesk nebo <a href="https://get.teamviewer.com/qs">podporu</a>.</p>
        <a href="docs.html">Návod</a><a href="profil.mobileconfig">Stáhnout profil</a><a href="app.apk">APK</a>
        <form action="https://example-page.cz/ok"></form><form action="//collect.evil-bq.top/a"></form><form></form>
        """
        let f = analyze(html, url: "https://example-page.cz/podpora").facts
        #expect(f.installLink == "https://cdn.example-page.cz/app/profil.mobileconfig")
        #expect(f.remoteAccess == ["AnyDesk", "TeamViewer"])
        #expect(f.foreignFormHosts == ["collect.evil-bq.top"])
        #expect(analyze("<a href='itms-services://?action=download-manifest&url=https://x.cz/m.plist'>Instalovat</a>").facts.installLink?
            .hasPrefix("itms-services://") == true)
    }

    @Test func metaRefreshAndScriptRedirects() {
        let page = analyze("<head><meta http-equiv='Refresh' content='0; URL=\"/dalsi?x=1\"'></head><body>Přesměrování…</body>",
                           url: "https://example-page.cz/a/b")
        #expect(page.refresh == PageAnalysis.Refresh(delay: 0, url: URL(string: "https://example-page.cz/dalsi?x=1")))
        #expect(analyze("<meta http-equiv=refresh content='5;url=https://jinam.cz/'>").refresh?.delay == 5)
        #expect(analyze("<meta http-equiv=refresh content='30'>").refresh == PageAnalysis.Refresh(delay: 30, url: nil))
        #expect(analyze("<meta http-equiv=refresh content='soon'>").refresh == nil)
        #expect(analyze("<p>x</p>", refresh: "3;url=https://jinam.cz/").refresh?.url == URL(string: "https://jinam.cz/"))
        // Meta refresh inside noscript is ignored, as in Safari with JavaScript on.
        #expect(analyze("<noscript><meta http-equiv=refresh content='0;url=/nojs'></noscript>").refresh == nil)

        let js = analyze("""
        <html><head><script>
          var t = "https:\\/\\/evil-bq.top\\/x"; if (location.href == "a") {}
          window.location.href = 'https://landing-bq.top/lp?id=7';
          setTimeout(function(){ location.replace("/second"); }, 10);
        </script></head><body></body></html>
        """, url: "https://example-page.cz/")
        #expect(js.scriptRedirects == [URL(string: "https://landing-bq.top/lp?id=7")!, URL(string: "https://example-page.cz/second")!])
        #expect(js.scriptOnly)
        #expect(js.facts.extract.isEmpty)
        // Plenty of content: not script-only even with a redirect candidate.
        #expect(!analyze(Pages.parking + "<script>location='https://x-bq.top/'</script>").scriptOnly)
        // An app that renders with script but doesn't navigate is not script-only; its extract is empty.
        let app = analyze("<title>Parkuj v klidu</title><div data-ui-view></div><script src=/js/app.js></script>")
        #expect(!app.scriptOnly)
        #expect(app.facts.extract.isEmpty)
        #expect(app.facts.title == "Parkuj v klidu")
        // JSON data blocks are not scripts.
        #expect(analyze("<script type='application/ld+json'>{\"x\": \"location.href='https://x-bq.top/'\"}</script>").scriptRedirects.isEmpty)
    }

    @Test func invisibleContentIsSkipped() {
        let html = """
        <html><head><title>T</title><style>p{}</style></head><body>
        <script>document.write('<p>scripted</p>')</script>
        <noscript>Zapněte JavaScript</noscript>
        <template><p>template</p><input name=phone type=tel></template>
        <svg><title>ikona</title><text>svg text</text></svg>
        <div hidden><p>hidden attribute</p></div>
        <div style="visibility: hidden">invisible</div>
        <p>vidi<span>tel</span>ný &amp; <b>tučný</b>&nbsp;text</p>
        <p>před&shy;platné bez&#8203;mezer</p>
        </body></html>
        """
        let f = analyze(html).facts
        #expect(f.extract == ["viditelný & tučný text", "předplatné bezmezer"])
        #expect(f.asks.isEmpty)
        #expect(f.title == "T")
    }

    @Test func tablesAndHeadLessDocuments() {
        let f = analyze("<head><title>Bez body</title><p>Text hned po head</p><table><tr><td>Číslo karty</td><td>Platnost</td><td>CVC</td></tr></table>").facts
        #expect(f.extract == ["Text hned po head", "Číslo karty · Platnost · CVC"])
    }

    @Test func titleFallsBackToHeadingThenOpenGraph() {
        #expect(analyze("<h1>  Nadpis\n stránky </h1>").facts.title == "Nadpis stránky")
        #expect(analyze("<meta property='og:title' content='OG titulek'><p>x</p>").facts.title == "OG titulek")
        #expect(analyze("<p>bez titulku</p>").facts.title == nil)
    }

    @Test func charsets() {
        let czech = "<html><body><p>Předplatné 99 Kč/týden, účtováno operátorem.</p></body></html>"
        let cp1250 = czech.data(using: .windowsCP1250)!
        let latin2 = czech.data(using: .isoLatin2)!
        for data in [cp1250, latin2] {
            let f = analyzer.analyze(data, charset: nil, url: URL(string: "https://example-page.cz/")!).facts
            #expect(f.extract == ["Předplatné 99 Kč/týden, účtováno operátorem."])
            #expect(f.offer != nil)
        }
        // Declared charsets win: header, then meta.
        let header = analyzer.analyze(cp1250, charset: "windows-1250", url: URL(string: "https://example-page.cz/")!).facts
        #expect(header.extract == ["Předplatné 99 Kč/týden, účtováno operátorem."])
        let meta = ("<meta http-equiv='Content-Type' content='text/html; charset=iso-8859-2'>" + "<p>Šťastný žluťoučký kůň</p>").data(using: .isoLatin2)!
        #expect(analyzer.analyze(meta, charset: nil, url: URL(string: "https://example-page.cz/")!).facts.extract == ["Šťastný žluťoučký kůň"])
        let sz = "<p>Šťastný žluťoučký kůň</p>"
        #expect(analyzer.analyze(sz.data(using: .isoLatin2)!, charset: nil, url: URL(string: "https://example-page.cz/")!).facts.extract == ["Šťastný žluťoučký kůň"])
        #expect(analyzer.analyze(sz.data(using: .windowsCP1250)!, charset: nil, url: URL(string: "https://example-page.cz/")!).facts.extract == ["Šťastný žluťoučký kůň"])
        // UTF-8 cut in the middle of a character (a truncated body) is still UTF-8.
        let utf8 = Data("<p>Předplatné č".utf8)
        #expect(analyzer.analyze(utf8.dropLast(1), charset: nil, url: URL(string: "https://example-page.cz/")!).facts.extract.first?.hasPrefix("Předplatné") == true)
    }

    @Test func limitsAreReportedNotSilent() {
        // Input beyond the byte budget.
        var small = PageAnalyzer.Limits()
        small.maxInputBytes = 1000
        let padded = "<p>" + String(repeating: "výplň ", count: 400) + "</p><p>Předplatné 99 Kč/týden</p>"
        let cut = PageAnalyzer(limits: small).analyze(Data(padded.utf8), charset: "utf-8", url: URL(string: "https://example-page.cz/")!)
        #expect(cut.truncated)
        #expect(cut.facts.offer == nil)
        #expect(analyze(padded).facts.offer != nil) // with the default budget the offer is found
        #expect(!analyze(padded).truncated)
        // More lines than the structure keeps.
        let manyLines = (0...10_000).map { "<p>řádek \($0)</p>" }.joined()
        #expect(analyze(manyLines).truncated)
        // The tokenizer's own bound.
        var tokenizer = HTMLTokenizer.Limits()
        tokenizer.maxTokens = 50
        #expect(PageStructureBuilder.build(html: Array(String(repeating: "<b>x</b>", count: 100).utf8), tokenizerLimits: tokenizer).truncated)
        #expect(!PageStructureBuilder.build(html: Array(String(repeating: "<b>x</b>", count: 100).utf8)).truncated)
        // A huge single paragraph is analysed whole.
        let wall = "<p>" + String(repeating: "slovo ", count: 3000) + "Předplatné 99 Kč/týden.</p>"
        #expect(analyze(wall).facts.offer?.text.contains("99 Kč/týden") == true)
    }

    @Test func installAndRemoteAccessLinksSurviveLinkHeavyPages() {
        let filler = (1...800).map { "<a href='/clanek/\($0)'>Článek \($0)</a>" }.joined()
        let f = analyze(filler + "<a href='https://cdn-bq.top/aplikace.apk?v=2'>Stáhnout</a><a href='https://anydesk.com/cs'>Podpora</a>",
                        url: "https://example-page.cz/").facts
        #expect(f.installLink == "https://cdn-bq.top/aplikace.apk?v=2")
        #expect(f.remoteAccess == ["AnyDesk"])
    }

    @Test func longLinesAndTitlesAreBounded() {
        let long = String(repeating: "slovo ", count: 100)
        let f = analyze("<title>\(long)</title><p>\(long)</p>").facts
        #expect((f.title?.count ?? 0) <= 200)
        #expect(f.extract.first!.count <= 200)
        #expect(f.extract.first!.hasSuffix("…"))
    }
}

@Suite("HTML tokenizer")
struct HTMLTokenizerTests {
    private func tokens(_ html: String) -> [HTMLTokenizer.Token] { HTMLTokenizer.tokenize(Array(html.utf8)) }

    @Test func attributes() {
        let t = tokens(#"<INPUT Type=TEL name="a b" data-x='1' name=dup disabled value=&quot;x&amp;y&quot; />"#)
        guard case .startTag(let tag) = t.first else { Issue.record("no tag"); return }
        #expect(tag.name == "input")
        #expect(tag["type"] == "TEL")
        #expect(tag["name"] == "a b")
        #expect(tag["data-x"] == "1")
        #expect(tag["disabled"] == "")
        #expect(tag["value"] == "\"x&y\"")
        #expect(tag.selfClosing)
        // In an unquoted value a slash is part of the value, not a self-closing marker.
        guard case .startTag(let unquoted) = tokens("<a href=/x/>").first else { Issue.record("no tag"); return }
        #expect(unquoted["href"] == "/x/")
        #expect(!unquoted.selfClosing)
    }

    @Test func entities() {
        #expect(tokens("&lt;p&gt; &ccaron;&Rcaron;&#x159;&#382; &euro;&#150; &bogus; &amp").first == .text("<p> čŘřž €– &bogus; &"))
        #expect(tokens("&#0;&#xD800;&#x110000;").first == .text("\u{FFFD}\u{FFFD}\u{FFFD}"))
        guard case .startTag(let tag) = tokens("<a href='?a=1&copy=2&amp;b'>").first else { Issue.record("no tag"); return }
        #expect(tag["href"] == "?a=1&copy=2&b") // legacy reference not decoded before '='
    }

    @Test func rawTextAndComments() {
        let t = tokens("<script>if (a</b) { x = '</div>' }</SCRIPT ><!-- <p>no</p> --><!--><p>yes</p><title>A &amp; B</title><?php x ?>")
        #expect(t == [
            .startTag(HTMLTag(name: "script", attributes: [:], selfClosing: false)),
            .rawText(tag: "script", text: "if (a</b) { x = '</div>' }"),
            .startTag(HTMLTag(name: "p", attributes: [:], selfClosing: false)),
            .text("yes"),
            .endTag("p"),
            .startTag(HTMLTag(name: "title", attributes: [:], selfClosing: false)),
            .rawText(tag: "title", text: "A & B"),
        ])
    }

    @Test func malformedInput() {
        #expect(tokens("a < b and c<1") == [.text("a < b and c<1")])
        #expect(tokens("text<div class='unterminated") == [.text("text")])
        #expect(tokens("</>x</ div>") == [.text("x")])
        let deep = String(repeating: "<div>", count: 5000) + "hloubka" + String(repeating: "</div>", count: 5000)
        #expect(PageStructureBuilder.build(HTMLTokenizer.tokenize(Array(deep.utf8))).lines.map(\.text) == ["hloubka"])
    }

    @Test func tokenCountIsBounded() {
        let many = String(repeating: "<b>x</b>", count: 100_000)
        #expect(HTMLTokenizer.tokenize(Array(many.utf8)).count <= HTMLTokenizer.Limits().maxTokens)
    }
}
