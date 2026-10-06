import BQCore
import SwiftUI
import Testing
@testable import BQUI

@MainActor
struct SignalTests {
    @Test("Every existing action and confirmation survives grouping", arguments: Corpus.ids)
    func preservesActions(_ id: String) {
        let a = Corpus.analysis(id), texts = FindingTexts(Corpus.analysis(id), .cs)
        for host in [ResultCapabilities.app, .imageExtension] {
            let plan = ActionPlan(a, verdict: Verdict(a, texts, .cs), texts: texts, lang: .cs, contactSaved: false, capabilities: host)
            let groups = ResultActionGroups(plan)
            let regrouped = groups.primary + groups.secondary
            #expect(regrouped.count == plan.items.filter { !$0.isDismissal }.count)
            for item in plan.items where !item.isDismissal { #expect(regrouped.contains { $0 == item }) }
            for case .hold(let hold) in plan.items {
                #expect(regrouped.contains(.hold(hold)))
                #expect(!hold.alternativeTitle.isEmpty && !hold.confirmTitle.isEmpty)
            }
            #expect(!regrouped.contains { $0.isDismissal })
        }
    }

    @Test("Header scores are unchanged and unscored types stay unscored", arguments: Corpus.ids)
    func summaryDoesNotChangeAnalysis(_ id: String) {
        let a = Corpus.analysis(id), texts = FindingTexts(Corpus.analysis(id), .cs)
        let summary = ResultSummary(a, texts: texts, language: .cs)
        #expect(summary.verdict == Verdict(a, texts, .cs))
        #expect(summary.score == (a.assessment.scored && !a.decodeOnly ? a.assessment.score : nil))
        if let critical = texts.consequences.first(where: { $0.texts.severity == .critical }) {
            #expect(summary.leadingReason == (summary.verdict.isAlert ? critical.texts.text : critical.texts.title))
            for consequence in texts.consequences where consequence.texts.severity != .info {
                #expect(summary.visibleConsequences.contains { $0.id == consequence.id } ||
                        (summary.verdict.title == consequence.texts.title && summary.leadingReason == consequence.texts.text))
            }
        }
    }

    @Test("Incomplete, critical and unscored results cannot get a reassuring green panel")
    func colourExceptions() {
        func summary(_ id: String) -> ResultSummary {
            let a = Corpus.analysis(id)
            return ResultSummary(a, texts: FindingTexts(a, .cs), language: .cs)
        }
        let incomplete = summary("url-offline-menu")
        #expect(incomplete.provisional)
        #expect(incomplete.surface.start == SignalPalette.color(for: .incomplete))
        #expect(summary("sms-premium-ano").surface.start == SignalPalette.color(for: .alert))
        #expect(summary("tel-mmi-forward").surface.start == SignalPalette.color(for: .alert))
        #expect(summary("wifi-wpa2").score == nil)
        #expect(summary("wifi-wpa2").surface.start == SignalPalette.color(for: .info))
        let a = Corpus.analysis("url-menu-shortener")
        let pending = ResultSummary(a, texts: FindingTexts(a, .cs), language: .cs, checking: true)
        #expect(pending.provisional && pending.surface.start == SignalPalette.color(for: .incomplete))
    }

    @Test("Small header text has 4.5:1 contrast across every score and gradient endpoint", arguments: 0...100)
    func scoreContrast(_ score: Int) {
        let surface = SignalPalette.Surface(SignalPalette.color(at: score))
        #expect(surface.start.contrast(with: surface.ink) >= 4.5)
        #expect(surface.end.contrast(with: surface.ink) >= 4.5)
    }

    @Test("All tone surfaces have readable small text", arguments: Tone.allCases)
    func toneContrast(_ tone: Tone) {
        let surface = SignalPalette.Surface(SignalPalette.color(for: tone))
        #expect(surface.start.contrast(with: surface.ink) >= 4.5)
        #expect(surface.end.contrast(with: surface.ink) >= 4.5)
    }

    @Test func incompleteReasonsExplainObservedFailureWithoutChangingRisk() {
        var analysis = Corpus.analysis("url-offline-menu")
        analysis.inspection = Inspection(chain: [Hop(url: analysis.code.text, status: 403)], completeness: Completeness(.incomplete, reason: "inc.http_error"))
        analysis.completeness = Completeness(.incomplete, reason: "inc.http_error")
        let before = analysis.assessment
        #expect(InspectionExplanation.text(analysis, .en).contains("did not allow"))
        analysis.inspection?.transportError = "tlsFailed"
        #expect(InspectionExplanation.text(analysis, .cs).contains("Bezpečné připojení"))
        #expect(analysis.assessment == before)
    }

