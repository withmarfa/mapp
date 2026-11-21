import Marfa
import SwiftUI
import Synchronization
import Testing
@testable import MAPP

/// Draws Activity, Monitoring, Limits and Start-Up from a scripted server, for a pull request's pictures. Skipped unless
/// `MAPP_SETTINGS_RENDERS` names a folder.
extension SettingsRenderTests {
    private func instanceHost(_ configure: (FakeInstanceCalls) -> Void = { _ in }) async -> StubMarfaHost {
        let source = FakeInstanceConfig([.name: .text("Castell Studio"), .trashRetentionDays: .number(60)])
        let settings = InstanceSettingsModel { .init(id: "https://marfa.castell.studio", source: source) }
        await settings.load()
        let host = StubMarfaHost(settings: settings)
        let calls = FakeInstanceCalls()
        configure(calls)
        host.instanceCalls = calls
        return host
    }

    private func context(_ host: StubMarfaHost) -> OwnerContext {
        OwnerContext(calls: host.ownerCalls, grants: { host.grants })
    }

    private func draw(_ page: MarfaSettingsPage, _ detail: some View, sheet: AnyView? = nil, named: String) async throws {
        try await SettingsRender.png(
            RenderedWindow(selection: .marfa(page), sheet: sheet, detail: detail), size: Self.size, named: named, settle: .milliseconds(900))
    }

    // MARK: Activity

    private static func log() -> [ActivityEntry] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        func at(_ day: Int, _ hour: Int, _ minute: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -day, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        let rows: [(Date, String?, String, String?)] = [
            (at(0, 4, 22), "MAPP on MacBook Pro", "type.replace", "81.2.69.160"),
            (at(0, 4, 0), "Marfa", "backup_folder.adopt", nil),
            (at(0, 3, 41), "Raycast", "auth.scopes.narrowed", "81.2.69.160"),
            (at(0, 2, 5), "Backup script", "key.update", "100.84.12.7"),
            (at(0, 1, 40), "MAPP on MacBook Pro", "webhook.create", "81.2.69.160"),
            (at(0, 1, 12), "Lisbon zine importer", "items.bulk", "100.84.12.7"),
            (at(0, 0, 30), "Mira Castell", "auth.sign_in.success", "81.2.69.160"),
            (at(1, 18, 20), "Mira Castell", "owner.password.changed", "81.2.69.160"),
            (at(1, 9, 0), "Marfa", "items.trash_purged", nil),
            (at(1, 8, 0), "Raycast", "auth.grant.created", "81.2.69.160"),
            (at(3, 14, 0), "Marfa", "instance.update.started", nil),
            (at(4, 17, 0), "GitHub connector", "connector.register", "100.84.12.7"),
            (at(5, 11, 0), "MAPP on MacBook Pro", "key.create", "81.2.69.160"),
            (at(6, 3, 0), "Marfa", "backup_folder.adopt", nil),
        ]
        return rows.enumerated().map { index, row in
            ActivityEntry(id: "e\(index)", date: row.0, who: row.1, action: row.2, resourceType: "x", resourceID: nil, address: row.3)
        }
    }

    @Test func activity() async throws {
        let host = await instanceHost { $0.state.withLock { $0.entries = Self.log() } }
        try await draw(.activity, MarfaSettingsPageView(page: .activity, host: host), named: "Activity")
    }

    @Test func activityWithNothingInIt() async throws {
        let host = await instanceHost()
        try await draw(.activity, MarfaSettingsPageView(page: .activity, host: host), named: "Activity, empty")
    }

    @Test func activityFilteredToNothing() async throws {
        let host = await instanceHost { $0.state.withLock { $0.entries = Self.log() } }
        let model = ActivityModel(context: context(host), calls: host.instanceCalls)
        model.search = "no such thing"
        try await draw(.activity, ActivityPage(host: host, model: model), named: "Activity, nothing matches")
    }

    @Test func activityNeedsAPermission() async throws {
        let host = await instanceHost()
        host.grants = [.configManage]
        try await draw(.activity, MarfaSettingsPageView(page: .activity, host: host), named: "Activity, without audit.read")
    }

    // MARK: Monitoring

    private func monitored(_ configure: (inout [String: StoredSetting]) -> Void = { _ in }) async -> StubMarfaHost {
        await instanceHost { calls in
            calls.state.withLock { state in
                state.settings["heartbeat_url"]?.isSet = true
                state.settings["posthog_host"]?.isSet = true
                state.settings["error_reporting_enabled"]?.value = .bool(false)
                configure(&state.settings)
            }
        }
    }

