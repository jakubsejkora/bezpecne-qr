import BQCore
import BQUI
import Foundation
import Observation

/// Shared app/extension batch. Occurrences keep their geometry, identical payloads share one model.
@MainActor @Observable final class MultiCodeSession {
    struct Entry: Identifiable {
        let located: LocatedCode
        let model: ResultModel
        var id: UUID { located.id }
    }
    let entries: [Entry]
    private(set) var diagnostics: [UUID: CheckDiagnostics] = [:]
    @ObservationIgnored var onUpdate: ((ResultModel, CheckDiagnostics) -> Void)?
    @ObservationIgnored private let checker: any LinkChecking
    private let options: AnalysisOptions
    @ObservationIgnored private var work: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var timeout: Task<Void, Never>?
    private var queue: [ResultModel] = []
    private var epoch = UUID()
    private var ended = false
    private let budget: Duration
    private let manual: Bool
    var analyses: [Analysis] { entries.map { $0.model.analysis } }
    var checking: Set<Int> { Set(entries.indices.filter { entries[$0].model.isChecking }) }

    init(codes: [LocatedCode], options: AnalysisOptions, checker: any LinkChecking, budget: Duration = .seconds(8), manual: Bool = false) {
        self.options = options; self.checker = checker; self.budget = budget; self.manual = manual
        var models: [String: ResultModel] = [:]
        entries = codes.map { located in
            let key = located.code.symbology.rawValue + ":" + located.code.text
            let model = models[key] ?? ResultModel(analysis: Analyzer().analyze(located.code, options: options), fromCamera: located.code.source == .camera)
            models[key] = model
            return Entry(located: located, model: model)
        }
    }

    func start() {
        guard !ended, work.isEmpty, timeout == nil else { return }
        var seen = Set<UUID>()
        for entry in entries where seen.insert(entry.model.analysis.id).inserted {
            let model = entry.model
            model.isChecking = model.analysis.linkTarget != nil && !options.offline && (options.pageFetch || options.domainChecks)
            if model.isChecking { model.step = .address; queue.append(model) }
            else { publish(model, timings: [:]) }
        }
        let ticket = epoch
        timeout = Task { [weak self, budget] in
            try? await Task.sleep(for: budget)
            guard !Task.isCancelled, let self, epoch == ticket else { return }
            finishPending(reason: "inc.timeout")
        }
        schedule(ticket)
    }

    private func schedule(_ ticket: UUID) {
        while work.count < 3, !queue.isEmpty, !ended {
            let model = queue.removeFirst()
            let timing = CheckTiming()
            guard let url = model.analysis.linkTarget else { continue }
            let id = model.analysis.id
            work[id] = Task { [weak self, weak model, checker, options, manual] in
                let inspection = await checker.check(url, pageFetch: options.pageFetch, domainChecks: options.domainChecks, manual: manual) { [weak self, weak model] step in
                    timing.mark(step)
                    Task { @MainActor [weak self, weak model] in
                        guard let self, self.epoch == ticket, !self.ended else { return }; model?.step = step
                    }
                }
                guard !Task.isCancelled, let self, let model, epoch == ticket, !ended else { return }
                model.analysis = Analyzer().analyze(model.analysis.code, inspection: inspection, options: options, id: id)
                model.isChecking = false; model.step = nil
                publish(model, timings: timing.finish())
                work[id] = nil; schedule(ticket)
            }
        }
        if work.isEmpty && queue.isEmpty { timeout?.cancel(); timeout = nil }
    }

    func cancel() {
        guard !ended else { return }
        finishPending(reason: "inc.cancelled"); ended = true
    }
    private func finishPending(reason: String) {
        epoch = UUID(); timeout?.cancel(); timeout = nil
        work.values.forEach { $0.cancel() }; work.removeAll(); queue.removeAll()
        var seen = Set<UUID>()
        for entry in entries where seen.insert(entry.model.analysis.id).inserted && entry.model.isChecking {
            let model = entry.model
            let incomplete = Inspection(completeness: Completeness(.incomplete, reason: reason), transportError: reason == "inc.cancelled" ? "cancelled" : "timeout")
            model.analysis = Analyzer().analyze(model.analysis.code, inspection: incomplete, options: options, id: model.analysis.id)
            model.isChecking = false; model.step = nil; publish(model, timings: [:])
        }
    }
    private func publish(_ model: ResultModel, timings: [String: Int]) {
        let detail = CheckDiagnostics(model.analysis, options: options, timings: timings)
        diagnostics[model.analysis.id] = detail; onUpdate?(model, detail)
    }
    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }
}
