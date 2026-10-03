import BQCore
import BQUI
import Network
import SwiftData
import SwiftUI

/// Runs a link inspection. Implemented by BQServices' inspector (see LinkChecker.swift).
protocol LinkChecking: Sendable {
    func check(_ url: URL, pageFetch: Bool, domainChecks: Bool, manual: Bool,
               progress: @escaping @Sendable (CheckStep) -> Void) async -> Inspection
}

/// The scan → freeze → analyse → inspect → verdict flow behind the scanner screen.
@MainActor
@Observable
final class ScanFlow {
    let camera = CameraController()
    let preview = PreviewBox()
    let actions = ActionHandler()
    @ObservationIgnored let analyzer = Analyzer()
    @ObservationIgnored let checker: LinkChecking
    @ObservationIgnored var modelContext: ModelContext?
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private var online = true

    /// The frozen camera frame while a sheet is open.
    var frozenImage: UIImage?
    /// Outline of the selected code in preview coordinates.
    var outline: [CGPoint] = []
    var result: ResultModel?
    /// Several codes were found: the user picks one.
    var candidates: [Analysis] = []
    var toast: String?
    var cameraAuthorization = CameraController.authorization
    var cameraUnavailable = false
    var detectionCount = 0

    @ObservationIgnored private var inspectionTask: Task<Void, Never>?
    @ObservationIgnored private var lastText: String?
    @ObservationIgnored private var cooldownUntil = Date.distantPast

    init(checker: LinkChecking) {
        self.checker = checker
        camera.onDetect = { [weak self] codes in self?.detected(codes) }
        camera.onUnavailable = { [weak self] in self?.cameraUnavailable = true }
        actions.onClose = { [weak self] in self?.dismiss() }
        actions.onManualCheck = { [weak self] in self?.manualCheck() }
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in self?.online = satisfied }
        }
        pathMonitor.start(queue: DispatchQueue(label: "cz.bezpecneqr.path"))
    }

    var isPresenting: Bool { result != nil || !candidates.isEmpty }

    // MARK: Camera

    func startCamera() {
        cameraAuthorization = CameraController.authorization
        switch cameraAuthorization {
        case .authorized:
            camera.start()
        case .notDetermined:
            Task {
                _ = await CameraController.requestAccess()
                cameraAuthorization = CameraController.authorization
                if cameraAuthorization == .authorized { camera.start() }
            }
        case .denied:
            break
        }
    }

    func stopCamera() { camera.stop() }

    func detected(_ codes: [DetectedCode]) {
        guard !isPresenting else { return }
        let now = Date()
        let fresh = codes.filter { !($0.text == lastText && now < cooldownUntil) }
        guard !fresh.isEmpty else { return }
        var seen = Set<String>()
        let distinct = fresh.filter { seen.insert($0.text).inserted }

        camera.setPaused(true)
        frozenImage = camera.snapshot()
        detectionCount += 1
        if distinct.count > 1 {
            outline = []
            candidates = distinct.map { analyzer.analyze(ScannedCode(text: $0.text, symbology: $0.symbology, source: .camera), options: options) }
        } else {
            outline = preview.viewCorners(of: distinct[0])
            start(ScannedCode(text: distinct[0].text, symbology: distinct[0].symbology, source: .camera))
        }
    }

    // MARK: Photos

    func scanPhoto(_ data: Data) async {
        let codes = await PhotoScanner.codes(in: data)
        guard !codes.isEmpty else {
            show(toast: L10n.t("scan.noCode", [:], .preferred))
            return
        }
        camera.setPaused(true)
        if codes.count > 1 {
            candidates = codes.map { analyzer.analyze($0, options: options) }
        } else {
            start(codes[0])
        }
    }

    // MARK: Analysis

    var options: AnalysisOptions {
        let defaults = UserDefaults.standard
        return AnalysisOptions(pageFetch: defaults.bool(SettingsKey.pageFetch, default: true),
                               domainChecks: defaults.bool(SettingsKey.domainChecks, default: true),
                               offline: !online)
    }

    func choose(_ index: Int) {
        guard candidates.indices.contains(index) else { return }
        let code = candidates[index].code
        candidates = []
        start(code)
    }

    func start(_ code: ScannedCode, manual: Bool = false) {
        lastText = code.text
        let options = self.options
        let analysis = analyzer.analyze(code, options: options)
        let model = result ?? ResultModel(analysis: analysis, fromCamera: code.source == .camera)
        model.analysis = analysis
        model.handler = actions
        result = model
        inspectionTask?.cancel()
        // Saved right away (history must not depend on waiting for the check); updated when final.
        save(analysis)
        if let target = analysis.linkTarget, !options.offline, options.pageFetch || options.domainChecks {
            model.isChecking = true
            model.step = .address
            inspectionTask = Task { [weak self] in
                await self?.inspect(code: code, target: target, model: model, options: options, manual: manual)
            }
        } else {
            model.isChecking = false
        }
    }

    private func inspect(code: ScannedCode, target: URL, model: ResultModel, options: AnalysisOptions, manual: Bool) async {
        let inspection = await checker.check(target, pageFetch: options.pageFetch, domainChecks: options.domainChecks, manual: manual) { step in
            Task { @MainActor in model.step = step }
        }
        guard !Task.isCancelled else { return }
        let final = analyzer.analyze(code, inspection: inspection, options: options, id: model.analysis.id)
        model.analysis = final
        model.isChecking = false
        model.step = nil
        save(final)
    }

    #if DEBUG
    /// Shows a corpus sample with its recorded inspection instead of contacting the network.
    func injectReplay(_ code: ScannedCode, inspection: Inspection?, printed: PrintedContext?, offline: Bool) {
        camera.setPaused(true)
        var options = self.options
        options.offline = offline
        let analysis = analyzer.analyze(code, inspection: inspection, printed: printed, options: options)
        let model = ResultModel(analysis: analysis, fromCamera: false)
        model.handler = actions
        model.isChecking = false
        result = model
    }
    #endif

    func manualCheck() {
        guard let model = result else { return }
        start(model.analysis.code, manual: true)
    }

    private func save(_ analysis: Analysis) {
        guard let modelContext else { return }
        HistoryStore.save(analysis, in: modelContext)
    }

    /// Re-checks a history entry.
    func recheck(_ record: ScanRecord) {
        guard let payload = record.payload else { return }
        camera.setPaused(true)
        start(ScannedCode(text: payload, symbology: Symbology(rawValue: record.symbology) ?? .qr, source: .debug))
    }

    // MARK: Dismissal

    func dismiss() {
        inspectionTask?.cancel()
        inspectionTask = nil
        result = nil
        candidates = []
        frozenImage = nil
        outline = []
        // Don't immediately re-scan the code the user just closed.
        cooldownUntil = Date().addingTimeInterval(2.5)
        camera.setPaused(false)
    }

    func show(toast text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            if toast == text { toast = nil }
        }
    }
}
