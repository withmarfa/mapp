import Foundation
import Marfa
import MarfaTelemetry
import os

/// What the app reports to WithMarfa, as a closed list of calls: each logs locally with the words it always used and
/// reports the same moment, so no call site decides on its own. Every name, sentence and operation is a
/// `StaticString`, and an attribute is a number, a flag or a fixed word, so nothing a person typed or a server
/// answered can reach a report. Whether anything leaves this Mac is `Reporting`'s decision.
nonisolated extension Telemetry {
    // MARK: Errors

    /// A refresh or a drain stopped on a failure the lane does not retry.
    static func syncStopped(_ error: MarfaError, during operation: StaticString, reporting: Reporting = .shared) {
        logger(.sync).error("sync stopped on a failure it does not retry")
        reporting.sink.report(error, during: operation)
    }

    /// A lane stopped on a failure the package does not name.
    static func syncStoppedUnnamed(during operation: StaticString, reporting: Reporting = .shared) {
        logger(.sync).error("sync stopped on a failure of a kind the package does not name")
        reporting.sink.report(
            type: "sync_failure_unnamed", sentence: "Sync stopped on a failure of a kind the app does not name.",
            during: operation)
    }

    /// The server's bin could not be read for a reason the lane does not retry.
    static func binUnreadable(_ error: MarfaError, reporting: Reporting = .shared) {
        logger(.sync).error("sync could not read the bin")
        reporting.sink.report(error, during: "bin")
    }

    /// A server's copy could not be opened or read. `error` is nil where the source failed with its own words.
    static func libraryNotOpened(_ error: MarfaError?, reporting: Reporting = .shared) {
        logger(.library).error("the library's copy could not be opened or read")
        if let error {
            reporting.sink.report(error, during: "open")
        } else {
            reporting.sink.report(
                type: "library_not_opened", sentence: "The library's copy could not be opened or read.", during: "open")
        }
    }

    /// The copy held rows it could not read.
    static func rowsUnreadable(count: Int, reporting: Reporting = .shared) {
        logger(.library).error("the copy held \(count, privacy: .public) rows it could not read")
        reporting.sink.report(
            type: "rows_unreadable", sentence: "The copy held rows it could not read.", during: "read")
    }

    /// The editor's web process ended; `wasReady` says whether the page had loaded first.
    static func editorProcessEnded(wasReady: Bool, reporting: Reporting = .shared) {
        if wasReady {
            logger(.editor).error("web content process ended; reloading")
        } else {
            logger(.editor).error("web content process ended before the editor was ready")
        }
        reporting.sink.report(
            type: "editor_process_ended", sentence: "The editor's web process ended.",
            during: wasReady ? "editor_running" : "editor_loading")
    }

    /// A quit that ran out of time, naming the stage it did not finish and nothing else.
    static func quitTimedOut(
        unfinished: [QuitTrace.Stage], limit: Duration, engineWaiting: Int?, reporting: Reporting = .shared
    ) {
        let stage: StaticString = switch unfinished.first {
        case .titles: "quit_titles"
        case .editors: "quit_editors"
        case .queue: "quit_queue"
        case nil: "quit_between_stages"
        }
        reporting.sink.report(
            type: "quit_timed_out", sentence: "The app did not finish saving before the time to quit ran out.",
            during: stage)
        reporting.sink.log(
            "quit_timed_out", level: .error,
            attributes: [
                "limit_ms": ReportAttribute(limit.inMilliseconds),
                "titles_unfinished": ReportAttribute(unfinished.contains(.titles)),
                "editors_unfinished": ReportAttribute(unfinished.contains(.editors)),
                "queue_unfinished": ReportAttribute(unfinished.contains(.queue)),
                "engine_events_waiting": ReportAttribute(engineWaiting ?? -1),
            ])
    }

    // MARK: Log events

    /// An event the engine took longer than `slow` over logs a notice, one longer than `stalled` an error, and the
    /// latter is also reported with its kind and duration.
    static func engineEventTook(_ kind: StaticString, _ elapsed: Duration, reporting: Reporting = .shared) {
        guard elapsed >= slow else { return }
        let log = logger(.engine)
        if elapsed >= stalled {
            log.error("engine event \(kind, privacy: .public) took \(elapsed.inMilliseconds, privacy: .public) ms")
            reporting.sink.log(
                "engine_event_slow", level: .warn,
                attributes: ["kind": ReportAttribute(stringLiteral: kind), "duration_ms": ReportAttribute(elapsed.inMilliseconds)])
        } else {
            log.notice("engine event \(kind, privacy: .public) took \(elapsed.inMilliseconds, privacy: .public) ms")
        }
    }

    /// Launch finished: one record for each milestone, with the time since the process began.
    static func launched(_ marks: [(milestone: LaunchTrace.Milestone, at: Duration, note: StaticString?)], reporting: Reporting = .shared) {
        for mark in marks {
            let milestone = ReportAttribute(stringLiteral: mark.milestone.word)
            let ms = ReportAttribute(mark.at.inMilliseconds)
            if let note = mark.note {
                reporting.sink.log(
                    "launch_milestone",
                    attributes: ["milestone": milestone, "since_process_start_ms": ms, "note": ReportAttribute(stringLiteral: note)])
            } else {
                reporting.sink.log("launch_milestone", attributes: ["milestone": milestone, "since_process_start_ms": ms])
            }
        }
    }

    /// MetricKit's daily summary: counts and the slowest bucket of each launch and hang metric.
    static func metricsSummarized(_ summary: MetricsListener.Summary, reporting: Reporting = .shared) {
        reporting.sink.log(
            "metrickit_report",
            attributes: [
                "interval_s": ReportAttribute(summary.intervalSeconds),
                "hang_samples": ReportAttribute(summary.hang.samples),
                "hang_slowest_ms": ReportAttribute(summary.hang.slowestMilliseconds),
                "first_draw_samples": ReportAttribute(summary.firstDraw.samples),
                "first_draw_slowest_ms": ReportAttribute(summary.firstDraw.slowestMilliseconds),
                "launch_samples": ReportAttribute(summary.launch.samples),
                "launch_slowest_ms": ReportAttribute(summary.launch.slowestMilliseconds),
            ])
    }

    /// A hang MetricKit measured.
    static func metricsHang(milliseconds: Int, intervalSeconds: Int, reporting: Reporting = .shared) {
        reporting.sink.log(
            "metrickit_hang", level: .warn,
            attributes: ["duration_ms": ReportAttribute(milliseconds), "interval_s": ReportAttribute(intervalSeconds)])
    }

    /// A slow launch MetricKit measured.
    static func metricsSlowLaunch(milliseconds: Int, intervalSeconds: Int, reporting: Reporting = .shared) {
        reporting.sink.log(
            "metrickit_slow_launch", level: .warn,
            attributes: ["duration_ms": ReportAttribute(milliseconds), "interval_s": ReportAttribute(intervalSeconds)])
    }
}
