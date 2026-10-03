import Dispatch
import Foundation
import Synchronization

/// Absolute deadlines on the monotonic clock. Every network step in this package takes one, so
/// DNS, TLS and slow trickles all count against the same budget.
public typealias Deadline = ContinuousClock.Instant

extension ContinuousClock.Instant {
    /// Seconds left until this instant; 0 when it has passed.
    var secondsRemaining: Double {
        let left = self - ContinuousClock.now
        guard left > .zero else { return 0 }
        let c = left.components
        return Double(c.seconds) + Double(c.attoseconds) / 1e18
    }

    var hasPassed: Bool { ContinuousClock.now >= self }

    /// The same instant as a `DispatchTime`, for timers on dispatch queues.
    var dispatchTime: DispatchTime {
        .now() + .nanoseconds(Int(min(secondsRemaining, 3600) * 1_000_000_000))
    }

    static func earliest(_ a: Self, _ b: Self) -> Self { a < b ? a : b }
}

/// A continuation that is resumed exactly once, whoever gets there first (result, timer or
/// cancellation). A value delivered before the continuation is installed is kept and delivered
/// on installation.
final class OneShot<Value: Sendable>: Sendable {
    private enum State {
        case idle
        case waiting(CheckedContinuation<Value, Never>)
        case resolved(Value)
        case done
    }

    private let state = Mutex<State>(.idle)

    func install(_ continuation: CheckedContinuation<Value, Never>) {
        let early: Value? = state.withLock { s in
            switch s {
            case .idle:
                s = .waiting(continuation)
                return nil
            case .resolved(let v):
                s = .done
                return v
            case .waiting, .done:
                preconditionFailure("OneShot installed twice")
            }
        }
        if let early { continuation.resume(returning: early) }
    }

    /// Delivers `value` unless something was delivered already. Returns whether it won.
    @discardableResult
    func resume(_ value: Value) -> Bool {
        let continuation: CheckedContinuation<Value, Never>?
        let won: Bool
        (continuation, won) = state.withLock { s in
            switch s {
            case .idle:
                s = .resolved(value)
                return (nil, true)
            case .waiting(let c):
                s = .done
                return (c, true)
            case .resolved, .done:
                return (nil, false)
            }
        }
        continuation?.resume(returning: value)
        return won
    }
}

/// Waits for a shared task's value until `deadline` or until the waiting task is cancelled,
/// whichever comes first, and returns `fallback` then. The shared task is not cancelled: other
/// callers may still be waiting for it. (Awaiting `task.value` directly ignores both.)
func waitForValue<T: Sendable>(of task: Task<T, Never>, until deadline: Deadline, fallback: T) async -> T {
    if deadline.hasPassed || Task.isCancelled { return fallback }
    let once = OneShot<T>()
    return await withTaskCancellationHandler {
        await withCheckedContinuation { continuation in
            once.install(continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: deadline.dispatchTime) { once.resume(fallback) }
            Task { once.resume(await task.value) }
        }
    } onCancel: {
        once.resume(fallback)
    }
}

/// Runs `operation` and returns `fallback` if it hasn't finished by `deadline`; the operation is
/// cancelled then. The operation must honour cancellation promptly (the group waits for it).
func withDeadline<T: Sendable>(_ deadline: Deadline, fallback: T,
                               _ operation: @escaping @Sendable () async -> T) async -> T {
    if deadline.hasPassed { return fallback }
    return await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(until: deadline, clock: .continuous)
            return nil
        }
        let first = await group.next() ?? nil
        group.cancelAll()
        return first ?? fallback
    }
}
