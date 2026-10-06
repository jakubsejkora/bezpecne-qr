import BQCore
import BQServices
import BQUI
import Foundation
import SwiftData
import Testing
@testable import BezpecneQR

@MainActor @Suite(.serialized)
struct PresentationTests {
    @Test func transitionsKeepTheSessionUntilNativeDismissalCompletes() {
        let c = ResultPresentationCoordinator()
        c.update(.chooser); #expect(c.sheetVisible)
        c.update(.popup)
        #expect(c.transitioning && !c.sheetVisible && !c.coverVisible)
        c.update(.fullPage) // A later preference wins without opening a second container.
        c.didDismiss()
        #expect(c.presented == .fullPage && c.coverVisible && !c.transitioning)
        c.update(.popup); #expect(c.coverVisible && !c.transitioning)
        c.update(.sheet); #expect(c.transitioning)
        c.update(nil) // Cancel while changing containers must not reopen the old scan.
        c.didDismiss(); #expect(c.presented == nil && !c.sheetVisible && !c.coverVisible)
    }
    @Test func expandingPresentationDoesNotChangeTheAnalysisOrCheckingState() {
        let a = Analyzer().analyze(ScannedCode(text: "https://example.org"))
        let m = ResultModel(analysis: a, fromCamera: true)
        let checking = m.isChecking
        m.resultExpanded = true
        #expect(m.analysis == a && m.isChecking == checking)
        m.resetPresentation()
        #expect(!m.resultExpanded && m.analysis == a && m.isChecking == checking)
    }
    @Test func historyTitleUpdatesAfterResolutionWithoutChangingPayload() throws {
        let schema = Schema(versionedSchema: HistorySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        SharedSettings.defaults.set(true, forKey: SharedSettings.history)
        HistoryStore.invalidatePending(enabled: true)
        let token = HistoryStore.writeToken()
        let code = ScannedCode(text: "https://qrco.de/review")
        let first = Analyzer().analyze(code)
        HistoryStore.save(first, in: container.mainContext, token: token)
        let endpoint = Endpoint(url: "https://destination-bq.cz/menu", host: "destination-bq.cz", registrable: "destination-bq.cz")
        let inspection = Inspection(final: endpoint, completeness: .complete,
            destination: DestinationResolution(state: .resolved, scannedURL: code.text, lastObserved: endpoint, resolved: endpoint, allowsDirectOpen: true))
        let final = Analyzer().analyze(code, inspection: inspection, id: first.id)
        HistoryStore.save(final, in: container.mainContext, token: token)
        let rows = try container.mainContext.fetch(FetchDescriptor<ScanRecord>())
        #expect(rows.count == 1 && rows.first?.title == "destination-bq.cz")
        #expect(rows.first?.payload == code.text)

        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let inbox = HistoryInbox(directory: folder)
        try inbox.invalidate(enabled: true)
        let generation = try #require(try inbox.begin())
        var resolved = try #require(HistoryEnvelope(final, generation: generation))
        resolved.id = UUID()
        var legacy = resolved
        legacy.id = UUID(); legacy.version = 1; legacy.resolvedHost = nil
        try inbox.put(resolved); try inbox.put(legacy)
        HistoryStore.importInbox(in: container.mainContext, from: inbox)
        let imported = try container.mainContext.fetch(FetchDescriptor<ScanRecord>())
        #expect(imported.count == 3)
        #expect(imported.first { $0.id == resolved.id }?.title == "destination-bq.cz")
        #expect(imported.first { $0.id == legacy.id }?.title == "qrco.de")
        #expect(imported.allSatisfy { $0.payload == code.text })
        try inbox.put(resolved) // Retry after a crash between DB save and acknowledgment.
        HistoryStore.importInbox(in: container.mainContext, from: inbox)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<ScanRecord>()) == 3)
        #expect(try inbox.entries().isEmpty)
    }
}
