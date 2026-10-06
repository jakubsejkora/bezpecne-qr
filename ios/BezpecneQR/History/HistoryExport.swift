#if DEBUG || DESIGN_REVIEW
import BQCore
import BQUI
import SwiftData
import SwiftUI
import UIKit

@MainActor enum HistoryExport {
    struct Record: Codable {
        let id: UUID
        let date: Date
        let type: String
        let band: String
        let score: Int?
        let symbology: String
        let source: String
        let title: String?
        let payload: String?
        let redacted: Bool
        let diagnostics: CheckDiagnostics?
        let diagnosticsAvailability: String
    }
    struct Document: Codable {
        let version = 1
        let created: Date
        let appVersion: String
        let osVersion: String
        let records: [Record]
        let outcomes: [String: Int]
        let reasons: [String: Int]
        let cameraEvents: [CameraEvents.Event]
    }
    static let folder = FileManager.default.temporaryDirectory.appendingPathComponent("BQHistoryExports", isDirectory: true)
    static var generation = UUID()
    static func invalidate() { generation = UUID(); try? FileManager.default.removeItem(at: folder) }
    static func make(_ records: [ScanRecord]) throws -> String {
        let sanitized = records.map { record -> Record in
            let protected = record.payload.map {
                HistoryPrivacy.isProtected(Analyzer().analyze(ScannedCode(text: $0), options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true)))
            } ?? true
            let diagnostic = !protected && record.diagnostics?.isValid == true ? record.diagnostics : nil
            return Record(id: record.id, date: record.date, type: record.type, band: record.band, score: record.score,
                          symbology: record.symbology, source: record.source,
                          title: protected ? nil : record.title, payload: protected ? nil : record.payload,
                          redacted: protected, diagnostics: diagnostic,
                          diagnosticsAvailability: protected ? "redacted" : diagnostic == nil ? "unavailable-legacy" : "available")
        }
        let document = Document(created: Date(), appVersion: AppInfo.version, osVersion: UIDevice.current.systemVersion,
                                records: sanitized,
                                outcomes: Dictionary(grouping: sanitized, by: \.band).mapValues(\.count),
                                reasons: Dictionary(grouping: sanitized, by: { $0.diagnostics?.completeness.reason ?? $0.diagnosticsAvailability }).mapValues(\.count),
                                cameraEvents: CameraEvents.events)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(document), as: UTF8.self)
    }
    static func write(_ json: String, token: UUID) throws -> URL {
        guard generation == token else { throw CancellationError() }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("BezpecneQR-history-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url, options: [.atomic, .completeFileProtection])
        return url
    }
}

struct HistoryExportScreen: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var preview = ""
    @State private var file: URL?
    @State private var sharing = false
    @State private var error = false
    @State private var token = HistoryExport.generation
    private let lang = Language.preferred
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(L10n.t("hist.exportNotice", lang)).font(.body)
                Button(L10n.t("hist.exportShare", lang), systemImage: "square.and.arrow.up") {
                    do { file = try HistoryExport.write(preview, token: token); sharing = true }
                    catch { self.error = true }
                }.buttonStyle(.borderedProminent).controlSize(.large).tint(.blue).disabled(preview.isEmpty)
                Text(preview).font(.caption.monospaced()).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.padding(22)
        }
        .navigationTitle(L10n.t("hist.export", lang)).navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let records = try context.fetch(FetchDescriptor<ScanRecord>(sortBy: [SortDescriptor(\.date, order: .reverse)]))
                preview = try HistoryExport.make(records)
            } catch { self.error = true }
        }
        .sheet(isPresented: $sharing, onDismiss: cleanup) {
            if let file { HistoryShareSheet(url: file) { sharing = false; cleanup() } }
        }
        .alert(L10n.t("error.generic", lang), isPresented: $error) { Button(L10n.t("act.close", lang), role: .cancel) { dismiss() } }
        .onDisappear { if !sharing { cleanup() } }
    }
    private func cleanup() { if let file { try? FileManager.default.removeItem(at: file) }; file = nil }
}

private struct HistoryShareSheet: UIViewControllerRepresentable {
    let url: URL
    let completed: () -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in completed() }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
#endif
