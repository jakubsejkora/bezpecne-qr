#if BQ_HOST_TESTS
@testable import BezpecneQR
#endif
import BQCore
import BQServices
import BQUI
import SwiftUI
import UniformTypeIdentifiers
import UIKit

final class ShareViewController: UIViewController {
    private var session: ShareSession?
    override func viewDidLoad() {
        super.viewDidLoad()
        let session = ShareSession { [weak self] in self?.extensionContext?.completeRequest(returningItems: nil) }
        self.session = session
        let host = UIHostingController(rootView: AppearanceHost(hidesStatusBar: false) { ShareScreen(session: session) })
        addChild(host); view.addSubview(host.view); host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([host.view.topAnchor.constraint(equalTo: view.topAnchor), host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                                     host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor), host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
        host.didMove(toParent: self)
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
            .filter { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }
        session.load(providers)
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        session?.cancel()
    }
}

@MainActor @Observable final class ShareSession: ResultActionHandler {
    var result: ResultModel?
    var candidates: [Analysis] = []
    var comparison: MultiCodeSession?
    var capture: CapturePresentation?
    var error: String?
    var loading = true
    var captureCount = 0
    var notice = false
    @ObservationIgnored private let close: () -> Void
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private let checker: any LinkChecking
    private var codes: [LocatedCode] = []
    private var generation: UUID?
    private var epoch = UUID()
    private var ended = false
    private var selectedIDs = Set<UUID>()
    init(checker: any LinkChecking = LinkChecker(), close: @escaping () -> Void) { self.checker = checker; self.close = close }

    func load(_ providers: [NSItemProvider]) {
        guard providers.count == 1, let provider = providers.first else {
            loading = false; error = L10n.t("share.oneImage", .preferred); return
        }
        generation = try? HistoryInbox.shared?.begin()
        let ticket = epoch
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let data = try await ProviderImage.load(provider)
                let scanned = try await ImageCodeScanner.scan(data, source: .share)
                guard !Task.isCancelled, epoch == ticket, !ended else { return }
                codes = scanned.codes; loading = false
                guard !codes.isEmpty else { error = L10n.t("scan.noCode", .preferred); return }
                let local = codes.map { Analyzer().analyze($0.code, options: AnalysisOptions(pageFetch: false, domainChecks: false, offline: true)) }
                if !local.contains(where: \.isSensitive) { capture = CapturePresentation(image: UIImage(cgImage: scanned.image), regions: codes.map(\.region)) }
                captureCount += 1
                AccessibilityNotification.Announcement(L10n.t("capture.detected", ["n": String(codes.count)], .preferred)).post()
                startBatch(codes)
            } catch is CancellationError { }
            catch { guard epoch == ticket else { return }; loading = false; self.error = L10n.t("share.imageError", .preferred) }
        }
    }
    private func startBatch(_ located: [LocatedCode], manual: Bool = false) {
        comparison?.cancel(); selectedIDs.removeAll()
        let acknowledged = SharedSettings.defaults.bool(forKey: SharedSettings.networkNotice)
        let options = AnalysisOptions(pageFetch: acknowledged && SharedSettings.enabled(SharedSettings.pageFetch),
                                      domainChecks: acknowledged && SharedSettings.enabled(SharedSettings.domainChecks))
        let batch = MultiCodeSession(codes: located, options: options, checker: checker, manual: manual)
        comparison = batch; candidates = batch.analyses
        notice = !acknowledged && candidates.contains { $0.linkTarget != nil && !$0.isSensitive }
        for entry in batch.entries {
            entry.model.capabilities = .imageExtension; entry.model.handler = self
            if located.count > 1 { entry.model.onShowAllCodes = { [weak self] in self?.result = nil } }
        }
        batch.onUpdate = { [weak self, weak batch] model, _ in
            guard let self, let batch, comparison === batch, !ended else { return }
            candidates = batch.analyses
            if model.analysis.isSensitive { capture = nil }
        }
        batch.start()
        result = nil
        if located.count == 1 { choose(0) }
    }
    func choose(_ index: Int) {
        guard let comparison, comparison.entries.indices.contains(index) else { return }
        let entry = comparison.entries[index]
        if let c = capture { capture = CapturePresentation(image: c.image, regions: c.regions, selected: entry.id) }
        selectedIDs.insert(entry.model.analysis.id); result = entry.model
    }
    func consent(online: Bool) {
        SharedSettings.defaults.set(true, forKey: SharedSettings.networkNotice)
        SharedSettings.defaults.set(online, forKey: SharedSettings.pageFetch)
        SharedSettings.defaults.set(online, forKey: SharedSettings.domainChecks)
        notice = false
        let selected = result?.analysis.code.text
        startBatch(codes)
        if let selected, let index = candidates.firstIndex(where: { $0.code.text == selected }) { choose(index) }
    }
    func finish() { cancel(); close() }
    func cancel() {
        guard !ended else { return }
        epoch = UUID(); task?.cancel(); task = nil
        comparison?.cancel()
        if SharedSettings.enabled(SharedSettings.history), let generation, let comparison {
            var saved = Set<UUID>()
            for entry in comparison.entries where selectedIDs.contains(entry.model.analysis.id) && saved.insert(entry.model.analysis.id).inserted {
                if let envelope = HistoryEnvelope(entry.model.analysis, generation: generation, diagnostics: comparison.diagnostics[entry.model.analysis.id]) {
                    try? HistoryInbox.shared?.put(envelope)
                }
            }
        }
        ended = true; comparison = nil
        capture = nil; codes = []; candidates = []; result = nil
    }
    func perform(_ action: ResultAction, for analysis: Analysis) async -> ActionResult {
        switch action {
        case .close, .backToScanning: finish(); return .done(toast: nil)
        case .manualCheck:
            startBatch([LocatedCode(code: analysis.code, region: CaptureRegion(corners: []))], manual: true)
            return .done(toast: nil)
        case .copy(let text, let kind):
            if kind == .password {
                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: text]], options: [.localOnly: true, .expirationDate: Date().addingTimeInterval(120)])
            } else { UIPasteboard.general.string = text }
            return .done(toast: L10n.t("toast.copied", .preferred))
        default: return .failed(L10n.t("share.continueApp", .preferred))
        }
    }
}

