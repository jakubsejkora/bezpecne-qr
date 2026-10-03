import BQCore
import Foundation

/// shared/testdata/samples.json replayed through the analyzer — the same recipe as BQCore's
/// CorpusTests (mock inspection, printed context from `ocr`, `now` = 2026-09-29).
enum Corpus {
    /// The repository root (…/ios/Packages/BQUI/Tests/BQUITests/Corpus.swift → 6 levels up).
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    struct Sample: Decodable {
        struct Expected: Decodable { var band: Band }
        struct OCR: Decodable { var printed: String?; var near: String? }
        var id: String
        var payload: String
        var type: String
        var engine: String
        var symbology: String?
        var network: String?
        var completeness: Completeness?
        var inspection: Inspection?
        var ocr: OCR?
        var expected: Expected
    }

    struct Scenario: Decodable {
        var id: String
        var children: [String]
    }

    private struct File: Decodable {
        var samples: [Sample]
        var scenarios: [Scenario]
    }

    private static let file: File = {
        let url = root.appendingPathComponent("shared/testdata/samples.json")
        do {
            return try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        } catch {
            fatalError("Cannot read \(url.path): \(error)")
        }
    }()

    static var samples: [Sample] { file.samples }
    static var ids: [String] { file.samples.map(\.id) }
    static var scenarios: [Scenario] { file.scenarios }

    /// The corpus was written on 2026-09-29 (domain ages are relative to that day).
    static let corpusDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 29; c.hour = 12
        c.timeZone = TimeZone(identifier: "Europe/Prague")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

    static func sample(_ id: String) -> Sample {
        guard let s = samples.first(where: { $0.id == id }) else { fatalError("No corpus sample \(id)") }
        return s
    }

    /// The final analysis of a sample (with its mocked inspection).
    static func analysis(_ id: String) -> Analysis {
        analyze(sample(id))
    }

    /// The instant offline analysis right after the scan, before any inspection ran.
    static func pendingAnalysis(_ id: String) -> Analysis {
        let s = sample(id)
        let code = ScannedCode(text: s.payload, symbology: Symbology(rawValue: s.symbology ?? "qr") ?? .qr, source: .camera)
        return Analyzer().analyze(code, now: corpusDate)
    }

    static func analyze(_ s: Sample) -> Analysis {
        let analyzer = Analyzer()
        var inspection = s.inspection
        if inspection != nil, inspection?.completeness == nil { inspection?.completeness = s.completeness }
        let linkLike = ["url", "store", "messenger", "webcal", "intent"].contains(s.type)
        if inspection == nil, linkLike, s.network != "offline", let c = s.completeness, c.state != .skipped {
            inspection = Inspection(completeness: c)
        }
        let options = AnalysisOptions(offline: s.network == "offline")
        let printed = s.ocr.map { PrintedContext(printed: $0.printed, near: $0.near) }
        let code = ScannedCode(text: s.payload, symbology: Symbology(rawValue: s.symbology ?? "qr") ?? .qr, source: .camera)
        return analyzer.analyze(code, inspection: inspection, printed: printed, options: options, now: corpusDate)
    }
}
