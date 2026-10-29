import Foundation
import Synchronization

/// What the engine is doing, readable from anywhere without awaiting the engine: the kind of event it is in and
/// since when, and how many events were told and not yet taken. A quit that times out reads this to name the step
/// it is stuck behind, which the engine's own actor could not answer while it is busy. It also counts the person's
/// writes told and taken, so a quit waits for those alone and not for what was told after them.
nonisolated final class EngineActivity: Sendable {
    nonisolated struct Snapshot: Sendable, Equatable {
        /// The kind of the event being taken; nil when the engine is between events.
        var step: String?
        var elapsed: Duration?
        /// Events told and not yet taken, the one being taken not among them.
        var waiting: Int
        /// Writes told and not yet taken, the one being taken among them.
        var writes: Int = 0

        /// For logs: kinds, durations and counts only.
        var summary: String {
            let waiting = "\(waiting) waiting, \(writes) writes not taken"
            guard let step, let elapsed else { return "engine idle, \(waiting)" }
            return "engine busy with \(step) for \(elapsed.inMilliseconds) ms, \(waiting)"
        }
    }

    nonisolated private struct State {
        var step: (kind: StaticString, began: ContinuousClock.Instant)?
        var told = 0
        var taken = 0
        var writesTold = 0
        var writesTaken = 0
        /// Each waits until the writes taken reach the count told when it began waiting.
        var waiters: [(mark: Int, done: CheckedContinuation<Void, Never>)] = []
        /// Set once the engine takes nothing more, after which no one waits.
        var finished = false

        /// Takes out the waiters whose writes are all taken. A write told and then refused lowers the count told,
        /// so a mark above it is met once the writes taken reach the count told.
        mutating func ready() -> [CheckedContinuation<Void, Never>] {
            let met = waiters.filter { writesTaken >= min($0.mark, writesTold) }
            waiters.removeAll { writesTaken >= min($0.mark, writesTold) }
            return met.map(\.done)
        }
    }

    private let state = Mutex(State())

    /// An event is on its way to the engine; `write` where it is a write of the person's.
    func tell(write: Bool = false) {
        state.withLock {
            $0.told += 1
            if write { $0.writesTold += 1 }
        }
    }

    /// The event was refused, as the engine's stream had ended.
    func untell(write: Bool = false) {
        let ready = state.withLock { state in
            state.told -= 1
            if write { state.writesTold -= 1 }
            return state.ready()
        }
        for done in ready { done.resume() }
    }

    /// The engine has taken one of the person's writes: it is in the copy's queue, or answered.
    func tookWrite() {
        let ready = state.withLock { state in
            state.writesTaken += 1
            return state.ready()
        }
        for done in ready { done.resume() }
    }

    /// Returns once every write told before the call is taken, at once where none waits or the engine has ended.
    func writesTaken() async {
        await withCheckedContinuation { continuation in
            let waits = state.withLock { state in
                guard !state.finished, state.writesTaken < state.writesTold else { return false }
                state.waiters.append((state.writesTold, continuation))
                return true
            }
            if !waits { continuation.resume() }
        }
    }

    /// The engine takes nothing more, so no write still told will be taken.
    func finish() {
        let waiting = state.withLock { state in
            state.finished = true
            defer { state.waiters = [] }
            return state.waiters.map(\.done)
        }
        for done in waiting { done.resume() }
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
                waiting: max(0, state.told - state.taken),
                writes: max(0, state.writesTold - state.writesTaken))
        }
    }
}
