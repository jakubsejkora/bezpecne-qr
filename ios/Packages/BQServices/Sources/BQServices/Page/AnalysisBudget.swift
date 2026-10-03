import Foundation

/// Bounds the CPU time of one page analysis: the inspector's deadline and task cancellation,
/// checked every 256 steps. Once spent, every stage stops and the analysis reports `truncated`.
/// Used synchronously within one `PageAnalyzer.analyze` call.
final class AnalysisBudget {
    private let deadline: Deadline?
    private var steps = 0
    private(set) var exhausted = false

    init(deadline: Deadline?) {
        self.deadline = deadline
    }

    /// A budget that never runs out (tests, small inputs).
    static var unlimited: AnalysisBudget { AnalysisBudget(deadline: nil) }

    /// Counts one step of work; true once the deadline has passed or the task was cancelled.
    func spend() -> Bool {
        if exhausted { return true }
        steps &+= 1
        guard steps & 0xFF == 0 else { return false }
        if Task.isCancelled || deadline?.hasPassed == true { exhausted = true }
        return exhausted
    }
}