    @Test func monitoring() async throws {
        let host = await monitored()
        try await draw(.monitoring, MarfaSettingsPageView(page: .monitoring, host: host), named: "Monitoring")
    }

    @Test func monitoringSettingASecret() async throws {
        let host = await monitored()
        let model = MonitoringModel(context: context(host), calls: host.instanceCalls)
        await model.load()
        model.begin(.postHogToken)
        model.sheet?.inputs["posthog_project_token"] = "phc_not_shown_anywhere"
        try await draw(.monitoring, MonitoringPage(host: host, model: model), named: "Monitoring, setting the project token")
    }

    @Test func monitoringASecretTheServerRefused() async throws {
        let host = await monitored()
        let calls = host.instanceCalls as? FakeInstanceCalls
        calls?.state.withLock { $0.refusal = "Use a public address; allow_private_addresses is off." }
        let model = MonitoringModel(context: context(host), calls: host.instanceCalls)
        await model.load()
        model.begin(.heartbeatAddress)
        model.sheet?.inputs["heartbeat_url"] = "http://10.0.0.1/ping"
        await model.save()
        try await draw(.monitoring, MonitoringPage(host: host, model: model), named: "Monitoring, an address refused")
    }

    // MARK: Limits

    @Test func limits() async throws {
        let host = await instanceHost()
        try await draw(.limits, MarfaSettingsPageView(page: .limits, host: host), named: "Limits")
    }

    @Test func limitsScrolledDown() async throws {
        let host = await instanceHost()
        try await SettingsRender.png(
            RenderedWindow(selection: .marfa(.limits), detail: MarfaSettingsPageView(page: .limits, host: host)),
            size: CGSize(width: Self.size.width, height: 1_240), named: "Limits, the whole page", settle: .milliseconds(900))
    }

    @Test func limitsAValueOutOfRange() async throws {
        let host = await instanceHost()
        let model = LimitsModel(context: context(host), calls: host.instanceCalls)
        await model.load()
        model.drafts["max_bulk_request_bytes"] = "64"
        model.drafts["enrichment_max_attempts"] = "500"
        try await draw(.limits, LimitsPage(host: host, model: model), named: "Limits, a value out of range")
    }

    @Test func limitsAChangeTheServerRefused() async throws {
        let host = await instanceHost()
        (host.instanceCalls as? FakeInstanceCalls)?.state.withLock { $0.refusal = "`max_request_bytes` must not exceed the bulk limit." }
        let model = LimitsModel(context: context(host), calls: host.instanceCalls)
        await model.load()
        model.drafts["max_request_bytes"] = "20"
        await model.commit(.largestRequest)
        try await draw(.limits, LimitsPage(host: host, model: model), named: "Limits, a change the server refused")
    }

    @Test func limitsChangedElsewhere() async throws {
        let host = await instanceHost()
        let calls = host.instanceCalls as? FakeInstanceCalls
        let model = LimitsModel(context: context(host), calls: host.instanceCalls)
        await model.load()
        calls?.changeElsewhere("enrichment_max_attempts", to: .int(7))
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        try await draw(.limits, LimitsPage(host: host, model: model), named: "Limits, changed somewhere else")
    }

    @Test func limitsNeedAPermission() async throws {
        let host = await instanceHost()
        host.grants = [.auditRead]
        try await draw(.limits, MarfaSettingsPageView(page: .limits, host: host), named: "Limits, without config.manage")
    }

    @Test func limitsWhenTheServerIsNotAnswering() async throws {
        let host = await instanceHost()
        host.connection = .notAnswering(lastAnswered: .now.addingTimeInterval(-600))
        try await draw(.limits, MarfaSettingsPageView(page: .limits, host: host), named: "Limits, Castell Studio not answering")
    }

    // MARK: Start-Up

    @Test func startUp() async throws {
        let host = await instanceHost { calls in
            calls.state.withLock { state in
                state.startUp = [
                    ("MARFA_PORT", true), ("MARFA_LISTEN_HOST", true), ("MARFA_DATABASE_PATH", true), ("MARFA_BLOB_PATH", true),
                    ("MARFA_TRUSTED_PROXY_CIDRS", false), ("MARFA_MAX_CONNECTIONS", false), ("MARFA_CONTROL_SOCKET", true),
                    ("MARFA_AUTH_SECRET", true),
                ].map { StartUpSetting(name: $0.0, isSecret: $0.0 == "MARFA_AUTH_SECRET", isSet: $0.1) }
            }
        }
        try await draw(.startUp, MarfaSettingsPageView(page: .startUp, host: host), named: "Start-Up")
    }
}
