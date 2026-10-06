import BQCore
import BQServices
import BQUI
import Network
import SwiftData
import SwiftUI

/// Owns one scan session. Camera visibility, async work and capture imagery share the same lifecycle.
@MainActor @Observable
final class ScanFlow {
    let camera = CameraController()
    let preview = PreviewBox()
    let actions = ActionHandler()
    @ObservationIgnored let analyzer = Analyzer()
    @ObservationIgnored let checker: LinkChecking
    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored var onRecoveryHelp: (() -> Void)?
    @ObservationIgnored var onShowScanner: (() -> Void)?
    private var online = true
    var result: ResultModel?
    var candidates: [Analysis] = []
    var capture: CapturePresentation?
    var toast: String?
    var cameraAuthorization = CameraController.authorization
    var cameraUnavailable = false
    var cameraState = CameraController.State.stopped
    var torchOn = false
    var torchAvailable = false
    var presentationVisible = false
    private var freezing = false
    var comparison: MultiCodeSession?
    private var selectedIDs = Set<UUID>()
    private var sceneHistoryToken: HistoryStore.WriteToken?
    private var currentOptions = AnalysisOptions()
    private var currentHistoryToken: HistoryStore.WriteToken?
    @ObservationIgnored private var refinementTask: Task<Void, Never>?
    private var lastTexts = Set<String>()
    var detectionCount = 0
    var scannerVisible = true
    var appActive = true
    var photoPickerVisible = false
    var importing = false
    var replayHeld = false
    var replayMultiple = false
    var replayScene = "single"
    #if DEBUG || DESIGN_REVIEW
    var aimingPreview = false
    #endif
    var isAimPreview: Bool {
        #if DEBUG || DESIGN_REVIEW
        aimingPreview
        #else
        false
        #endif
    }
    private var previewing = false
    private var located: [LocatedCode] = []
    private var epoch = UUID()
    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var permissionTask: Task<Void, Never>?
    private var lastText: String?
    private var cooldownUntil = Date.distantPast

