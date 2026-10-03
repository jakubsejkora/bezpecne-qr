import Foundation
import Testing
@testable import BQCore

/// Replays every sample of shared/testdata/samples.json through the analyzer.
struct CorpusTests {
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
        var signals: [Finding]?
        var consequences: [Finding]?
        var completeness: Completeness?
        var inspection: Inspection?
        var ocr: OCR?
        var expected: Expected
    }

    struct Corpus: Decodable { var samples: [Sample] }

    static let corpus: [Sample] = {
        let url = root.appendingPathComponent("shared/testdata/samples.json")
        let data = try! Data(contentsOf: url)
        return try! JSONDecoder().decode(Corpus.self, from: data).samples
    }()

    nonisolated(unsafe) static let rawSamples: [String: [String: Any]] = {
        let url = root.appendingPathComponent("shared/testdata/samples.json")
        let json = try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        var out: [String: [String: Any]] = [:]
        for s in json["samples"] as! [[String: Any]] { out[s["id"] as! String] = s }
        return out
    }()

    /// The corpus was written on 2026-09-29 (domain ages are relative to that day).
    static let corpusDate: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 29; c.hour = 12
        c.timeZone = TimeZone(identifier: "Europe/Prague")
        return Calendar(identifier: .gregorian).date(from: c)!
    }()

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
        let code = ScannedCode(text: s.payload, symbology: Symbology(rawValue: s.symbology ?? "qr") ?? .qr, source: .debug)
        return analyzer.analyze(code, inspection: inspection, printed: printed, options: options, now: corpusDate)
    }

    @Test("Every corpus sample has the expected type", arguments: corpus.map(\.id))
    func type(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        #expect(Self.analyze(s).type.rawValue == s.type)
    }

    @Test("Parsed fields match the corpus", arguments: corpus.map(\.id))
    func fields(_ id: String) throws {
        let s = Self.corpus.first { $0.id == id }!
        guard let expected = Self.rawSamples[id]?["fields"] as? [String: Any] else { return }
        let actual = Self.analyze(s).content.fieldsJSON
        for (key, value) in expected where key != "note" {
            let got = actual[key]
            #expect(Self.jsonEqual(value, got), "\(id).\(key): expected \(value), got \(String(describing: got))")
        }
    }

    @Test("Evidence signals match the corpus", arguments: corpus.map(\.id))
    func signals(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        let got = Set(Self.analyze(s).evidence.map(\.id))
        let want = Set((s.signals ?? []).map(\.id))
        #expect(got == want, "\(id): missing \(want.subtracting(got).sorted()), unexpected \(got.subtracting(want).sorted())")
    }

    @Test("Consequences match the corpus", arguments: corpus.map(\.id))
    func consequences(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        let got = Set(Self.analyze(s).consequences.map(\.id))
        let want = Set((s.consequences ?? []).map(\.id))
        #expect(got == want, "\(id): missing \(want.subtracting(got).sorted()), unexpected \(got.subtracting(want).sorted())")
    }

    @Test("Band matches the corpus", arguments: corpus.map(\.id))
    func band(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        let a = Self.analyze(s)
        #expect(a.band == s.expected.band, "\(id): got \(a.band) (score \(a.assessment.score ?? -1), completeness \(a.completeness.state))")
    }

    @Test("Completeness state matches the corpus", arguments: corpus.map(\.id))
    func completeness(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        guard let want = s.completeness else { return }
        let got = Self.analyze(s).completeness
        #expect(got.state == want.state, "\(id): got \(got.state) (\(got.reason ?? "-")), want \(want.state) (\(want.reason ?? "-"))")
        if want.state == .skipped { #expect(got.reason == want.reason && got.manual == want.manual, "\(id)") }
    }

    @Test("Scorer reproduces the reference engine for the corpus' own signals", arguments: corpus.map(\.id))
    func scorer(_ id: String) {
        let s = Self.corpus.first { $0.id == id }!
        let engine = EngineKind(rawValue: s.engine) ?? .none
        let a = Scorer(weights: RuleSet.bundled.weights).assess(engine: engine, evidence: s.signals ?? [],
                                                                completeness: s.completeness ?? .complete)
        #expect(a.band == s.expected.band, "\(id): reference scoring gives \(a.band) (\(a.score ?? -1))")
    }

    @Test("Bundled rules are in sync with shared/")
    func resourcesInSync() throws {
        let fm = FileManager.default
        for folder in ["rules", "content"] {
            let shared = Self.root.appendingPathComponent("shared/\(folder)")
            for name in try fm.contentsOfDirectory(atPath: shared.path) where name.hasSuffix(".json") {
                let bundled = Bundle.module.url(forResource: (name as NSString).deletingPathExtension, withExtension: "json", subdirectory: folder)
                let a = try Data(contentsOf: shared.appendingPathComponent(name))
                let b = try bundled.map { try Data(contentsOf: $0) }
                #expect(a == b, "\(folder)/\(name) differs — run scripts/sync-core-resources.sh")
            }
        }
    }

    static func jsonEqual(_ a: Any, _ b: Any?) -> Bool {
        if a is NSNull { return b == nil || b is NSNull }
        guard let b else { return false }
        switch (a, b) {
        case let (x as String, y as String): return x == y
        case let (x as NSNumber, y as NSNumber): return x.doubleValue == y.doubleValue
        case let (x as [Any], y as [Any]): return x.count == y.count && zip(x, y).allSatisfy { jsonEqual($0, $1) }
        case let (x as [String: Any], y as [String: Any]):
            return x.allSatisfy { k, v in jsonEqual(v, y[k]) }
        default: return false
        }
    }
}
