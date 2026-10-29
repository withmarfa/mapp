import Foundation
import os
import Synchronization

/// What one flush before a quit or a change of library has done: each stage's start and end, so a flush that runs
/// out of time can name the stage it did not finish, and every stage's duration is logged even when it succeeds.
/// Each line names the flush's purpose, since the same stages run for both.
nonisolated final class QuitTrace: Sendable {
    /// The window titles, the editors' flush (the pages handing over their last edit), and the library keeping
    /// its writes on this Mac (`ItemSource.queueSubmitted`).
    nonisolated enum Stage: String, CaseIterable, Sendable {
        case titles, editors, queue
    }

    nonisolated enum Purpose: Sendable {
        case quit, libraryChange

        var label: StaticString {
            switch self {
            case .quit: "quit"
            case .libraryChange: "library change"
            }
        }
    }

    nonisolated private struct Entry {
        var interval: Telemetry.Interval?
        var began: ContinuousClock.Instant?
        var spent = Duration.zero
        var finished = false
        var skipped = false
        var activity: EngineActivity?
    }

    private let stages = Mutex<[Stage: Entry]>([:])
    private let purpose: Purpose
    private let log = Telemetry.logger(.quit)

    init(purpose: Purpose) {
        self.purpose = purpose
    }

    /// Starts a stage. A stage that is begun again, as the titles are one window after another, adds to its time.
    /// `activity` is the engine of the library the stage waits on, nil where it is not the Marfa library, so
    /// nothing can be said of an engine.
    func begin(_ stage: Stage, activity: EngineActivity? = nil) {
        let interval = Telemetry.begin(.quit, stage.signpost)
        stages.withLock { entries in
            var entry = entries[stage] ?? Entry()
            entry.interval = interval
            entry.began = .now
            entry.finished = false
            entry.activity = activity
            entries[stage] = entry
        }
    }

    func end(_ stage: Stage) {
        let (interval, spent) = stages.withLock { entries -> (Telemetry.Interval?, Duration) in
            var entry = entries[stage] ?? Entry()
            if let began = entry.began { entry.spent += ContinuousClock.now - began }
            entry.finished = true
            let interval = entry.interval
            entry.interval = nil
            entry.began = nil
            entries[stage] = entry
            return (interval, entry.spent)
        }
        interval?.end()
        log.info("\(self.purpose.label) stage \(stage.rawValue, privacy: .public) finished in \(spent.inMilliseconds, privacy: .public) ms")
    }

    /// A stage with nothing to do, as the queue's when the library has closed since the flush began.
    func skip(_ stage: Stage, because reason: StaticString) {
        stages.withLock { $0[stage, default: Entry()].skipped = true }
        log.info("\(self.purpose.label) stage \(stage.rawValue, privacy: .public) skipped: \(reason.description, privacy: .public)")
    }

    /// The stages begun and not finished, in the order a flush runs them.
    var unfinished: [Stage] {
        stages.withLock { entries in
            Stage.allCases.filter { stage in
                guard let entry = entries[stage] else { return false }
                return entry.began != nil && !entry.finished
            }
        }
    }

    /// Names the stage a flush that ran out of time did not finish, and for the queue what the engine was doing:
    /// kinds, durations and counts only. A flush that never began a stage, or that has finished them all and is
    /// held up between them, says so.
    func diagnosis(at now: ContinuousClock.Instant = .now) -> String {
        let stalled = unfinished
        let activities = stages.withLock { $0.mapValues(\.activity) }
        guard !stalled.isEmpty else {
            return "no stage is unfinished; the flush stopped between stages"
        }
        return stalled.map { stage in
            switch stage {
            case .queue:
                let engine = activities[.queue].flatMap { $0 }?.snapshot(at: now).summary ?? "engine unknown"
                return "queue did not finish (\(engine))"
            case .editors: return "editors did not finish handing over their last edit"
            case .titles: return "window titles did not finish saving"
            }
        }.joined(separator: "; ")
    }

    /// Logs the diagnosis of a flush that ran out of time.
    func logTimeout(after limit: Duration) {
        let text = diagnosis()
        log.error("quit timed out after \(limit.inMilliseconds, privacy: .public) ms: \(text, privacy: .public)")
    }
}

private extension QuitTrace.Stage {
    nonisolated var signpost: StaticString {
        switch self {
        case .titles: "stage.titles"
        case .editors: "stage.editors"
        case .queue: "stage.queue"
        }
    }
}
