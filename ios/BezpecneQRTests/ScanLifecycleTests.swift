import BQCore
import BQServices
import BQUI
import SwiftData
import Testing
import UIKit
@testable import BezpecneQR

private actor DeferredChecker: LinkChecking {
    var pending: CheckedContinuation<Inspection, Never>?
    var observer: CheckedContinuation<Void, Never>?
    func check(_ url: URL, pageFetch: Bool, domainChecks: Bool, manual: Bool, progress: @escaping @Sendable (CheckStep) -> Void) async -> Inspection {
        await withCheckedContinuation { continuation in
            pending = continuation; observer?.resume(); observer = nil
        }
    }
    func started() async {
        if pending != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func finish() { pending?.resume(returning: Inspection(completeness: .complete)); pending = nil }
}

@MainActor @Suite(.serialized)
struct ScanLifecycleTests {
    @Test func aimingPreviewRejectsDetectionAndResumesAfterDismissal() {
        let flow = ScanFlow(checker: DeferredChecker())
        let code = DetectedCode(text: "Preview must not scan", symbology: .qr, bounds: .zero, corners: [])
        flow.previewAim()
        #expect(flow.isAimPreview && !flow.scanningAllowed)
        flow.detected([code])
        #expect(flow.result == nil && flow.candidates.isEmpty && flow.capture == nil)
        #expect(flow.detectionCount == 0)
        flow.dismiss()
        #expect(!flow.isAimPreview && flow.scanningAllowed)
        flow.detected([code])
        #expect(flow.result?.analysis.code.text == code.text)
        flow.dismiss(); flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func visibilityAndPresentationsGateDetection() {
        let flow = ScanFlow(checker: DeferredChecker())
        #expect(flow.scanningAllowed)
        flow.scannerVisible = false; #expect(!flow.scanningAllowed)
        flow.scannerVisible = true; flow.appActive = false; #expect(!flow.scanningAllowed)
        flow.appActive = true; flow.photoPickerVisible = true; #expect(!flow.scanningAllowed)
        flow.photoPickerVisible = false; flow.importing = true; #expect(!flow.scanningAllowed)
        flow.cancelImport(); #expect(flow.scanningAllowed)
        flow.replayHeld = true; #expect(!flow.scanningAllowed)
        flow.dismiss(); flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func duplicateDetectionAndCooldownDoNotReopenResult() {
        let flow = ScanFlow(checker: DeferredChecker())
        let code = DetectedCode(text: "A plain text code", symbology: .qr, bounds: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.2), corners: [])
        flow.detected([code, code])
        #expect(flow.result != nil)
        #expect(flow.candidates.isEmpty)
        #expect(flow.detectionCount == 1)
        flow.dismiss(); flow.detected([code])
        #expect(flow.result == nil)
        #expect(flow.detectionCount == 1)
        flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func multiCodeRequiresChoiceAndPreservesSelectedIdentity() {
        let flow = ScanFlow(checker: DeferredChecker())
        let first = DetectedCode(text: "First", symbology: .qr, bounds: .zero, corners: [])
        let second = DetectedCode(text: "Second", symbology: .qr, bounds: .zero, corners: [])
        flow.detected([first, second])
        #expect(flow.result == nil)
        #expect(flow.candidates.count == 2)
        #expect(!flow.scanningAllowed)
        flow.choose(1)
        #expect(flow.result?.analysis.code.text == "Second")
        flow.dismiss(); flow.detected([first, second])
        #expect(flow.result == nil)
        #expect(flow.candidates.isEmpty)
        // Every member of the captured scene remains in cooldown, even if it was not selected.
        flow.detected([first]); #expect(flow.result == nil)
        let newCode = DetectedCode(text: "Third", symbology: .qr, bounds: .zero, corners: [])
        flow.detected([newCode]); #expect(flow.result?.analysis.code.text == "Third")
        flow.dismiss(); flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func sensitiveScanDiscardsPreviouslyHeldImage() {
        let flow = ScanFlow(checker: DeferredChecker())
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 20)).image { _ in }
        flow.capture = CapturePresentation(image: image, regions: [CaptureRegion(rect: CGRect(x: 0, y: 0, width: 1, height: 1))])
        flow.start(ScannedCode(text: "otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP"))
        #expect(flow.result?.analysis.isSensitive == true)
        #expect(flow.capture == nil)
        flow.dismiss(); flow.scannerVisible = false; flow.updateCamera()
    }
    @Test func cancelledCheckCannotReplaceNextResult() async {
        SharedSettings.defaults.set(true, forKey: SharedSettings.pageFetch)
        let checker = DeferredChecker(), flow = ScanFlow(checker: checker)
        flow.scannerVisible = false
        flow.start(ScannedCode(text: "https://example.org"))
        await checker.started()
        flow.dismiss()
        flow.start(ScannedCode(text: "Next plain text"))
        let id = flow.result?.analysis.id
        await checker.finish()
        for _ in 0..<20 { await Task.yield() }
        #expect(flow.result?.analysis.id == id)
        #expect(flow.result?.analysis.code.text == "Next plain text")
        #expect(flow.result?.isChecking == false)
        flow.dismiss()
    }
    @Test func clearingHistoryInvalidatesInFlightAppWrites() throws {
        let schema = Schema(versionedSchema: HistorySchemaV2.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        let context = container.mainContext
        SharedSettings.defaults.set(true, forKey: SharedSettings.history)
        HistoryStore.invalidatePending(enabled: true)
        let token = HistoryStore.writeToken()
        let analysis = Analyzer().analyze(ScannedCode(text: "A scan before clear"))
        HistoryStore.save(analysis, in: context, token: token)
        #expect(try context.fetchCount(FetchDescriptor<ScanRecord>()) == 1)
        HistoryStore.clear(in: context)
        HistoryStore.save(analysis, in: context, token: token)
        #expect(try context.fetchCount(FetchDescriptor<ScanRecord>()) == 0)
    }
}
