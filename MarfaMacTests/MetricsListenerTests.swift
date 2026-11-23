import Foundation
import MetricKit
import Testing
@testable import MarfaMac

/// A decoded daily report. MetricKit's types can only be decoded, and the full-day interval is the one sent: a
/// shorter interval is already inside it.
struct MetricsListenerTests {
    @Test func aDailyReportThatCarriesCPUTimeSendsItWithTheHangs() throws {
        let summary = MetricsListener.summary(of: try report(carriesCPUTime: true))
        #expect(summary.cpuTimeMilliseconds == 1500)
        #expect(summary.hang.samples == 4)
        #expect(summary.hang.slowestMilliseconds == 250)

        let sent = try sentAttributes(of: summary)
        #expect(sent["cpu_time_ms"] == reportAttribute(1500))
        #expect(sent["hang_samples"] == reportAttribute(4))
        #expect(sent["hang_slowest_ms"] == reportAttribute(250))
        #expect(sent["first_draw_samples"] == reportAttribute(0))
        #expect(sent["launch_samples"] == reportAttribute(0))
        #expect(sent["peak_memory_bytes"] == nil)
    }

    @Test func aDailyReportWithoutCPUTimeSendsTheHangsAlone() throws {
        let summary = MetricsListener.summary(of: try report(carriesCPUTime: false))
        #expect(summary.cpuTimeMilliseconds == nil)
        #expect(summary.hang.samples == 2)

        let sent = try sentAttributes(of: summary)
        #expect(sent["hang_samples"] == reportAttribute(2))
        #expect(sent["hang_slowest_ms"] == reportAttribute(100))
        #expect(sent["cpu_time_ms"] == nil)
        #expect(sent["peak_memory_bytes"] == nil)
    }

    private func sentAttributes(of summary: MetricsListener.Summary) throws -> [String: ReportAttribute] {
        let sink = RecordingSink()
        Telemetry.metricsSummarized(summary, reporting: Reporting(sink: sink))
        #expect(sink.logs == ["metrickit_report"])
        return try #require(sink.attributes["metrickit_report"])
    }

    /// Two intervals when CPU time is carried: an hour at 10 seconds, then the full day at 1500 milliseconds. The
    /// hour is there so a sum would be caught. The report without CPU time is the full day and its hangs only.
    private func report(carriesCPUTime: Bool) throws -> MetricReport {
        let cpu = carriesCPUTime ? #",{"cpuTimeMetric":{"value":{"value":1500,"unit":"ms"}}}"# : ""
        let hour = carriesCPUTime
            ? #"{"states":[],"duration":{"value":3600,"unit":"s"},"values":[{"cpuTimeMetric":{"value":{"value":10,"unit":"s"}}}]},"#
            : ""
        let samples = carriesCPUTime ? 4 : 2
        let slowest = carriesCPUTime ? 250 : 100
        let json = """
        {"timeRange":{"begin":0,"end":86400},"stateEntries":[],"intervalEntries":[
          \(hour)
          {"states":[],"duration":{"value":86400,"unit":"s"},"values":[
            {"hangTimeMetric":{"histogram":{"buckets":[
              {"lowerBound":{"value":0,"unit":"ms"},"upperBound":{"value":\(slowest),"unit":"ms"},"count":\(samples)}
            ]}}}
            \(cpu)
          ]}
        ]}
        """
        return try JSONDecoder().decode(MetricReport.self, from: Data(json.utf8))
    }
}
