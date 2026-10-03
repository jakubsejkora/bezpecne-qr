#if DEBUG
import BQCore
import BQUI
import SwiftUI

/// Debug launch arguments for scripted Simulator checks:
/// `-BQDebugSample <corpus id>` replays a sample, `-BQDebugURL <url>` scans a payload live.
@MainActor
enum DebugLaunch {
    private static var done = false

    /// `-BQDebugOpen settings` opens Settings at launch (for screenshots).
    static var openSettings: Bool { UserDefaults.standard.string(forKey: "BQDebugOpen") == "settings" }

    static func run(_ flow: ScanFlow) {
        guard !done else { return }
        done = true
        let args = UserDefaults.standard
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
            Section {
                Toggle("Skutečná kontrola sítě (místo uložené ukázky)", isOn: $liveNetwork)
            } footer: {
                Text("\(Self.samples.count) vzorků ze shared/testdata/samples.json")
            }
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
