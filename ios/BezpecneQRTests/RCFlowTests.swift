import BQCore
import BQServices
import BQUI
import Foundation
import SwiftData
import Testing
@testable import BezpecneQR

private actor BatchChecker: LinkChecking {
    private(set) var calls = 0
    private(set) var active = 0
    private(set) var peak = 0
    var delay: Duration
    init(delay: Duration) { self.delay = delay }
    func check(_ url: URL, pageFetch: Bool, domainChecks: Bool, manual: Bool,
               progress: @escaping @Sendable (CheckStep) -> Void) async -> Inspection {
        calls += 1; active += 1; peak = max(peak, active)
        defer { active -= 1 }
        progress(.page)
        try? await Task.sleep(for: delay)
        // Deliberately return success after cancellation: owners must reject this stale callback.
        let endpoint = Endpoint(url: url.absoluteString, host: url.host!, registrable: "example.org")
        return Inspection(final: endpoint, completeness: .complete,
                          destination: DestinationResolution(state: .resolved, scannedURL: url.absoluteString, resolved: endpoint))
    }
}

@MainActor @Suite(.serialized) struct RCFlowTests {
    private func code(_ raw: String) -> LocatedCode {
        LocatedCode(code: ScannedCode(text: raw), region: CaptureRegion(rect: CGRect(x: 0.1, y: 0.2, width: 0.2, height: 0.2)))
    }
    @Test func duplicateOccurrencesShareInspectionButKeepMarkerIdentity() async throws {
        let checker = BatchChecker(delay: .milliseconds(20))
        let session = MultiCodeSession(codes: [code("https://example.org/menu"), code("https://example.org/menu"), code("Plain text")], options: AnalysisOptions(), checker: checker)
        #expect(session.entries[0].id != session.entries[1].id)
        #expect(session.entries[0].model === session.entries[1].model)
        session.start()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await checker.calls == 1)
        #expect(session.checking.isEmpty)
        #expect(session.analyses[0].resolvedHost == "example.org")
        #expect(session.diagnostics[session.analyses[0].id]?.stageTimingsMS["total"] != nil)
        session.cancel()
    }
    @Test func sceneBudgetCoversQueuedChecksAndIgnoresLateSuccess() async throws {
        let checker = BatchChecker(delay: .seconds(2))
        let codes = (0..<5).map { code("https://example.org/menu/\($0)") }
        let session = MultiCodeSession(codes: codes, options: AnalysisOptions(), checker: checker, budget: .milliseconds(60))
        session.start()
        try await Task.sleep(for: .milliseconds(180))
        #expect(await checker.calls == 3)
        #expect(await checker.peak == 3)
        #expect(session.checking.isEmpty)
        #expect(session.analyses.allSatisfy { $0.completeness.reason == "inc.timeout" && $0.resolvedHost == nil })
        #expect(session.diagnostics.count == 5)
        session.cancel()
    }
    @Test func closingWaitsForActualDismissalAndHistoryNeverStartsCamera() {
        let flow = ScanFlow(checker: BatchChecker(delay: .seconds(1)))
        flow.start(ScannedCode(text: "Hello"))
        flow.presentationVisible = true
        flow.dismiss()
        #expect(!flow.scanningAllowed)
        flow.presentationDidDismiss()
        #expect(flow.scanningAllowed)
        flow.scannerVisible = false
        flow.start(ScannedCode(text: "From history")); flow.presentationVisible = true
        flow.dismiss(); flow.presentationDidDismiss()
        #expect(!flow.scanningAllowed)
        flow.updateCamera()
    }
    @Test func cachedSelectionReturnsToComparisonWithoutRechecking() async throws {
        SharedSettings.defaults.set(true, forKey: SharedSettings.pageFetch)
        SharedSettings.defaults.set(true, forKey: SharedSettings.domainChecks)
        let checker = BatchChecker(delay: .milliseconds(10)), flow = ScanFlow(checker: checker)
        let detections = ["https://example.org/menu", "https://example.org/contact"].map {
            DetectedCode(text: $0, symbology: .qr, bounds: .zero, corners: [])
        }
        flow.detected(detections)
        try await Task.sleep(for: .milliseconds(100))
        flow.choose(0)
        let model = flow.result
        flow.showAllCodes(); #expect(flow.result == nil && flow.candidates.count == 2)
        flow.choose(0); #expect(flow.result === model)
        flow.choose(1); #expect(flow.result !== model)
        #expect(await checker.calls == 2)
        flow.dismiss(); flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func historyMigratesV1WithoutLosingOriginalPayload() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("history.store"), id = UUID()
        func seed() throws {
            let schema = Schema(versionedSchema: HistorySchemaV1.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
            container.mainContext.insert(HistorySchemaV1.ScanRecord(id: id, date: Date(), type: "text", band: "info", score: nil, title: "Original", symbology: "qr", source: "camera", payload: "Original payload"))
            try container.mainContext.save()
        }
        try seed()
        let schema = Schema(versionedSchema: HistorySchemaV2.self)
        let container = try ModelContainer(for: schema, migrationPlan: HistoryMigrationPlan.self, configurations: ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
        let records = try container.mainContext.fetch(FetchDescriptor<ScanRecord>())
        #expect(records.count == 1 && records.first?.id == id && records.first?.payload == "Original payload")
        #expect(records.first?.diagnostics == nil)
    }
    @Test func fullExportRedactsSecretsAndIsInvalidatedOnClear() throws {
        let schema = Schema(versionedSchema: HistorySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let records = ["Personal note", "https://example.org/?token=secretprivatevalue123456789", "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP"].map {
            ScanRecord(id: UUID(), date: Date(), type: "text", band: "info", score: nil, title: $0, symbology: "qr", source: "camera", payload: $0)
        }
        let json = try HistoryExport.make(records)
        #expect(json.contains("Personal note"))
        #expect(!json.contains("secretprivatevalue") && !json.contains("JBSWY3DPEHPK3PXP"))
        #expect(json.contains("unavailable-legacy"))
        let token = HistoryExport.generation
        let url = try HistoryExport.write(json, token: token)
        #expect(FileManager.default.fileExists(atPath: url.path))
        HistoryStore.clear(in: container.mainContext)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(throws: CancellationError.self) { try HistoryExport.write(json, token: token) }
    }
}
