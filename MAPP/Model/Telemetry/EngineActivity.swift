import Foundation
import Synchronization

/// What the engine is doing, readable from anywhere without awaiting the engine: the kind of event it is in and
/// since when, and how many events were told and not yet taken. A quit that times out reads this to name the step
/// it is stuck behind, which the engine's own actor could not answer while it is busy.
nonisolated final class EngineActivity: Sendable {
    nonisolated struct Snapshot: Sendable, Equatable {
        /// The kind of the event being taken; nil when the engine is between events.
        var step: String?
        var elapsed: Duration?
        /// Events told and not yet taken, the one being taken not among them.
        var waiting: Int

        /// For logs: kinds, durations and counts only.
        var summary: String {
            let waiting = "\(waiting) waiting"
            guard let step, let elapsed else { return "engine idle, \(waiting)" }
            return "engine busy with \(step) for \(elapsed.inMilliseconds) ms, \(waiting)"
        }
    }

    nonisolated private struct State {
        var step: (kind: StaticString, began: ContinuousClock.Instant)?
        var told = 0
        var taken = 0
    }

    private let state = Mutex(State())

    /// An event is on its way to the engine.
    func tell() {
        state.withLock { $0.told += 1 }
    }

    /// The event was refused, as the engine's stream had ended.
    func untell() {
        state.withLock { $0.told -= 1 }
    }

    /// The engine took an event off its stream and is working on it.
    func begin(_ kind: StaticString, at now: ContinuousClock.Instant = .now) {
        state.withLock {
            $0.taken += 1
            $0.step = (kind, now)
        }
    }

    func end() {
        state.withLock { $0.step = nil }
    }

    func snapshot(at now: ContinuousClock.Instant = .now) -> Snapshot {
        state.withLock { state in
            Snapshot(
                step: state.step.map { "\($0.kind)" },
                elapsed: state.step.map { now - $0.began },
                waiting: max(0, state.told - state.taken))
        }
    }
}
