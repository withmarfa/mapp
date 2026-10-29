import Foundation
import MetricKit
import os

/// Logs what the system measured of this app's launches and hangs, as MetricKit reports it, in `launch`. The system
/// delivers a report at most daily, for the use before, so it shows what people's Macs saw rather than this run.
/// Only counts, durations and the names of the app's own signposts are written: never a call stack.
nonisolated final class MetricsListener: Sendable {
    private let manager = MetricManager()
    private let tasks: [Task<Void, Never>]

    init() {
        let manager = manager
        tasks = [
            Task {
                for await report in manager.metricReports { Self.log(report) }
            },
            Task {
                for await report in manager.diagnosticReports { Self.log(report) }
            },
        ]
    }

    deinit {
        for task in tasks { task.cancel() }
    }

    private static let logger = Telemetry.logger(.launch)

    static func log(_ report: MetricReport) {
        let entries = report.stateEntries.flatMap(\.values) + report.intervalEntries.flatMap(\.values)
        let lines = entries.compactMap(summary)
        logger.notice("""
            MetricKit report for \(report.timeRange.duration.rounded(), privacy: .public) s: \
            \(lines.isEmpty ? "no launch or hang metrics" : lines.joined(separator: "; "), privacy: .public)
            """)
    }

    static func log(_ report: DiagnosticReport) {
        let interval = report.timeRange.duration.rounded()
        switch report.result {
        case .hang(let hang):
            let signposts = Set(report.environment.signpostData.map(\.name)).sorted().prefix(10)
            logger.error("""
                MetricKit hang of \(milliseconds(hang.hangDuration), privacy: .public) ms over \(interval, privacy: .public) s; \
                signposts then: \(signposts.joined(separator: ", "), privacy: .public)
                """)
        case .appLaunch(let launch):
            logger.notice("MetricKit slow launch of \(milliseconds(launch.launchDuration), privacy: .public) ms over \(interval, privacy: .public) s")
        case .crash:
            logger.error("MetricKit crash over \(interval, privacy: .public) s")
        case .cpuException:
            logger.error("MetricKit CPU exception over \(interval, privacy: .public) s")
        case .diskWriteException:
            logger.error("MetricKit disk write exception over \(interval, privacy: .public) s")
        @unknown default:
            logger.notice("MetricKit diagnostic of a kind this build does not know over \(interval, privacy: .public) s")
        }
    }

    private static func summary(_ result: MetricResult) -> String? {
        switch result {
        case .hangTime(let metric): "hang time: \(summary(metric.histogram))"
        case .timeToFirstDraw(let metric): "time to first draw: \(summary(metric.histogram))"
        case .optimizedTimeToFirstDraw(let metric): "optimized time to first draw: \(summary(metric.histogram))"
        case .extendedLaunch(let metric): "extended launch: \(summary(metric.histogram))"
        case .applicationResumeTime(let metric): "resume: \(summary(metric.histogram))"
        case .signpostInterval(let metric):
            "\(metric.signpostCategory)/\(metric.signpostName) x\(metric.totalCount): \(summary(metric.signpostDuration))"
        default: nil
        }
    }

    private static func summary(_ histogram: Histogram<UnitDuration>) -> String {
        let filled = histogram.buckets.filter { $0.count > 0 }
        guard let slowest = filled.max(by: { $0.upperBound < $1.upperBound }) else { return "no samples" }
        return "\(filled.reduce(0) { $0 + $1.count }) samples, slowest bucket up to \(milliseconds(slowest.upperBound)) ms"
    }

    private static func milliseconds(_ measurement: Measurement<UnitDuration>) -> Int {
        Int(measurement.converted(to: .milliseconds).value)
    }
}
