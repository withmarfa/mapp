import Foundation
import Marfa
import MarfaTelemetry

/// The SDK's reporter and what it takes, named here because the app's own `Telemetry` hides the SDK's type of that
/// name. Only the files in `MAPP/Model/Telemetry/` import `MarfaTelemetry`.
typealias SDKReporter = MarfaTelemetry.Telemetry
typealias ReportLevel = MarfaTelemetry.Telemetry.LogLevel
typealias ReportAttribute = MarfaTelemetry.Telemetry.LogAttribute

/// What the app hands to the SDK. A test gives its own, so no test reaches the network.
nonisolated protocol ReportSink: Sendable {
    func report(_ error: MarfaError, during operation: StaticString)
    func report(type: StaticString, sentence: StaticString, during operation: StaticString)
    func log(_ name: StaticString, level: ReportLevel, attributes: KeyValuePairs<StaticString, ReportAttribute>)
}

nonisolated extension SDKReporter: ReportSink {}

nonisolated extension ReportSink {
    func log(_ name: StaticString, attributes: KeyValuePairs<StaticString, ReportAttribute> = [:]) {
        log(name, level: .info, attributes: attributes)
    }
}

/// Whether this run reports errors and timings to WithMarfa, and where to. The SDK is told nothing, and so sends
/// nothing, unless every condition in `Gate` holds. What is reported is `Telemetry`'s closed list of calls; this
/// type only decides whether the SDK is on.
nonisolated final class Reporting: Sendable {
    static let shared = Reporting(sink: SDKReporter.shared)

    /// The `Info.plist` keys (build settings of the same names) a build carries its destination in. Both are empty in
    /// the repository, so a build from the public source sends nothing.
    static let hostKey = "MARFA_POSTHOG_HOST"
    static let tokenKey = "MARFA_POSTHOG_PROJECT_TOKEN"
    /// The Settings switch, in the defaults. On until the person turns it off.
    static let switchKey = "sendErrorReports"

    let sink: any ReportSink

    init(sink: any ReportSink) {
        self.sink = sink
    }

    /// Where reports go, from a bundle's `Info.plist`; nil when the build carries none, or carries one the SDK
    /// refuses (a host that is not `https`, or a token with white space).
    static func destination(in info: [String: Any]?) -> SDKReporter.Destination? {
        guard let host = (info?[hostKey] as? String)?.trimmingCharacters(in: .whitespaces), !host.isEmpty,
            let url = URL(string: host),
            let token = (info?[tokenKey] as? String)?.trimmingCharacters(in: .whitespaces), !token.isEmpty
        else { return nil }
        return try? SDKReporter.Destination(host: url, projectToken: token)
    }

    /// Whether this build carries a destination, which is when Settings offers the switch.
    static let carriesDestination = destination(in: Bundle.main.infoDictionary) != nil

    /// The conditions for sending, each of which must hold.
    nonisolated struct Gate: Equatable, Sendable {
        var carriesDestination: Bool
        /// The unit tests' host, UI tests' sample library, previews and the sample library never report.
        var isTestHost: Bool
        var isPreview: Bool
        var usesSampleLibrary: Bool
        var switchIsOn: Bool

        var sends: Bool {
            carriesDestination && !isTestHost && !isPreview && !usesSampleLibrary && switchIsOn
        }

        /// The sample library stands for a library, so it does not report; run against a test server by hand
        /// (`MAPP_TEST_MARFA_URL` and `MAPP_TEST_MARFA_KEY`), the isolated app has a real one and does.
        static func current(
            info: [String: Any]? = Bundle.main.infoDictionary,
            arguments: [String] = ProcessInfo.processInfo.arguments,
            environment: [String: String] = ProcessInfo.processInfo.environment,
            defaults: UserDefaults = .standard,
            isTestHost: Bool
        ) -> Gate {
            let sampled = arguments.contains(SampleLibrary.flag) && !arguments.contains("-MAPPSampleUnconfigured")
            let hasTestServer = ["MAPP_TEST_MARFA_URL", "MAPP_TEST_MARFA_KEY"].allSatisfy { !(environment[$0] ?? "").isEmpty }
            return Gate(
                carriesDestination: destination(in: info) != nil,
                isTestHost: isTestHost,
                isPreview: environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1",
                usesSampleLibrary: arguments.contains(SampleLibrary.flag) && !(sampled && hasTestServer),
                switchIsOn: Reporting.switchIsOn(in: defaults))
        }
    }

    static func switchIsOn(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: switchKey) as? Bool ?? true
    }

    /// Configures and turns on the SDK if this run may report. Called once, at launch.
    func start(isTestHost: Bool) {
        let info = Bundle.main.infoDictionary
        guard Gate.current(info: info, isTestHost: isTestHost).sends, let destination = Self.destination(in: info)
        else { return }
        SDKReporter.shared.configure(
            SDKReporter.Configuration(destination: destination, serviceName: "mapp", serviceVersion: Self.version(info)))
        SDKReporter.shared.isEnabled = true
    }

    /// The Settings switch changed: off stops reporting at once and drops what waits.
    func switchChanged(to isOn: Bool) {
        guard Self.carriesDestination else { return }
        SDKReporter.shared.isEnabled = isOn && Gate.current(isTestHost: Self.isTestHost).sends
    }

    private static var isTestHost: Bool {
        #if DEBUG
        TestHost.isRequested
        #else
        false
        #endif
    }

    /// The version and build, as About gives them.
    static func version(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return "\(version) (\(build))"
    }

    /// Sends what waits, up to the SDK's short deadline, as the app quits. It returns at once when nothing waits or
    /// reporting is off.
    func flush() async {
        await SDKReporter.shared.flush()
    }
}