    @Test func releaseIgnoresExperimentalPreferences() {
        let release = ReviewAppearance(preset: "fade", presentation: "popup", scoreChart: "arc", fadeTreatment: "softWash", statusBar: "immersive", enabled: false)
        #expect(release.preset == .fade && release.presentation == .sheet && release.scoreChart == .spectrum)
        #expect(release.fadeTreatment == .vivid && release.statusBar == .immersive)
        let defaults = ReviewAppearance(preset: nil, presentation: nil, enabled: true)
        #expect(defaults.preset == .fade && defaults.presentation == .sheet && defaults.scoreChart == .spectrum)
        #expect(defaults.fadeTreatment == .vivid && defaults.statusBar == .immersive)
        let saved = ReviewAppearance(preset: "type", presentation: "fullPage", scoreChart: "dots", enabled: true)
        #expect(saved.preset == .fade && saved.presentation == .sheet && saved.scoreChart == .dots)
        #expect(ReviewAppearance(preset: nil, presentation: nil, scoreChart: "unknown", enabled: true).scoreChart == .spectrum)
        let independent = ReviewAppearance(preset: "type", presentation: "popup", scoreChart: "arc", fadeTreatment: "softWash", statusBar: "immersive", enabled: true)
        #expect(independent.preset == .fade && independent.presentation == .sheet && independent.scoreChart == .arc)
        #expect(independent.fadeTreatment == .vivid && independent.statusBar == .immersive)
        let invalid = ReviewAppearance(preset: nil, presentation: nil, fadeTreatment: "old", statusBar: "old", enabled: true)
        #expect(invalid.fadeTreatment == .vivid && invalid.statusBar == .immersive)
    }

    @Test("All adjacent scores remain continuous, including verdict thresholds")
    func continuousPalette() {
        for (score, hex) in [(0, 0x34C759), (25, 0xFFD60A), (45, 0xFF9F0A), (60, 0xFF453A), (100, 0xD70015)] as [(Int, UInt32)] {
            #expect(SignalPalette.color(at: score) == SignalPalette.RGB(hex))
        }
        for score in 1...100 {
            let a = SignalPalette.color(at: score - 1), b = SignalPalette.color(at: score)
            #expect(max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) < 0.05)
        }
        for anchor in [0.25, 0.45, 0.60] {
            let a = SignalPalette.sample(at: anchor - 0.0001), b = SignalPalette.sample(at: anchor + 0.0001)
            #expect(max(abs(a.r - b.r), abs(a.g - b.g), abs(a.b - b.b)) < 0.00001)
        }
        #expect(SignalPalette.color(at: -10) == SignalPalette.color(at: 0))
        #expect(SignalPalette.color(at: 110) == SignalPalette.color(at: 100))
    }

    @Test("Text remains readable through the entire page fade for every score and tone")
    func fadeContrast() {
        let colours = (0...100).map(SignalPalette.color(at:)) + Tone.allCases.map(SignalPalette.color(for:))
        for base in colours {
            for treatment in FadeTreatment.allCases {
                for dark in [false, true] {
                    for increased in [false, true] {
                        let surface = FadeSurface(base: base, treatment: treatment, dark: dark, increasedContrast: increased)
                        for step in 0...100 {
                            #expect(surface.sample(Double(step) / 100).contrast(with: surface.ink) >= (increased ? 7 : 4.5))
                        }
                        #expect(surface.sample(1) == surface.page)
                    }
                }
            }
        }
    }

    @Test("Scanner scrim protects text on white and black footage and ends continuously")
    func scannerFadeContrast() {
        for h in [180.0, 260, 520] {
            for treatment in FadeTreatment.allCases {
                let lime = SignalPalette.RGB(0xD8FA3D)
                let base = treatment == .vivid ? lime : lime.mixed(with: .init(0), fraction: 0.88)
                let ink = SignalPalette.RGB(treatment == .vivid ? 0x141A0A : 0xFFFFFF)
                for footage in [SignalPalette.RGB(0), SignalPalette.RGB(0xFFFFFF)] {
                    for step in 0...100 {
                        let alpha = ScannerFadeCurve.strength(at: h * Double(step) / 100, textBottom: h)
                        #expect(footage.mixed(with: base, fraction: alpha).contrast(with: ink) >= 4.5)
                    }
                }
            }
            var previous = 1.0
            for y in stride(from: 0.0, through: h + 144, by: 1) {
                let next = ScannerFadeCurve.strength(at: y, textBottom: h)
                #expect(next <= previous && next >= 0)
                #expect(previous - next < 0.01)
                previous = next
            }
            #expect(ScannerFadeCurve.strength(at: h + 144, textBottom: h) == 0)
        }
    }

    @Test func expandedActionsResetOnlyWhenTheCodeChanges() {
        let m = ResultModel(analysis: Corpus.analysis("wifi-wpa2"), fromCamera: true)
        m.moreActionsExpanded = true
        m.analysis = Corpus.analysis("wifi-wpa2")
        #expect(m.moreActionsExpanded)
        m.analysis = Corpus.analysis("wifi-open")
        #expect(!m.moreActionsExpanded)
    }
}
