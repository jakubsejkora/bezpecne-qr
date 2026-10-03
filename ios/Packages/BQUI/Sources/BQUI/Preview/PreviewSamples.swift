#if DEBUG
import BQCore
import SwiftUI

/// A few corpus samples (shared/testdata/samples.json) rebuilt in code for Xcode previews.
/// The snapshot tests render the whole corpus; these only keep the canvas useful.
enum PreviewSamples {
    /// The corpus date (domain ages in the samples are relative to it).
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 29; c.hour = 12
        c.timeZone = TimeZone(identifier: "Europe/Prague")
        return Calendar(identifier: .gregorian).date(from: c) ?? Date()
    }()

    static func analyze(_ payload: String, inspection: Inspection? = nil, printed: PrintedContext? = nil) -> Analysis {
        Analyzer().analyze(ScannedCode(text: payload), inspection: inspection, printed: printed, now: now)
    }

    /// url-parking-fake: a fake EasyPark sticker asking for a card (Nebezpečné).
    static var fakeParking: Analysis {
        let url = "https://easypark-platba.cc/praha"
        let inspection = Inspection(
            chain: [Hop(url: url, status: 200)],
            final: Endpoint(url: url, host: "easypark-platba.cc", registrable: "easypark-platba.cc"),
            page: PageFacts(title: "EasyPark — Zaplaťte parkovné",
                            extract: ["Zaplaťte parkovné v zóně P1", "Číslo karty · Platnost · CVC", "Zaplatit 40 Kč"],
                            asks: [.card], brandClaim: "EasyPark"),
            domain: DomainFacts(registered: "2026-09-24", registry: "Verisign (.cc)", quad9: .ok),
            completeness: .complete)
        return analyze(url, inspection: inspection, printed: PrintedContext(printed: "parking.praha.eu", near: "Zaplaťte parkovné online"))
    }

    /// url-dcb-subscription: "Vyhrajte iPhone" with a hidden carrier-billed subscription.
    static var subscription: Analysis {
        let start = "https://vyhra-iphone17-cz.top/start", landing = "https://vyhra-iphone17-cz.top/lp?c=cz"
        let offer = Offer(text: "Předplatné 99 Kč/týden, účtováno operátorem", promise: "iPhone 17 zdarma", highlight: [4])
        let inspection = Inspection(
            chain: [Hop(url: start, status: 302), Hop(url: landing, status: 200)],
            final: Endpoint(url: landing, host: "vyhra-iphone17-cz.top", registrable: "vyhra-iphone17-cz.top"),
            page: PageFacts(title: "Gratulujeme! Vyhrajte iPhone 17",
                            extract: ["Gratulujeme! Jste dnešní vybraný návštěvník.",
                                      "Vyhrajte iPhone 17 zdarma — stačí zadat číslo.",
                                      "Telefonní číslo: [          ]", "[ Pokračovat ]",
                                      "Předplatné 99 Kč/týden, účtováno operátorem. Zrušíte SMS STOP na 90211."],
                            asks: [.phone], offer: offer),
            domain: DomainFacts(registered: "2026-09-27", registry: "ZDNS (.top)", quad9: .ok),
            completeness: .complete)
        return analyze(start, inspection: inspection)
    }

    static var payment: Analysis {
        analyze("SPD*1.0*ACC:CZ6508000000192000145399*AM:480.50*CC:CZK*MSG:PLATBA ZA ZBOZI*X-VS:1234567890")
    }

    static var contact: Analysis {
        analyze("BEGIN:VCARD\nVERSION:3.0\nN:Nováková;Jana;;;\nFN:Jana Nováková\nORG:Kavárna U Lípy\nTITLE:Majitelka\n"
                + "TEL;TYPE=CELL:+420777123456\nEMAIL:jana@kavarnaulipy.cz\nURL:https://www.kavarnaulipy.cz\n"
                + "ADR;TYPE=WORK:;;Lipová 12;Praha 2;;120 00;Česko\nEND:VCARD")
    }

    static var wifi: Analysis { analyze("WIFI:T:WPA;S:Kavarna_U_Lipy;P:kafe-2026;;") }
    static var callForwarding: Analysis { analyze("tel:**21*+420606000000%23") }
    static var premiumSMS: Analysis { analyze("SMSTO:9021199:ANO HUDBA") }
    static var pendingLink: Analysis { analyze("https://qrco.de/bfK7aQ") }
}

#Preview("Nebezpečné — falešné parkování") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.fakeParking, fromCamera: true, language: .cs))
}

#Preview("Skryté předplatné") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.subscription, fromCamera: true, language: .cs))
}

#Preview("QR Platba") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.payment, fromCamera: true, language: .cs))
}

#Preview("Vizitka (tmavý)") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.contact, fromCamera: false, language: .cs))
        .preferredColorScheme(.dark)
}

#Preview("Wi‑Fi") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.wifi, fromCamera: false, language: .cs))
}

#Preview("Přesměrování hovorů (EN)") {
    ResultScreen(model: ResultModel(analysis: PreviewSamples.callForwarding, fromCamera: true, language: .en))
}

#Preview("Kontroluji…") {
    let model = ResultModel(analysis: PreviewSamples.pendingLink, fromCamera: true, language: .cs)
    model.step = .address
    model.step = .domain
    model.step = .redirects(1)
    return ResultScreen(model: model)
}

#Preview("Dva kódy") {
    ChooserView(candidates: [PreviewSamples.analyze("https://parking.praha.eu/PA/1234"), PreviewSamples.fakeParking],
                language: .cs, onPick: { _ in }, onClose: {})
}
#endif
