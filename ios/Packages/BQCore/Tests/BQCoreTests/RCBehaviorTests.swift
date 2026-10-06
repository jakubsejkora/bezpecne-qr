import Foundation
import Testing
@testable import BQCore

struct RCBehaviorTests {
    private func link(_ band: Band, score: Int, path: String = "menu") -> Analysis {
        let url = "https://example.org/" + path
        let endpoint = Endpoint(url: url, host: "example.org", registrable: "example.org")
        var a = Analyzer().analyze(ScannedCode(text: url), inspection: Inspection(final: endpoint, completeness: .complete,
            destination: DestinationResolution(state: .resolved, scannedURL: url, resolved: endpoint)))
        a.assessment = Assessment(scored: true, score: score, band: band)
        return a
    }
    @Test func recommendationRequiresUniqueCompleteLowRiskWebCode() {
        let low = link(.safe, score: 7), caution = link(.caution, score: 45)
        #expect(CodeComparison.recommendation([low, caution]) == 0)
        #expect(CodeComparison.recommendation([caution, low]) == 1)
        #expect(CodeComparison.recommendation([low, low, caution]) == nil)
        #expect(CodeComparison.recommendation([low, caution], checking: [1]) == nil)
        var incomplete = caution; incomplete.completeness = Completeness(.incomplete, reason: "inc.timeout")
        #expect(CodeComparison.recommendation([low, incomplete]) == nil)
        var unresolved = low; unresolved.inspection?.destination?.state = .unresolved
        #expect(CodeComparison.recommendation([unresolved, caution]) == nil)
        #expect(CodeComparison.recommendation([low, Analyzer().analyze(ScannedCode(text: "Plain text"))]) == nil)
        var consequence = low; consequence.consequences = [Finding("csq.sms_premium")]
        // A real known critical consequence from the analyzer suppresses selection too.
        let premium = Analyzer().analyze(ScannedCode(text: "SMSTO:9030999:ANO"))
        consequence.consequences = premium.consequences
        #expect(!premium.consequences.isEmpty)
        #expect(CodeComparison.recommendation([consequence, caution]) == nil)
    }
    @Test func bareAndEmbeddedDomainsAreNotClaimedToBePlainText() {
        for text in ["Pay at parking.example.org today", "See www.example.org/menu", "Open https://example.org/?a=1"] {
            let a = Analyzer().analyze(ScannedCode(text: text))
            guard case .text(let info) = a.content else { Issue.record("Expected text"); continue }
            #expect(info.entities.contains { $0.kind == "url" })
            #expect(!a.checks.contains { $0.id == "chk.no_links" })
            #expect(a.linkTarget == nil)
        }
        let text = Analyzer().analyze(ScannedCode(text: "Welcome to our café"))
        #expect(!text.assessment.scored && text.assessment.score == nil)
        #expect(text.checks.contains { $0.id == "chk.no_links" })
    }
    @Test func diagnosticsContainOnlyInertBoundedFacts() throws {
        var a = link(.safe, score: 5)
        a.inspection?.chain = [Hop(url: "https://example.org/menu?search=personal", status: 200),
                               Hop(url: "https://example.org/login?token=verysecretaccessvalue123456789", stopped: .gate)]
        a.inspection?.transportError = "connectionFailed"
        let d = CheckDiagnostics(a, options: AnalysisOptions(), timings: ["inspection": 20])
        #expect(d.isValid)
        let json = String(decoding: try JSONEncoder().encode(d), as: UTF8.self)
        #expect(!json.contains("personal") && !json.contains("verysecret") && !json.contains("/menu"))
        #expect(d.hops[0].host == "example.org" && d.hops[1].host == nil)
        var bad = d; bad.findingIDs = ["https://secret.example/a?token=123"]
        #expect(!bad.isValid)
    }
    @Test func exportProtectionIncludesTokensInTextAndSensitiveCodes() {
        for raw in ["otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP", "https://example.org/?token=verysecretaccessvalue123456789",
                    "Sign in at https://example.org/?token=verysecretaccessvalue123456789",
                    "BEGIN:VCARD\nVERSION:3.0\nFN:Test Person\nURL:https://example.org/?token=verysecretaccessvalue123456789\nEND:VCARD"] {
            #expect(HistoryPrivacy.isProtected(Analyzer().analyze(ScannedCode(text: raw))))
        }
        #expect(!HistoryPrivacy.isProtected(Analyzer().analyze(ScannedCode(text: "Ordinary saved text"))))
    }
}