    init(checker: LinkChecking) {
        self.checker = checker
        camera.onDetect = { [weak self] in self?.detected($0) }
        camera.onState = { [weak self] state in
            guard let self else { return }
            cameraState = state; cameraUnavailable = state == .failed
            CameraEvents.record(state)
        }
        camera.onTorch = { [weak self] on, available in self?.torchOn = on; self?.torchAvailable = available }
        actions.onClose = { [weak self] in self?.dismiss() }
        actions.onManualCheck = { [weak self] in self?.manualCheck() }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let status = path.status != .unsatisfied
            Task { @MainActor in self?.online = status }
        }
        pathMonitor.start(queue: DispatchQueue(label: "cz.bezpecneqr.path"))
    }
    var isPresenting: Bool { result != nil || !candidates.isEmpty }
    var scanningAllowed: Bool { scannerVisible && appActive && !isPresenting && !presentationVisible && !freezing && !photoPickerVisible && !importing && !replayHeld && !isAimPreview }

    func updateCamera() {
        cameraAuthorization = CameraController.authorization
        guard scanningAllowed else { camera.setPaused(true); camera.stop(); return }
        switch cameraAuthorization {
        case .authorized: camera.setPaused(false); camera.start()
        case .notDetermined:
            guard permissionTask == nil else { return }
            permissionTask = Task { [weak self] in
                _ = await CameraController.requestAccess()
                guard let self else { return }
                permissionTask = nil; updateCamera()
            }
        case .denied: camera.setPaused(true); camera.stop()
        }
    }
    func startCamera() { updateCamera() }
    func stopCamera() { camera.setPaused(true); camera.stop() }

    func detected(_ codes: [DetectedCode]) {
        guard scanningAllowed else { return }
        var fresh: [DetectedCode] = []
        for code in codes where !fresh.contains(code) { fresh.append(code) }
        guard !fresh.isEmpty, !(Date() < cooldownUntil && fresh.contains { lastTexts.contains($0.text) }) else { return }
        camera.setPaused(true)
        let local = fresh.map { analyzer.analyze(ScannedCode(text: $0.text, symbology: $0.symbology, source: .camera), options: options) }
        let image = local.contains(where: \.isSensitive) ? nil : camera.snapshot()
        let metadata = fresh.map { LocatedCode(code: ScannedCode(text: $0.text, symbology: $0.symbology, source: .camera),
                                               region: preview.region(of: $0, imageSize: image?.size ?? .zero)) }
        camera.discardFrame()
        guard let image, let cg = image.cgImage else { receive(metadata, image: nil); return }
        freezing = true; updateCamera(); let ticket = epoch
        refinementTask = Task { [weak self] in
            let refined = (try? await ImageCodeScanner.codes(in: cg, source: .camera)) ?? []
            guard !Task.isCancelled, let self, epoch == ticket, scannerVisible, appActive else { return }
            var merged = refined
            // Keep metadata candidates that Vision missed. For matches, carry the original identity.
            var available = metadata
            for i in merged.indices {
                if let match = available.indices.filter({ available[$0].code.text == merged[i].code.text }).min(by: {
                    let a = available[$0].region.bounds, b = available[$1].region.bounds, c = merged[i].region.bounds
                    return hypot(a.midX - c.midX, a.midY - c.midY) < hypot(b.midX - c.midX, b.midY - c.midY)
                }) { merged[i].region.id = available.remove(at: match).id }
            }
            merged += available.filter { candidate in !refined.contains { $0.code.text == candidate.code.text } }
            freezing = false; receive(merged.isEmpty ? metadata : merged, image: image)
        }
    }
    private func receive(_ codes: [LocatedCode], image: UIImage?) {
        if codes.first?.code.source == .camera, Date() < cooldownUntil, codes.contains(where: { lastTexts.contains($0.code.text) }) {
            updateCamera(); return
        }
        located = codes; lastTexts = Set(codes.map { $0.code.text })
        let local = codes.map { analyzer.analyze($0.code, options: options) }
        capture = local.contains(where: \.isSensitive) ? nil : image.map { CapturePresentation(image: $0, regions: codes.map(\.region)) }
        detectionCount += 1
        AccessibilityNotification.Announcement(L10n.t("capture.detected", ["n": String(codes.count)], .preferred)).post()
        if codes.count > 1 { beginComparison(codes) }
        else if let code = codes.first?.code { start(code) }
    }
    private func beginComparison(_ codes: [LocatedCode]) {
        comparison?.cancel(); selectedIDs.removeAll()
        let batch = MultiCodeSession(codes: codes, options: options, checker: checker)
        comparison = batch; sceneHistoryToken = HistoryStore.writeToken()
        candidates = batch.analyses
        for entry in batch.entries {
            entry.model.handler = actions; entry.model.onRecoveryHelp = onRecoveryHelp
            entry.model.onShowAllCodes = { [weak self] in self?.showAllCodes() }
        }
        batch.onUpdate = { [weak self, weak batch] model, diagnostic in
            guard let self, let batch, comparison === batch else { return }
            candidates = batch.analyses
            if model.analysis.isSensitive { capture = nil; camera.discardFrame() }
            if selectedIDs.contains(model.analysis.id), let token = sceneHistoryToken {
                save(model.analysis, token: token, diagnostics: diagnostic)
            }
        }
        batch.start(); updateCamera()
    }
    func showAllCodes() { guard let comparison else { return }; result = nil; candidates = comparison.analyses }
    func presentationDidDismiss() { presentationVisible = false; updateCamera() }
    func retryCamera() { guard scanningAllowed else { return }; cameraUnavailable = false; camera.setPaused(false); camera.retry() }
    func toggleTorch() { camera.setTorch(!torchOn) }
    func scanPhoto(_ data: Data) async {
        guard !Task.isCancelled, scannerVisible, appActive, !isPresenting else { cancelImport(); return }
        let ticket = UUID(); epoch = ticket; importing = true; updateCamera()
        do {
            let scanned = try await ImageCodeScanner.scan(data)
            guard !Task.isCancelled, epoch == ticket, scannerVisible, appActive else {
                if epoch == ticket { importing = false; updateCamera() }; return
            }
            importing = false
            guard !scanned.codes.isEmpty else { show(toast: L10n.t("scan.noCode", .preferred)); updateCamera(); return }
            receive(scanned.codes, image: UIImage(cgImage: scanned.image))
        } catch {
            guard epoch == ticket else { return }
            show(toast: L10n.t(error is ImageScanError ? "share.imageError" : "error.generic", .preferred))
        }
        if epoch == ticket { importing = false; updateCamera() }
    }
    func cancelImport() {
        if importing || freezing { epoch = UUID(); importing = false; freezing = false; refinementTask?.cancel(); refinementTask = nil }
        updateCamera()
    }
    var options: AnalysisOptions {
        AnalysisOptions(pageFetch: SharedSettings.enabled(SharedSettings.pageFetch),
                        domainChecks: SharedSettings.enabled(SharedSettings.domainChecks), offline: !online)
    }
    func choose(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        if let c = capture, located.indices.contains(index) {
            capture = CapturePresentation(image: c.image, regions: c.regions, selected: located[index].id)
        }
        if let batch = comparison, batch.entries.indices.contains(index) {
            let model = batch.entries[index].model
            selectedIDs.insert(model.analysis.id); result = model
            if let token = sceneHistoryToken { save(model.analysis, token: token, diagnostics: batch.diagnostics[model.analysis.id] ?? CheckDiagnostics(model.analysis, options: options)) }
            updateCamera(); return
        }
        let code = candidates[index].code
        candidates = []
        #if DEBUG || DESIGN_REVIEW
        if previewing { injectReplay(code, inspection: nil, printed: nil, offline: true); return }
        #endif
        start(code)
    }
    func start(_ code: ScannedCode, manual: Bool = false) {
        cancelCheck()
        comparison?.cancel(); comparison = nil; candidates = []; selectedIDs.removeAll()
        epoch = UUID(); let ticket = epoch
        replayHeld = false; lastText = code.text; lastTexts = [code.text]
        let options = options
        let historyToken = HistoryStore.writeToken()
        currentOptions = options; currentHistoryToken = historyToken
        let analysis = analyzer.analyze(code, options: options)
        if analysis.isSensitive { capture = nil; camera.discardFrame() }
        let model = ResultModel(analysis: analysis, fromCamera: code.source == .camera)
        model.handler = actions; model.onRecoveryHelp = onRecoveryHelp
        result = model
        inspectionTask?.cancel()
        save(analysis, token: historyToken, diagnostics: CheckDiagnostics(analysis, options: options)); updateCamera()
        if let target = analysis.linkTarget, !options.offline, options.pageFetch || options.domainChecks {
            model.isChecking = true; model.step = .address
            inspectionTask = Task { [weak self] in
                guard let self else { return }
                let timing = CheckTiming()
                let inspection = await checker.check(target, pageFetch: options.pageFetch, domainChecks: options.domainChecks, manual: manual) { [weak self, weak model] step in
                    timing.mark(step)
                    Task { @MainActor in guard let self, self.epoch == ticket, self.result === model else { return }; model?.step = step }
                }
                guard !Task.isCancelled, epoch == ticket, result === model else { return }
                let final = analyzer.analyze(code, inspection: inspection, options: options, id: model.analysis.id)
                if final.isSensitive { capture = nil; camera.discardFrame() }
                model.analysis = final; model.isChecking = false; model.step = nil
                save(final, token: historyToken, diagnostics: CheckDiagnostics(final, options: options, timings: timing.finish()))
            }
        } else { model.isChecking = false }
    }
    func manualCheck() { if let result { start(result.analysis.code, manual: true) } }
    private func save(_ analysis: Analysis, token: HistoryStore.WriteToken, diagnostics: CheckDiagnostics? = nil) {
        if let modelContext { HistoryStore.save(analysis, in: modelContext, token: token, diagnostics: diagnostics) }
    }
    private func cancelCheck() {
        inspectionTask?.cancel(); inspectionTask = nil
        guard comparison == nil, let model = result, model.isChecking, let token = currentHistoryToken else { return }
        let inspection = Inspection(completeness: Completeness(.incomplete, reason: "inc.cancelled"), transportError: "cancelled")
        model.analysis = analyzer.analyze(model.analysis.code, inspection: inspection, options: currentOptions, id: model.analysis.id)
        model.isChecking = false; model.step = nil
        save(model.analysis, token: token, diagnostics: CheckDiagnostics(model.analysis, options: currentOptions))
    }
    func recheck(_ record: ScanRecord) {
        guard let payload = record.payload else { return }
        capture = nil; located = []
        start(ScannedCode(text: payload, symbology: Symbology(rawValue: record.symbology) ?? .qr, source: .debug))
    }
    func dismiss() {
        #if DEBUG || DESIGN_REVIEW
        aimingPreview = false
        #endif
        epoch = UUID(); cancelCheck(); comparison?.cancel(); comparison = nil
        refinementTask?.cancel(); refinementTask = nil; freezing = false
        result = nil; candidates = []; capture = nil; located = []; replayHeld = false; previewing = false
        camera.discardFrame(); cooldownUntil = Date().addingTimeInterval(2.5); updateCamera()
    }
    func show(toast text: String) {
        toast = text
        Task { try? await Task.sleep(for: .seconds(2.5)); if toast == text { toast = nil } }
    }
    #if DEBUG || DESIGN_REVIEW
    func injectComparisonReplay(_ analyses: [Analysis], image: CapturePresentation) {
        dismiss(); previewing = true; sceneHistoryToken = nil
        let codes = analyses.enumerated().map { index, analysis in
            LocatedCode(code: analysis.code, region: image.regions[index % image.regions.count])
        }
        located = codes
        let batch = MultiCodeSession(codes: codes, options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true), checker: checker)
        for (index, entry) in batch.entries.enumerated() {
            entry.model.analysis = analyses[index]; entry.model.isChecking = false
            entry.model.handler = actions; entry.model.capabilities = .preview
            entry.model.onShowAllCodes = { [weak self] in self?.showAllCodes() }
        }
        comparison = batch; candidates = analyses; capture = analyses.contains(where: \.isSensitive) ? nil : image
        updateCamera()
    }
    func previewAim() {
        dismiss(); aimingPreview = true; onShowScanner?(); updateCamera()
    }
    func injectReplay(_ code: ScannedCode, inspection: Inspection?, printed: PrintedContext?, offline: Bool) {
        inspectionTask?.cancel(); epoch = UUID(); replayHeld = false
        var options = options; options.offline = offline
        let analysis = analyzer.analyze(code, inspection: inspection, printed: printed, options: options)
        if analysis.isSensitive { capture = nil; camera.discardFrame() }
        let model = ResultModel(analysis: analysis, fromCamera: false)
        model.handler = actions; model.capabilities = .preview; model.onRecoveryHelp = onRecoveryHelp
        model.isChecking = false; result = model; updateCamera()
    }
    func continueReplay() {
        guard let capture else { return }
        replayHeld = false; previewing = true
        located = capture.regions.enumerated().map { i, region in
            LocatedCode(code: ScannedCode(text: "https://example.org/preview/\(i + 1)", source: .debug), region: region)
        }
        if located.count > 1 {
            candidates = located.map { analyzer.analyze($0.code, options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true)) }
            updateCamera()
        } else if let code = located.first?.code { injectReplay(code, inspection: nil, printed: nil, offline: true) }
    }
    func holdReplay(_ presentation: CapturePresentation, multiple: Bool) {
        dismiss(); replayMultiple = multiple; replayHeld = true; capture = presentation; updateCamera()
    }
    #endif
}
