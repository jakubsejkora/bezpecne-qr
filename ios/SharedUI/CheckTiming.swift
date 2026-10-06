import BQUI
import Foundation

/// Stage callbacks can arrive on any queue; only elapsed durations are retained.
final class CheckTiming: @unchecked Sendable {
    private let lock = NSLock()
    private let start = ContinuousClock.now
    private var previous = ContinuousClock.now
    private var stage = "address"
    private var durations: [String: Int] = [:]
    func mark(_ step: CheckStep) {
        let next: String = switch step { case .address: "address"; case .domain: "domain"; case .redirects: "redirects"; case .page: "page" }
        lock.lock(); defer { lock.unlock() }
        let now = ContinuousClock.now
        durations[stage, default: 0] += Self.ms(previous.duration(to: now))
        stage = next; previous = now
    }
    func finish() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        let now = ContinuousClock.now
        var result = durations
        result[stage, default: 0] += Self.ms(previous.duration(to: now))
        result["total"] = Self.ms(start.duration(to: now))
        return result
    }
    private static func ms(_ duration: Duration) -> Int {
        max(0, min(600_000, Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)))
    }
}
