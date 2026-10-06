#if DEBUG || DESIGN_REVIEW
import BQCore
import BQServices
import BQUI
import SwiftUI

/// Debug launch arguments for scripted Simulator checks:
/// `-BQDebugSample <corpus id>` replays a sample, `-BQDebugURL <url>` scans a payload live.
@MainActor
enum DebugLaunch {
    private static var done = false

    /// Internal recording fixture: exercise the real preference and guide rendering, then restore it.
    static func recordAimComparison(_ flow: ScanFlow) async {
        guard flow.isAimPreview, flow.scannerVisible, flow.appActive,
              UserDefaults.standard.bool(forKey: "BQCycleAims") else { return }
        let store = SharedSettings.defaults
        let previous = store.object(forKey: SharedSettings.aim)
        defer {
            if let previous { store.set(previous, forKey: SharedSettings.aim) }
            else { store.removeObject(forKey: SharedSettings.aim) }
        }
        do {
            try await Task.sleep(for: .seconds(1))
            for guide in AimGuideStyle.allCases {
                try Task.checkCancellation()
                store.set(guide.rawValue, forKey: SharedSettings.aim)
                try await Task.sleep(for: .milliseconds(1600))
            }
        } catch { /* Leaving the scanner ends the recording fixture. */ }
    }

    /// `-BQDebugOpen settings` opens Settings at launch (for screenshots).
    static var openTab: AppTab? {
        switch UserDefaults.standard.string(forKey: "BQDebugOpen") {
        case "settings", "lab", "sharing", "scores": .settings
        case "history": .settings
        case "help": .help
        default: nil
        }
    }

    static func run(_ flow: ScanFlow) {
        guard !done else { return }
        done = true
        let args = UserDefaults.standard
        if let direction = args.string(forKey: "BQDesign") { SharedSettings.defaults.set(direction, forKey: SharedSettings.design) }
        if let preset = args.string(forKey: "BQSignalPreset"), SignalPreset(rawValue: preset) != nil {
            SharedSettings.defaults.set(preset, forKey: SharedSettings.signalPreset)
        }
        if let presentation = args.string(forKey: "BQResultPresentation"), ResultPresentationStyle(rawValue: presentation) != nil {
            SharedSettings.defaults.set(presentation, forKey: SharedSettings.resultPresentation)
        }
        if let chart = args.string(forKey: "BQScoreChart"), ScoreChartStyle(rawValue: chart) != nil {
            SharedSettings.defaults.set(chart, forKey: SharedSettings.scoreChart)
        }
        if let fade = args.string(forKey: "BQFadeTreatment"), FadeTreatment(rawValue: fade) != nil {
            SharedSettings.defaults.set(fade, forKey: SharedSettings.fadeTreatment)
        }
        if let bar = args.string(forKey: "BQStatusBar"), ReviewStatusBar(rawValue: bar) != nil {
            SharedSettings.defaults.set(bar, forKey: SharedSettings.statusBar)
        }
        if let aim = args.string(forKey: "BQAimStyle"), AimGuideStyle(rawValue: aim) != nil {
            SharedSettings.defaults.set(aim, forKey: SharedSettings.aim)
        }
        if args.bool(forKey: "BQComparisonPreview") {
            let ids = ["url-menu-shortener", "url-parking-fake", "url-free-hosting"]
            let analyses = ids.compactMap { id -> Analysis? in
                guard let s = DebugSamplesScreen.samples.first(where: { $0.id == id }) else { return nil }
                return Analyzer().analyze(ScannedCode(text: s.payload, source: .debug), inspection: s.inspection)
            }
            flow.injectComparisonReplay(analyses, image: CaptureExamples.make(.crowded)); return
        }
        if args.bool(forKey: "BQAimPreview") { flow.previewAim(); return }
        if let style = args.string(forKey: "BQCaptureStyle") {
            BQServices.SharedSettings.defaults.set(style, forKey: BQServices.SharedSettings.capture)
            if let direction = args.string(forKey: "BQDesign") { BQServices.SharedSettings.defaults.set(direction, forKey: BQServices.SharedSettings.design) }
            CaptureExamples.replay(flow, scene: CaptureExamples.Scene(rawValue: args.string(forKey: "BQCaptureScene") ?? "single") ?? .single)
            return
        }
        if let id = args.string(forKey: "BQDebugSample"), let sample = DebugSamplesScreen.samples.first(where: { $0.id == id }) {
            DebugSamplesScreen.replay(sample, in: flow, live: false)
        } else if let payload = args.string(forKey: "BQDebugURL") {
            flow.camera.setPaused(true)
            flow.start(ScannedCode(text: payload, source: .debug))
        }
    }
}

/// Debug builds only: injects any corpus sample as if it had been scanned (the Simulator has no
/// camera). The corpus is copied into Debug builds by a build phase and never ships in Release.
struct DebugSamplesScreen: View {
    let flow: ScanFlow
    let close: () -> Void
    @State private var liveNetwork = false
    @State private var search = ""

    struct Sample: Decodable, Identifiable {
        struct Title: Decodable { var cs: String; var en: String }
        struct OCR: Decodable { var printed: String?; var near: String? }
        var id: String
        var group: String
        var title: Title
        var payload: String
        var symbology: String?
        var network: String?
        var inspection: Inspection?
        var completeness: Completeness?
        var ocr: OCR?
    }

    struct Corpus: Decodable { var samples: [Sample] }

    static let samples: [Sample] = {
        guard let url = Bundle.main.url(forResource: "samples", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let corpus = try? JSONDecoder().decode(Corpus.self, from: data) else { return [] }
        return corpus.samples
    }()

    var filtered: [Sample] {
        search.isEmpty ? Self.samples : Self.samples.filter { $0.id.localizedCaseInsensitiveContains(search) || $0.title.cs.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List {
            #if DEBUG
            Section { Toggle("Skutečná kontrola sítě (místo uložené ukázky)", isOn: $liveNetwork) }
            #endif
            ForEach(["links", "payments", "comms", "security", "places", "other"], id: \.self) { group in
                let items = filtered.filter { $0.group == group }
                if !items.isEmpty {
                    Section(group) {
                        ForEach(items) { sample in
                            Button {
                                inject(sample)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(Language.preferred == .en ? sample.title.en : sample.title.cs)
                                    Text(sample.id).font(.caption.monospaced()).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .searchable(text: $search)
        .navigationTitle(L10n.t("set.debug", [:], .preferred))
    }

    private func inject(_ sample: Sample) {
        close()
        let live = liveNetwork
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(450))
            DebugSamplesScreen.replay(sample, in: flow, live: live)
        }
    }

    static func replay(_ sample: Sample, in flow: ScanFlow, live: Bool) {
        let code = ScannedCode(text: sample.payload, symbology: Symbology(rawValue: sample.symbology ?? "qr") ?? .qr, source: .debug)
        if live {
            flow.camera.setPaused(true)
            flow.start(code)
            return
        }
        var inspection = sample.inspection
        if inspection != nil, inspection?.completeness == nil { inspection?.completeness = sample.completeness }
        if inspection == nil, let c = sample.completeness, c.state != .skipped, sample.network != "offline" {
            inspection = Inspection(completeness: c)
        }
        flow.injectReplay(code, inspection: inspection,
                          printed: sample.ocr.map { PrintedContext(printed: $0.printed, near: $0.near) },
                          offline: sample.network == "offline")
    }
}
#endif