struct ShareScreen: View {
    @State var session: ShareSession
    @Environment(\.bqDesign) private var design
    var body: some View {
        Group {
            if let model = session.result {
                ResultScreen(model: model)
            } else if !session.candidates.isEmpty {
                ChooserView(candidates: session.candidates, checking: session.comparison?.checking ?? [], language: .preferred, onPick: session.choose, onClose: session.finish)
            } else {
                VStack(spacing: 24) {
                    Spacer()
                    if session.loading { ProgressView(); Text(L10n.t("share.reading", .preferred)).font(.title2.bold()) }
                    else { ContentUnavailableView(session.error ?? L10n.t("error.generic", .preferred), systemImage: "qrcode.viewfinder") }
                    Spacer()
                    Button(L10n.t("act.close", .preferred), action: session.finish).buttonStyle(PrimaryButtonStyle())
                }.padding(24)
            }
        }.background(design.background).environment(\.bqCapture, session.capture)
            .sensoryFeedback(.impact(weight: .medium), trigger: session.captureCount)
            .safeAreaInset(edge: .bottom) {
                if session.notice {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L10n.t("share.networkTitle", .preferred)).font(.headline)
                        Text(L10n.t("onb.privacyNote", .preferred)).font(.footnote).fixedSize(horizontal: false, vertical: true)
                        Button(L10n.t("share.online", .preferred)) { session.consent(online: true) }.buttonStyle(PrimaryButtonStyle())
                        Button(L10n.t("share.local", .preferred)) { session.consent(online: false) }.frame(maxWidth: .infinity, minHeight: 44)
                    }.padding(20).background(design.surface)
                }
            }
    }
}
