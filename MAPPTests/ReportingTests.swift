import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// Whether a run reports, and what a quit that ran out of time says, without a network or the person's defaults.
struct ReportingTests {
    private static let info: [String: Any] = [
        Reporting.hostKey: "https://reports.example.com", Reporting.tokenKey: "phc_abc123",
    ]

    private func defaults(switchOn: Bool? = nil) -> UserDefaults {
        let suite = "MAPP.ReportingTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        if let switchOn { defaults.set(switchOn, forKey: Reporting.switchKey) }
        return defaults
    }

    private func gate(
        info: [String: Any]? = ReportingTests.info, arguments: [String] = [], environment: [String: String] = [:],
        switchOn: Bool? = nil, isTestHost: Bool = false
    ) -> Reporting.Gate {
        .current(info: info, arguments: arguments, environment: environment, defaults: defaults(switchOn: switchOn), isTestHost: isTestHost)
    }

    @Test func aBuildWithADestinationAndTheSwitchLeftOnSends() {
        #expect(gate().sends)
    }

    @Test func aBuildWithoutADestinationNeverSends() {
        #expect(!gate(info: [:]).sends)
        #expect(!gate(info: [Reporting.hostKey: "", Reporting.tokenKey: ""]).sends)
        // An unset build setting reaches the plist as its own name.
        #expect(!gate(info: [Reporting.hostKey: "$(MARFA_POSTHOG_HOST)", Reporting.tokenKey: "$(MARFA_POSTHOG_PROJECT_TOKEN)"]).sends)
        #expect(!gate(info: [Reporting.hostKey: "http://reports.example.com", Reporting.tokenKey: "phc_abc123"]).sends)
        #expect(!gate(info: [Reporting.hostKey: "https://reports.example.com", Reporting.tokenKey: "phc abc"]).sends)
    }

    @Test func theUnitTestHostPreviewsAndTheSampleLibraryNeverSend() {
        #expect(!gate(isTestHost: true).sends)
        #expect(!gate(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]).sends)
        #expect(!gate(arguments: [SampleLibrary.flag]).sends)
        #expect(!gate(arguments: [SampleLibrary.flag, "-MAPPSampleUnconfigured"]).sends)
    }

    @Test func theIsolatedHostNeverSendsEvenOnATestServer() {
        let server = ["MAPP_TEST_MARFA_URL": "https://test.example.com", "MAPP_TEST_MARFA_KEY": "key"]
        #expect(!gate(arguments: [SampleLibrary.flag], environment: server).sends)
    }

    @Test func theSwitchOffStopsSendingAndTheDefaultIsOn() {
        #expect(!gate(switchOn: false).sends)
        #expect(gate(switchOn: true).sends)
        #expect(Reporting.switchIsOn(in: defaults()))
    }

    /// A run that starts with the switch off is still configured, so turning the switch on needs no relaunch.
    @Test func theSwitchDoesNotDecideWhetherARunMayReport() {
        #expect(gate(switchOn: false).mayReport)
        #expect(!gate(switchOn: false, isTestHost: true).mayReport)
        #expect(!gate(info: [:], switchOn: true).mayReport)
    }

    @Test func aQuitThatTimedOutReportsOnlyTheFixedTypeSentenceAndStage() {
        let activity = EngineActivity()
        activity.tell()
        activity.begin("change.server")
        let trace = QuitTrace(purpose: .quit)
        trace.begin(.editors)
        trace.end(.editors)
        trace.begin(.queue, activity: activity)
        let sink = RecordingSink()

        trace.logTimeout(after: .seconds(5), reporting: Reporting(sink: sink))

        #expect(sink.errors == [
            .init(type: "quit_timed_out", sentence: "The app did not finish saving before the time to quit ran out.", operation: "quit_queue")
        ])
        #expect(sink.logs == ["quit_timed_out"])
    }

    @Test func aQuitStuckBetweenStagesNamesNoStage() {
        let sink = RecordingSink()
        QuitTrace(purpose: .quit).logTimeout(after: .seconds(5), reporting: Reporting(sink: sink))

        #expect(sink.errors.map(\.operation) == ["quit_between_stages"])
    }

    @Test func anUnreadableTimestampSortsAsTheOldestAndIsReportedOnceARun() {
        let sink = RecordingSink()
        let reporting = Reporting(sink: sink)

        #expect(MarfaMapping.date("2026-10-06T09:00:00Z", reporting: reporting) > .distantPast)
        #expect(sink.errors.isEmpty)
        #expect(MarfaMapping.date("not a time", reporting: reporting) == .distantPast)
        #expect(MarfaMapping.date("", reporting: reporting) == .distantPast)

        #expect(sink.errors == [
            .init(type: "timestamp_unreadable", sentence: "A timestamp could not be read, so its item sorts as the oldest.", operation: "map")
        ])
    }

    @Test func unreadConflictLinksAreReportedOnceARun() {
        let sink = RecordingSink()
        let reporting = Reporting(sink: sink)

        Telemetry.conflictLinksUnread(count: 2, reporting: reporting)
        Telemetry.conflictLinksUnread(count: 3, reporting: reporting)

        #expect(sink.errors.map(\.type) == ["conflict_links_unread"])
    }
}
