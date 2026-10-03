import BQCore
import Foundation
import Testing
@testable import BQServices

/// Scan → inspect → analyse on real sites. Run with `BQ_LIVE_TESTS=1 swift test --filter EndToEnd`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["BQ_LIVE_TESTS"] == "1"))
struct EndToEndLiveTests {
    static let urls = [
        "https://parking.praha.eu/",
        "https://www.rohlik.cz/",
        "https://www.alza.cz/",
        "https://www.zasilkovna.cz/",
        "https://www.seznam.cz/",
        "http://example.com/",
        "https://portal.gov.cz/",
        "https://apps.apple.com/cz/app/id1234567890",
        "https://wa.me/420777123456",
        "https://www.ceskaposta.cz/",
        "https://www.csob.cz/",
        "https://www.easypark.com/cs-cz",
        "https://edalnice.gov.cz/",
        "https://www.idnes.cz/",
        "https://www.kb.cz/",
        "https://www.o2.cz/",
        "https://bit.ly/3QYn2Bd",
    ]

    @Test(arguments: urls)
    func verdict(_ url: String) async {
        let analyzer = Analyzer()
        let inspector = LinkInspector()
        let code = ScannedCode(text: url, source: .debug)
        let first = analyzer.analyze(code)
        guard let target = first.linkTarget else {
            Issue.record("\(url): no link target")
            return
        }
        let started = ContinuousClock.now
        let inspection = await inspector.inspect(target)
        let elapsed = ContinuousClock.now - started
        let a = analyzer.analyze(code, inspection: inspection)
        let chain = inspection.chain.map { "\($0.status.map(String.init) ?? "-") \($0.url)" }.joined(separator: " → ")
        print("""
        ▸ \(url)  [\(elapsed)]
          band \(a.band.rawValue) score \(a.assessment.score.map(String.init) ?? "-") completeness \(a.completeness.state.rawValue) \(a.completeness.reason ?? "")
          evidence \(a.evidence.map(\.id)) consequences \(a.consequences.map(\.id))
          checks \(a.checks.map(\.id))
          chain \(chain)
          page \(inspection.page?.title ?? "-") asks \(inspection.page?.asks.map(\.rawValue) ?? []) lines \(inspection.page?.extract.count ?? 0)
          domain \(inspection.domain?.registered ?? "-") \(inspection.domain?.registry ?? "-") quad9 \(inspection.domain?.quad9?.rawValue ?? "-")
          offer \(inspection.page?.offer.map { "\($0.text) | promise: \($0.promise ?? "-")" } ?? "-")
        """)
        #expect(a.band != .danger, "\(url) should not be dangerous")
    }
}
