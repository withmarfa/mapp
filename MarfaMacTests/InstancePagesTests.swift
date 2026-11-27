import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// Holds `itemStats` so a test can change the period while a read is in flight.
private nonisolated final class StatsPause: @unchecked Sendable {
    private let lock = NSLock()
    private var holding = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var waitingCount = 0

    var isHolding: Bool {
        lock.lock()
        defer { lock.unlock() }
        return holding
    }

    var waiting: Int {
        lock.lock()
        defer { lock.unlock() }
        return waitingCount
    }

    func hold() {
        lock.lock()
        holding = true
        lock.unlock()
    }

    /// Later calls are not held. Calls already waiting stay waiting.
    func admit() {
        lock.lock()
        holding = false
        lock.unlock()
    }

    func park() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if holding {
                waitingCount += 1
                waiters.append(continuation)
                lock.unlock()
            } else {
                lock.unlock()
                continuation.resume()
            }
        }
    }

    func release() {
        lock.lock()
        holding = false
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

/// What Activity, Monitoring, Limits and Start-Up ask of the server, held in memory: it answers as the server does, keeps what it
/// was sent and fails a named call on request.
nonisolated final class FakeInstanceCalls: InstanceCalls {
    struct State {
        var instanceID = "instance-1"
        var settings: [String: StoredSetting] = FakeInstanceCalls.defaults
        var startUp: [StartUpSetting] = [
            StartUpSetting(name: "MARFA_PORT", isSecret: false, isSet: true),
            StartUpSetting(name: "MARFA_MAX_CONNECTIONS", isSecret: false, isSet: false),
            StartUpSetting(name: "MARFA_AUTH_SECRET", isSecret: true, isSet: true),
        ]
        var entries: [ActivityEntry] = []
        var failures: [String: OwnerFailure] = [:]
        var calls: [String] = []
        var sent: [[String: StoredSettingChange]] = []
        var instanceIDsSent: [String?] = []
        var queries: [ActivityQuery] = []
        var metrics = UsageMetrics(versionCount: 0, fileBytes: 0, databaseBytes: 0)
        var allTimeType: [String: Int] = [:]
        var allTimeSource: [String: Int] = [:]
        var periodType: [String: Int] = [:]
        var periodSource: [String: Int] = [:]
        var dayType: [String: Int] = [:]
        var daySource: [String: Int] = [:]
        var statQueries: [UsageStatsQuery] = []
        /// A day-sized stats read fails, and the wider reads still answer.
        var failDayStats = false
        /// A refusal the server gives a write, in its words, instead of taking it.
        var refusal: String?
        /// How long a write takes, so a second write can arrive while it runs.
        var changeDelay: Duration?
        /// Whether every read fails once a write has been taken.
        var failReadsAfterChange = false
    }

    static let defaults: [String: StoredSetting] = {
        func number(_ key: String, _ value: Int, stored: Bool = false) -> StoredSetting {
            StoredSetting(key: key, value: .int(value), defaultValue: .int(value), isStored: stored, isSecret: false, isSet: true)
        }
        func flag(_ key: String, _ value: Bool) -> StoredSetting {
            StoredSetting(key: key, value: .bool(value), defaultValue: .bool(value), isStored: false, isSecret: false, isSet: true)
        }
        func secret(_ key: String, set: Bool = false) -> StoredSetting {
            StoredSetting(key: key, value: nil, defaultValue: nil, isStored: set, isSecret: true, isSet: set)
        }
        let all = [
            number("trash_retention_days", 60), number("version_max_versions", 500), number("version_recent_days", 30),
            number("version_daily_snapshot_days", 90), number("version_weekly_snapshot_days", 365), number("audit_retention_days", 90),
            number("event_log_retention_days", 30), number("row_log_retention_days", 30), number("inbound_handled_retention_days", 7),
            number("inbound_pending_retention_days", 30), number("blob_min_copies", 1), number("disk_reserve_bytes", 134_217_728),
            flag("enrichment_enabled", true), flag("enrichment_ocr_enabled", true), flag("blob_cleanup_enabled", true), number("blob_cleanup_grace_seconds", 86400),
            number("max_request_bytes", 1_048_576), number("max_bulk_request_bytes", 16_777_216),
            number("rate_limit_requests", 4000), number("rate_limit_keys_requests", 200), number("rate_limit_window_seconds", 60),
            number("enrichment_max_blob_bytes", 20_971_520), number("enrichment_max_text_chars", 100_000),
            number("enrichment_max_attempts", 3), number("inbound_max_bytes", 26_214_400),
            number("rate_limit_inbound_requests", 600), number("inbound_backlog_deliveries", 10_000),
            number("event_stream_max_viewers", 0), number("mcp_fetch_max_bytes", 52_428_800), number("mcp_fetch_timeout_seconds", 60),
            flag("rate_limit_enabled", true), flag("mcp_fetch_enabled", true), flag("heartbeat_enabled", true),
            flag("error_reporting_enabled", true), flag("telemetry_enabled", true), flag("allow_private_addresses", false),
            secret("heartbeat_url"), secret("posthog_host"), secret("posthog_project_token"),
            secret("otel_exporter_otlp_endpoint"), secret("otel_exporter_otlp_headers"),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    }()

    let state = Mutex(State())
    private let statsPause = StatsPause()

    /// Holds later `itemStats` calls until `releaseStats`.
    func holdStats() { statsPause.hold() }
    var waitingStats: Int { statsPause.waiting }

    /// New stats calls go through, and calls already waiting stay waiting.
    func admitNewStats() { statsPause.admit() }

    var calls: [String] { state.withLock { $0.calls } }
    var sent: [[String: StoredSettingChange]] { state.withLock { $0.sent } }
    func fail(_ call: String, with failure: OwnerFailure?) { state.withLock { $0.failures[call] = failure } }

    /// Changes a setting as if another app had, between the page's read and its write.
    func changeElsewhere(_ key: String, to value: SettingValue) {
        state.withLock { $0.settings[key]?.value = value; $0.settings[key]?.isStored = true }
    }

    private func enter(_ call: String) throws(OwnerFailure) {
        let failure = state.withLock { state in
            state.calls.append(call)
            return state.failures[call]
        }
        if let failure { throw failure }
    }

    func activity(_ query: ActivityQuery) async throws(OwnerFailure) -> ActivityBatch {
        try enter("activity")
        return state.withLock { state in
            state.queries.append(query)
            let search = query.search.lowercased()
            let matching = state.entries.filter { entry in
                (query.kind == nil || Self.kind(of: entry.action) == query.kind)
                    && (search.isEmpty || entry.action.lowercased().contains(search) || (entry.who ?? "").lowercased().contains(search))
            }
            let start = query.cursor.flatMap(Int.init) ?? 0
            let end = min(start + query.limit, matching.count)
            return ActivityBatch(entries: Array(matching[start..<end]), next: end < matching.count ? String(end) : nil)
        }
    }

    func itemStats(_ query: UsageStatsQuery) async throws(OwnerFailure) -> [String: Int] {
        try enter("itemStats")
        state.withLock { $0.statQueries.append(query) }
        if statsPause.isHolding { await statsPause.park() }
        let answer = state.withLock { state -> Result<[String: Int], OwnerFailure> in
            let span = query.updatedAfter.flatMap { start in query.updatedBefore.map { $0.timeIntervalSince(start) } }
            if state.failDayStats, let span, span < 36 * 60 * 60 { return .failure(.unreachable) }
            return .success(Self.stats(state, query))
        }
        switch answer {
        case .success(let counts): return counts
        case .failure(let error): throw error
        }
    }

    /// Lets every paused stats read finish.
    func releaseStats() { statsPause.release() }

    private static func stats(_ state: State, _ query: UsageStatsQuery) -> [String: Int] {
        let span = query.updatedAfter.flatMap { start in query.updatedBefore.map { $0.timeIntervalSince(start) } }
        switch (query.grouping, span) {
        case (.type, nil): return state.allTimeType
        case (.source, nil): return state.allTimeSource
        case (.type, let span?) where span < 36 * 60 * 60: return state.dayType
        case (.source, let span?) where span < 36 * 60 * 60: return state.daySource
        case (.type, _): return state.periodType
        case (.source, _): return state.periodSource
        }
    }

    func usageMetrics() async throws(OwnerFailure) -> UsageMetrics {
        try enter("usageMetrics")
        return state.withLock { $0.metrics }
    }

    static func kind(of action: String) -> ActivityKind {
        switch action.split(separator: ".").first.map(String.init) ?? "" {
        case "auth", "owner", "key": .access
        case "config", "webhook": .settings
        case "items": .housekeeping
        default: .data
        }
    }

    func startUpSettings() async throws(OwnerFailure) -> [StartUpSetting] { try await storedSettings().startUp }

    func storedSettings() async throws(OwnerFailure) -> InstanceSettingsSnapshot {
        try enter("storedSettings")
        return state.withLock { InstanceSettingsSnapshot(instanceID: $0.instanceID, settings: $0.settings, startUp: $0.startUp) }
    }

    func change(_ changes: [String: StoredSettingChange], instanceID: String?) async throws(OwnerFailure) {
        try enter("change")
        // The write takes this long so that a test can start another while it is under way.
        if let delay = state.withLock({ $0.changeDelay }) { try? await Task.sleep(for: delay) }
        try state.withLock { state throws(OwnerFailure) in
            state.instanceIDsSent.append(instanceID)
            guard instanceID == nil || instanceID == state.instanceID else { throw .instanceChanged }
            if let refusal = state.refusal { throw .refused(refusal) }
            state.sent.append(changes)
            for (key, change) in changes {
                guard var setting = state.settings[key] else { continue }
                switch change {
                case .set(let value):
                    setting.value = setting.isSecret ? nil : value
                    setting.isStored = true
                    setting.isSet = true
                case .clear:
                    setting.value = setting.isSecret ? nil : setting.defaultValue
                    setting.isStored = false
                    setting.isSet = !setting.isSecret
                }
                state.settings[key] = setting
            }
            if state.failReadsAfterChange { state.failures["storedSettings"] = .unreachable }
        }
    }
}

@MainActor private func limitsModel(_ calls: FakeInstanceCalls = FakeInstanceCalls(), refreshed: RefreshCount = RefreshCount()) -> LimitsModel {
    LimitsModel(
        context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.configManage] }, refreshGrants: { refreshed.count += 1 }), calls: calls)
}

@MainActor private func monitoringModel(_ calls: FakeInstanceCalls = FakeInstanceCalls()) -> MonitoringModel {
    MonitoringModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.configManage] }), calls: calls)
}

@MainActor final class RefreshCount {
    var count = 0
}

@Suite(.hangLimit) @MainActor struct LimitsTests {
    private static let american = Locale(identifier: "en_US")
    private static let german = Locale(identifier: "de_DE")
    private static let french = Locale(identifier: "fr_FR")

    @Test func sizesAreShownInMegabytesAndSentInBytes() {
        let us = Self.american
        #expect(LimitSetting.largestRequest.text(for: 1_048_576, locale: us) == "1")
        #expect(LimitSetting.largestBulkRequest.text(for: 16_777_216, locale: us) == "16")
        #expect(LimitSetting.largestRequest.text(for: 1_572_864, locale: us) == "1.5")
        #expect(LimitSetting.largestRequest.entry(from: "2", locale: us) == .value(2_097_152))
        #expect(LimitSetting.largestRequest.entry(from: "0.5", locale: us) == .value(524_288))
        #expect(LimitSetting.requestsPerWindow.text(for: 4000, locale: us) == "4,000", "thousands are separated, as the board shows them")
        #expect(LimitSetting.mostTextKept.text(for: 100_000, locale: us) == "100,000")
        #expect(LimitSetting.mostTextKept.entry(from: "100,000", locale: us) == .value(100_000), "what the field shows can be typed back")
        #expect(LimitSetting.largestRequest.entry(from: "1,024", locale: us) == .value(1_073_741_824))
        #expect(LimitSetting.requestsPerWindow.entry(from: "4000", locale: us) == .value(4000))
    }

    @Test func numbersAreGroupedAndPointedAsTheMacsRegionDoes() {
        let de = Self.german
        #expect(LimitSetting.requestsPerWindow.text(for: 4000, locale: de) == "4.000")
        #expect(LimitSetting.largestRequest.text(for: 1_572_864, locale: de) == "1,5")
        #expect(LimitSetting.requestsPerWindow.entry(from: "4.000", locale: de) == .value(4000), "what the field shows can be typed back")
        #expect(LimitSetting.largestRequest.entry(from: "0,5", locale: de) == .value(524_288), "the region's comma is its point")
        #expect(LimitSetting.largestRequest.entry(from: "1.024", locale: de) == .value(1_073_741_824))
        #expect(LimitSetting.requestsPerWindow.entry(from: "4,000", locale: Self.american) == .value(4000))
        #expect(LimitSetting.largestRequest.entry(from: "0,5", locale: Self.american) == .invalid("Use digits only."), "a separator the region does not use is refused, not guessed at")
        #expect(LimitSetting.largestRequest.entry(from: "1.5", locale: de) == .invalid("Use digits only."))
        let fr = Self.french
        let shown = LimitSetting.mostTextKept.text(for: 100_000, locale: fr)
        #expect(LimitSetting.mostTextKept.entry(from: shown, locale: fr) == .value(100_000), "a space between thousands is typed back as it is shown")
        #expect(LimitSetting.mostTextKept.entry(from: "100 000", locale: fr) == .value(100_000))
    }

    @Test func aValueOutOfRangeIsToldBeforeAnythingIsSent() {
        #expect(LimitSetting.largestBulkRequest.entry(from: "33") == .invalid("Use a number above 0, up to 32 MB."))
        #expect(LimitSetting.tries.entry(from: "0") == .invalid("Use a number from 1 to 100 times."))
        #expect(LimitSetting.tries.entry(from: "101") == .invalid("Use a number from 1 to 100 times."))
        #expect(LimitSetting.tries.entry(from: "2.5", locale: Self.american) == .invalid("Use a whole number."))
        #expect(LimitSetting.tries.entry(from: "three", locale: Self.american) == .invalid("Use digits only."))
        #expect(LimitSetting.mostViewers.entry(from: "0") == .value(0), "0 is allowed where the server allows it")
        #expect(LimitSetting.tries.entry(from: "  ") == .useDefault)
    }

    @Test func aTypedValueIsSentOnceWithTheInstanceThatWasRead() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        model.drafts["max_bulk_request_bytes"] = "8"
        await model.commit(.largestBulkRequest)
        #expect(calls.sent == [["max_bulk_request_bytes": .set(.int(8_388_608))]])
        #expect(calls.state.withLock { $0.instanceIDsSent } == ["instance-1"])
        #expect(model.text(.largestBulkRequest) == "8", "it shows what the server now holds")
        #expect(model.drafts.isEmpty)
        await model.commit(.largestBulkRequest)
        #expect(calls.sent.count == 1, "a value that hasn't changed is not sent again")
    }

    @Test func aValueOutOfRangeKeepsWhatWasTypedAndSendsNothing() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        model.drafts["enrichment_max_attempts"] = "500"
        await model.commit(.tries)
        #expect(calls.sent.isEmpty)
        #expect(model.text(.tries) == "500")
        #expect(model.line(.tries) == "Use a number from 1 to 100 times.")
        #expect(model.hasProblem(.tries))
    }

    @Test func aRefusedWriteRestoresTheHeldValueWithOneLineInPlainWords() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.refusal = "`max_request_bytes` can't be less than the bulk limit; PATCH /config refused." }
        var returned: [OwnerDraft] = []
        let model = LimitsModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.configManage] }, lateDraft: { returned.append($0) }), calls: calls)
        await model.load()
        model.drafts["max_request_bytes"] = "2"
        await model.commit(.largestRequest)
        #expect(model.text(.largestRequest) == "1", "the last server value returns")
        #expect(model.line(.largestRequest) == "The server refused this change. Nothing was changed.", "no backticks, names or routes")
        #expect(model.hasProblem(.largestRequest))
        #expect(returned == [.typed(title: LimitSetting.largestRequest.title, text: "2")])
        calls.state.withLock { $0.refusal = "A request can't be larger than the bulk limit." }
        model.type("2", for: .largestRequest)
        await model.commit(.largestRequest)
        #expect(model.line(.largestRequest) == "A request can't be larger than the bulk limit.", "a refusal with plain words is shown")
    }

    @Test func emptyingAStoredLimitRemovesItSoTheDefaultApplies() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.settings["enrichment_max_attempts"] = StoredSetting(key: "enrichment_max_attempts", value: .int(5), defaultValue: .int(3), isStored: true, isSecret: false, isSet: true) }
        let model = limitsModel(calls)
        await model.load()
        model.drafts["enrichment_max_attempts"] = ""
        await model.commit(.tries)
        #expect(calls.sent == [["enrichment_max_attempts": .clear]])
        #expect(model.text(.tries) == "3")
    }

    @Test func aLimitChangedElsewhereIsToldAndNotWrittenOver() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        calls.changeElsewhere("enrichment_max_attempts", to: .int(7))
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(calls.sent.isEmpty, "nothing is written over the newer value")
        #expect(model.text(.tries) == "7", "the page shows what is there now")
        #expect(model.notice == "Tries was changed elsewhere. The app read the new value; yours wasn’t saved.")
    }

    @Test func anotherMarfaAtTheAddressIsToldAsThatAndNothingIsAdopted() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        calls.state.withLock {
            $0.instanceID = "instance-2"
            $0.settings["enrichment_max_attempts"]?.value = .int(9)
        }
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(calls.sent.isEmpty)
        #expect(model.notice == nil, "it did not change somewhere else: another Marfa answered")
        #expect(model.line(.tries) == "Another Marfa now answers at this address. Nothing was sent.")
        #expect(model.held(.tries) == 3, "the other Marfa's value is not adopted")
        #expect(model.text(.tries) == "3", "the original value returns")
        await model.commit(.tries)
        #expect(calls.sent.isEmpty, "no retry is sent to it")
        #expect(calls.state.withLock { $0.instanceIDsSent }.isEmpty)
    }

    @Test func aSecondFieldLeftWhileAWriteRunsIsSentAfterIt() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.changeDelay = .milliseconds(150) }
        let model = limitsModel(calls)
        await model.load()
        model.drafts["enrichment_max_attempts"] = "4"
        model.drafts["rate_limit_window_seconds"] = "30"
        async let first: Void = model.commit(.tries)
        async let second: Void = model.commit(.window)
        _ = await (first, second)
        #expect(calls.sent.count == 2, "both were sent, one after the other")
        #expect(model.held(.tries) == 4 && model.held(.window) == 30)
        #expect(model.line(.window) == nil && model.line(.tries) == nil)
        #expect(model.notice == nil, "the second was not told it changed elsewhere")
    }

    @Test func aFailedReadAfterASuccessfulWriteKeepsTheValuesSent() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.failReadsAfterChange = true }
        let model = limitsModel(calls)
        await model.load()
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(model.held(.tries) == 4, "what was sent is kept, though the read after it failed")
        calls.state.withLock { $0.failures["storedSettings"] = nil }
        model.drafts["enrichment_max_attempts"] = "5"
        await model.commit(.tries)
        #expect(model.notice == nil, "a later write is not told it changed elsewhere")
        #expect(calls.sent.count == 2)
        #expect(model.held(.tries) == 5)
    }

    @Test func theNoticeClosesWhenThePersonNextEditsOrCloses() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        calls.changeElsewhere("enrichment_max_attempts", to: .int(7))
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(model.notice != nil)
        model.type("5", for: .window)
        #expect(model.notice == nil, "the next edit closes it")
        #expect(model.drafts["rate_limit_window_seconds"] == "5")
        calls.changeElsewhere("enrichment_max_attempts", to: .int(8))
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        model.dismissNotice()
        #expect(model.notice == nil, "Close closes it")
    }

    @Test func aWriteTheServerAnswersAsAConflictIsToldAndReadAgain() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        calls.fail("change", with: .conflict)
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(model.notice != nil)
        #expect(calls.calls.filter { $0 == "storedSettings" }.count >= 3, "it read again")
    }

    @Test func aWriteRefusedForWantOfAPermissionNamesItAndReadsWhatIsHeldAgain() async {
        let calls = FakeInstanceCalls()
        let refreshed = RefreshCount()
        let model = limitsModel(calls, refreshed: refreshed)
        await model.load()
        calls.fail("change", with: .notPermitted("config.manage"))
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(refreshed.count == 1)
        #expect(!model.isLoaded)
        #expect(model.line(.tries) == OwnerWording.permissionLine("config.manage"))
        #expect(model.text(.tries) == "3")
    }

    @Test func aReadRefusedForWantOfAPermissionIsThePagesState() async {
        let calls = FakeInstanceCalls()
        calls.fail("storedSettings", with: .notPermitted("config.manage"))
        let refreshed = RefreshCount()
        let model = limitsModel(calls, refreshed: refreshed)
        await model.load()
        #expect(model.failure == .notPermitted("config.manage"))
        #expect(!model.isLoaded)
        #expect(refreshed.count == 1)
    }

    @Test func theServerNotAnsweringIsThePagesState() async {
        let calls = FakeInstanceCalls()
        calls.fail("storedSettings", with: .unreachable)
        let model = limitsModel(calls)
        await model.load()
        #expect(model.failure == .unreachable)
    }

    @Test func aSwitchIsSentAtOnce() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        #expect(model.isOn("rate_limit_enabled"))
        await model.setSwitch("rate_limit_enabled", false)
        #expect(calls.sent == [["rate_limit_enabled": .set(.bool(false))]])
        #expect(!model.isOn("rate_limit_enabled"))
    }

    @Test func aMissingSettingAndAStartOnlySettingCannotBeWritten() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.settings["rate_limit_enabled"] = nil }
        let model = limitsModel(calls)
        await model.load()
        await model.setSwitch("rate_limit_enabled", true)
        await model.setSwitch("MARFA_PORT", true)
        #expect(calls.sent.isEmpty)
    }

    @Test func pausingTelemetryPausesReportsAndPreservesTheirStoredSwitch() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        await model.setSwitch("telemetry_enabled", false)
        #expect(!model.isOn("error_reporting_enabled"))
        #expect((try? await calls.storedSettings())?.activeMonitoringCount == 1)
        #expect(model.isOn("heartbeat_enabled"))
        await model.setSwitch("error_reporting_enabled", true)
        await model.setSwitch("telemetry_enabled", true)
        #expect(model.isOn("error_reporting_enabled"))
        #expect(calls.sent == [["telemetry_enabled": .set(.bool(false))], ["telemetry_enabled": .set(.bool(true))]])
    }

    @Test func retentionChoicesIncludeTheServersBoundsInTheirOwnUnits() {
        for setting in InstanceSetting.versionSettings + InstanceSetting.logSettings + [.trashRetentionDays, .blobCleanupGraceSeconds] {
            let choices = InstanceChoices.options(for: setting, holding: nil, defaultValue: nil).compactMap(\.value)
            #expect(choices.contains(setting.range.lowerBound))
            #expect(choices.contains(setting.range.upperBound))
        }
        #expect(InstanceSetting.versionMaxVersions.range == 1...1_000_000)
        #expect(InstanceChoices.title(.trashRetentionDays, 0) == "No Limit")
        #expect(InstanceChoices.title(.versionRecentDays, 0) == "0 Days")
    }

    @Test func aLimitThatDependsOnASwitchIsOffWhileTheSwitchIs() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        #expect(model.isOn(LimitSetting.rateLimitSwitch))
        #expect(model.isEnabled(.requestsPerWindow))
        await model.setSwitch(LimitSetting.rateLimitSwitch, false)
        for limit in [LimitSetting.requestsPerWindow, .keyRequestsPerWindow, .window, .deliveriesPerWindow] {
            #expect(!model.isEnabled(limit), "\(limit.title) is off with Limit Requests")
        }
        #expect(model.isEnabled(.largestRequest))
        #expect(model.isEnabled(.largestFetch) == model.isOn(LimitSetting.fetchSwitch))
        await model.setSwitch(LimitSetting.fetchSwitch, false)
        #expect(!model.isEnabled(.largestFetch))
        #expect(!model.isEnabled(.fetchTime))
        #expect(model.isEnabled(.mostViewers))
    }

    @Test func whatWasTypedAndNotSentIsHandedBackWhenSettingsCloses() async {
        let model = limitsModel()
        await model.load()
        model.drafts["max_request_bytes"] = "9"
        model.drafts["enrichment_max_attempts"] = "3"
        #expect(model.takeDrafts() == [.typed(title: "Largest request", text: "9")], "a value the server already holds is no draft")
        #expect(model.drafts.isEmpty)
    }

    @Test func everyLimitIsSomethingTheClientCanSend() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        for limit in LimitSetting.all { #expect(model.held(limit) != nil, "\(limit.key) is read") }
        #expect(LimitSetting.all.count + 2 == 16)
    }
}

@Suite(.hangLimit) @MainActor struct MonitoringTests {
    @Test func aPausedReportDestinationCanBeEditedAndRemovedBeforeResuming() async throws {
        let calls = FakeInstanceCalls()
        calls.changeElsewhere("telemetry_enabled", to: .bool(false))
        let model = monitoringModel(calls)
        await model.load()
        #expect(!model.isOn("error_reporting_enabled"))
        model.begin(.postHogHost)
        model.sheet?.inputs["posthog_host"] = "https://reports.example"
        model.sheet?.inputs["posthog_project_token"] = "test"
        await model.save()
        #expect(model.errorReportsHaveReceiver)
        model.askToRemove(.postHogToken)
        let question = try #require(model.question)
        await model.confirm(question)
        await model.setSwitch("telemetry_enabled", true)
        #expect(!model.telemetryHasReceiver)
        #expect(!model.errorReportsHaveReceiver)
    }

    @Test(arguments: ["traces", "logs", "metrics"])
    func signalOverridesNeedABaseAndErrorReportsNeedTheirOwnSwitch(signal: String) async {
        let calls = FakeInstanceCalls()
        let key = "otel_exporter_otlp_\(signal)_endpoint"
        calls.state.withLock {
            $0.settings[key] = StoredSetting(key: key, value: nil, defaultValue: nil, isStored: true, isSecret: true, isSet: true)
            $0.settings["posthog_host"]?.isSet = true
            $0.settings["posthog_project_token"]?.isSet = true
        }
        calls.changeElsewhere("error_reporting_enabled", to: .bool(false))
        let model = monitoringModel(calls)
        await model.load()
        #expect(!model.telemetryHasReceiver)
        await model.setSwitch("error_reporting_enabled", true)
        #expect(model.telemetryHasReceiver)
        await model.setSwitch("error_reporting_enabled", false)
        calls.state.withLock { $0.settings["otel_exporter_otlp_endpoint"]?.isSet = true }
        await model.load()
        #expect(model.telemetryHasReceiver)
    }

    @Test func aSecretIsOnlySetOrNotSet() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.settings["heartbeat_url"]?.isSet = true }
        let model = monitoringModel(calls)
        await model.load()
        #expect(model.isSet(.heartbeatAddress))
        #expect(!model.isSet(.postHogToken))
        #expect(model.heartbeatHasReceiver)
    }

    @Test func aSecretIsSetThenCleared() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        model.begin(.heartbeatAddress)
        #expect(model.sheet?.fields == [.heartbeatAddress])
        model.sheet?.inputs["heartbeat_url"] = "  https://monitor.example/ping  "
        await model.save()
        #expect(calls.sent == [["heartbeat_url": .set(.text("https://monitor.example/ping"))]])
        #expect(model.sheet == nil, "the sheet and what was typed are gone")
        #expect(model.isSet(.heartbeatAddress))
        #expect(calls.state.withLock { $0.settings["heartbeat_url"]?.value } == nil, "the value is never read back")

        model.askToRemove(.heartbeatAddress)
        #expect(model.question?.title == "Remove the heartbeat address?", "it asks first")
        #expect(model.question?.message == "The server stops sending its heartbeat.")
        #expect(calls.sent.count == 1, "nothing is removed until the owner agrees")
        await model.confirm(model.question!)
        #expect(calls.sent.last == ["heartbeat_url": .clear])
        #expect(!model.isSet(.heartbeatAddress))
        #expect(model.sheet == nil)
    }

    @Test func aRefusedSecretKeepsTheSheetAndWhatWasTypedWithOneLine() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.refusal = "Use a public address; allow_private_addresses is off." }
        let model = monitoringModel(calls)
        await model.load()
        model.begin(.heartbeatAddress)
        model.sheet?.inputs["heartbeat_url"] = "http://10.0.0.1"
        await model.save()
        #expect(model.sheet?.inputs["heartbeat_url"] == "http://10.0.0.1")
        #expect(model.sheet?.error == "The server refused this change. Nothing was changed.")
        #expect(!model.isSet(.heartbeatAddress))
    }

    @Test func theTwoPostHogSecretsAreSetTogetherAndRemovedTogether() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        model.begin(.postHogToken)
        #expect(model.sheet?.fields == [.postHogHost, .postHogToken], "the server takes them only together")
        model.sheet?.inputs["posthog_host"] = "https://eu.example"
        model.sheet?.inputs["posthog_project_token"] = "phc_secret"
        await model.save()
        #expect(calls.sent == [["posthog_host": .set(.text("https://eu.example")), "posthog_project_token": .set(.text("phc_secret"))]])
        #expect(model.errorReportsHaveReceiver)

        model.begin(.postHogToken)
        #expect(model.sheet?.fields == [.postHogToken], "with the host set, only the token is asked")
        model.close()
        model.askToRemove(.postHogToken)
        #expect(model.question?.message == "The PostHog host and the project token are removed together, and error reports stop.")
        await model.confirm(model.question!)
        #expect(Set(calls.sent.last?.keys.map { $0 } ?? []) == ["posthog_host", "posthog_project_token"])
        #expect(!model.isSet(.postHogHost) && !model.isSet(.postHogToken))
    }

    @Test func onePostHogFieldAloneIsToldBeforeAnythingIsSent() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        model.begin(.postHogHost)
        model.sheet?.inputs["posthog_host"] = "https://eu.example"
        await model.save()
        #expect(calls.sent.isEmpty)
        #expect(model.sheet?.error == "Type both the host and the project token.")
        #expect(model.sheet?.inputs["posthog_host"] == "https://eu.example", "what was typed stays")
    }

    @Test func aSecretIsNeverHandedOverOrKeptAfterTheSheetCloses() async {
        let model = monitoringModel()
        await model.load()
        model.begin(.postHogToken)
        model.sheet?.inputs["posthog_project_token"] = "phc_secret"
        model.close()
        #expect(model.sheet == nil)
        model.begin(.postHogToken)
        #expect(model.sheet?.inputs.isEmpty == true)
    }

    @Test func aSwitchThatNeedsAReceiverSaysSoWithoutSendingAnything() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.settings["heartbeat_enabled"]?.value = .bool(false) }
        let model = monitoringModel(calls)
        await model.load()
        await model.setSwitch("heartbeat_enabled", true)
        #expect(calls.sent.isEmpty)
        #expect(model.line("heartbeat_enabled") == "Set the address first.")
        #expect(!model.isOn("heartbeat_enabled"))
    }

    @Test func aSecretChangedElsewhereIsToldAndNotWrittenOver() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        calls.state.withLock { $0.settings["heartbeat_url"]?.isSet = true }
        model.begin(.heartbeatAddress)
        model.sheet?.inputs["heartbeat_url"] = "https://monitor.example/ping"
        await model.save()
        #expect(calls.sent.isEmpty)
        #expect(model.notice != nil)
        #expect(model.isSet(.heartbeatAddress), "the page now shows it as set")
    }

    @Test func aSecretChangedElsewhereNamesItByTheWordsOfThePage() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        calls.state.withLock { $0.settings["posthog_host"]?.isSet = true }
        model.begin(.postHogHost)
        model.sheet?.inputs["posthog_host"] = "https://eu.example"
        model.sheet?.inputs["posthog_project_token"] = "phc_secret"
        await model.save()
        #expect(model.notice == "Error reports address was changed elsewhere. The app read the new value; yours wasn’t saved.")
        model.dismissNotice()
        #expect(model.notice == nil)
    }

    @Test func anotherMarfaAtTheAddressIsToldOnTheRowAndNothingIsAdopted() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        calls.state.withLock {
            $0.instanceID = "instance-2"
            $0.settings["telemetry_enabled"]?.value = .bool(true)
        }
        await model.setSwitch("telemetry_enabled", false)
        #expect(calls.sent.isEmpty)
        #expect(model.notice == nil)
        #expect(model.line("telemetry_enabled") == "Another Marfa now answers at this address. Nothing was sent.")
        #expect(model.isOn("telemetry_enabled"), "what the page showed is not replaced by the other Marfa's")
    }

    @Test func aSecretIsTypedSecurelyUnlessTheServerKeepsItInPlainView() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock {
            $0.settings["otel_exporter_otlp_endpoint"] = StoredSetting(
                key: "otel_exporter_otlp_endpoint", value: .text("https://collector.example"), defaultValue: nil, isStored: true,
                isSecret: false, isSet: true)
        }
        let model = monitoringModel(calls)
        await model.load()
        #expect(model.isSecure(.heartbeatAddress), "a secret the server holds is typed securely")
        #expect(!model.isSecure(.telemetryAddress))
        model.begin(.telemetryAddress)
        #expect(model.sheet?.inputs["otel_exporter_otlp_endpoint"] == "https://collector.example", "a setting that can be read is there to change")
        model.close()
        model.begin(.heartbeatAddress)
        #expect(model.sheet?.inputs.isEmpty == true, "a secret is never put back in a field")
    }

    @Test func aRemovalFailingKeepsTheRowAndSaysWhyOnIt() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.settings["heartbeat_url"]?.isSet = true }
        let model = monitoringModel(calls)
        await model.load()
        calls.state.withLock { $0.refusal = "Not now." }
        model.askToRemove(.heartbeatAddress)
        await model.confirm(model.question!)
        #expect(model.line("heartbeat_url") == "Not now.")
        #expect(model.isSet(.heartbeatAddress))
    }

    @Test func theTelemetrySwitchIsSentAtOnce() async {
        let calls = FakeInstanceCalls()
        let model = monitoringModel(calls)
        await model.load()
        await model.setSwitch("telemetry_enabled", false)
        #expect(calls.sent == [["telemetry_enabled": .set(.bool(false))]])
    }
}

@Suite(.hangLimit) @MainActor struct ActivityTests {
    private func entries(_ count: Int) -> [ActivityEntry] {
        (0..<count).map { index in
            ActivityEntry(
                id: "e\(index)", date: Date(timeIntervalSince1970: 1_700_000_000 - Double(index) * 60), who: index.isMultiple(of: 2) ? "Mira" : "Marfa",
                action: index.isMultiple(of: 3) ? "auth.sign_in.success" : "item.update", resourceType: "item", resourceID: nil, address: nil)
        }
    }

    private func model(_ calls: FakeInstanceCalls) -> ActivityModel {
        ActivityModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.auditRead] }), calls: calls)
    }

    @Test func anEmptyLogIsAnEmptyPage() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.reload()
        #expect(model.hasLoaded)
        #expect(model.entries.isEmpty)
        #expect(model.range == nil)
        #expect(!model.hasNext)
        #expect(model.failure == nil)
    }

    @Test func aPageAtATimeNewestFirstWithTheWayBack() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let model = model(calls)
        await model.reload()
        #expect(model.entries.count == 20)
        #expect(model.range == "1 to 20")
        #expect(model.hasNext)
        await model.older()
        #expect(model.range == "21 to 40")
        #expect(model.entries.first?.id == "e20")
        await model.older()
        #expect(model.range == "41 to 45")
        #expect(!model.hasNext)
        await model.newer()
        #expect(model.range == "21 to 40")
        #expect(model.entries.first?.id == "e20")
        await model.newer()
        #expect(model.pageIndex == 0)
        #expect(model.entries.first?.id == "e0")
    }

    @Test func pagingIsOfferedOnlyWhereThereIsAnotherPage() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.reload()
        #expect(!model.isPaged, "an empty log has nothing to page")
        calls.state.withLock { $0.entries = entries(5) }
        await model.reload()
        #expect(!model.isPaged)
        calls.state.withLock { $0.entries = entries(45) }
        await model.reload()
        #expect(model.isPaged)
        await model.older()
        await model.older()
        #expect(model.isPaged, "the last page has a way back")
    }

    @Test func aFilterStartsAgainFromTheNewest() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let model = model(calls)
        await model.reload()
        await model.older()
        model.kind = .access
        await model.reload()
        #expect(model.pageIndex == 0)
        #expect(model.entries.allSatisfy { $0.action.hasPrefix("auth") })
        #expect(calls.state.withLock { $0.queries.last?.cursor } == nil)
        #expect(model.isFiltered)
        model.search = "nothing like this"
        await model.reload()
        #expect(model.entries.isEmpty)
    }

    @Test func aFailedPageKeepsTheOneShown() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let model = model(calls)
        await model.reload()
        calls.fail("activity", with: .unreachable)
        await model.older()
        #expect(model.failure == .unreachable)
        #expect(model.range == "1 to 20")
        calls.fail("activity", with: nil)
        await model.older()
        #expect(model.range == "21 to 40", "the way forward still works after a failure")
    }

    @Test func aFailedReadForANewFilterNeverLeavesTheOldFiltersRowsShown() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let model = model(calls)
        await model.reload()
        await model.older()
        calls.fail("activity", with: .unreachable)
        model.kind = .access
        await model.reload()
        #expect(model.failure == .unreachable)
        #expect(model.entries.isEmpty, "rows of the old filter are not kept under the new one")
        #expect(model.range == nil && !model.hasNext)
        #expect(model.pageIndex == 0)
        calls.fail("activity", with: nil)
        await model.reload()
        #expect(model.entries.allSatisfy { $0.action.hasPrefix("auth") })
    }

    @Test func aReadRefusedForWantOfAPermissionIsToldAndGrantsAreReadAgain() async {
        let calls = FakeInstanceCalls()
        calls.fail("activity", with: .notPermitted("audit.read"))
        let refreshed = RefreshCount()
        let model = ActivityModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.auditRead] }, refreshGrants: { refreshed.count += 1 }), calls: calls)
        await model.reload()
        #expect(model.failure == .notPermitted("audit.read"))
        #expect(refreshed.count == 1)
    }

    @Test func wordsAreTheAppsAndNeverTheServersKeys() {
        #expect(ActivityWording.what("item.delete") == "Moved an item to Trash")
        #expect(ActivityWording.what("items.trash") == "Moved items to Trash")
        #expect(ActivityWording.what("items.feed_expired") == "Moved expired Feed items to Trash")
        #expect(ActivityWording.what("auth.sign_in.success") == "Signed in")
        #expect(ActivityWording.what("config.update") == "Changed the settings")
        #expect(ActivityWording.what("thing.did_something") == "Thing did something", "an unknown action is still put into words")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = Date(timeIntervalSince1970: 1_700_050_000)
        #expect(ActivityWording.when(now.addingTimeInterval(-3_600), now: now, calendar: calendar) == Date(timeIntervalSince1970: 1_700_046_400).formatted(.dateTime.hour().minute()))
        #expect(ActivityWording.when(now.addingTimeInterval(-86_400), now: now, calendar: calendar) == "Yesterday")
        #expect(ActivityWording.when(nil) == "")
    }

    @Test func everyActionTheContractNamesHasWords() {
        for action in ["item.create", "key.revoke", "webhook.delivery.redeliver", "owner.password.changed", "auth.refresh.replayed", "auth.grants.purged"] {
            #expect(ActivityWording.what(action) != action)
            #expect(!ActivityWording.what(action).contains("."))
        }
    }

    @Test func theLoadedPageSortsByEachColumnAndAMissingValueSortsAsNothing() async {
        let calls = FakeInstanceCalls()
        let sent = [
            ActivityEntry(id: "b", date: Date(timeIntervalSince1970: 200), who: "Mira", action: "item.update", resourceType: "item", resourceID: nil, address: "10.0.0.2"),
            ActivityEntry(id: "a", date: nil, who: nil, action: "auth.sign_in.success", resourceType: "item", resourceID: nil, address: nil),
            ActivityEntry(id: "c", date: Date(timeIntervalSince1970: 100), who: "Ada", action: "config.update", resourceType: "item", resourceID: nil, address: "10.0.0.1"),
        ]
        calls.state.withLock { $0.entries = sent }
        let model = model(calls)
        await model.reload()
        #expect(model.orderLabel == "Newest first")
        #expect(model.listed.map(\.id) == ["b", "c", "a"], "a missing time is the oldest, so newest first puts it last")
        model.toggleSort(.when)
        #expect(model.orderLabel == "Oldest first")
        #expect(model.listed.map(\.id) == ["a", "c", "b"])
        model.toggleSort(.when)
        #expect(model.listed.map(\.id) == ["b", "c", "a"])

        model.toggleSort(.who)
        #expect(model.order.ascending)
        #expect(model.orderLabel == "A to Z")
        #expect(model.listed.map(\.id) == ["c", "b", "a"], "a missing name is Unknown, after Ada and Mira")
        model.toggleSort(.who)
        #expect(model.orderLabel == "Z to A")
        #expect(model.listed.map(\.id) == ["a", "b", "c"])

        model.toggleSort(.what)
        #expect(model.listed.map(\.id) == ["b", "c", "a"], "Changed an item, Changed the settings, Signed in")
        model.toggleSort(.what)
        #expect(model.listed.map(\.id) == ["a", "c", "b"])

        model.toggleSort(.address)
        #expect(model.listed.map(\.id) == ["a", "c", "b"])
        model.toggleSort(.address)
        #expect(model.listed.map(\.id) == ["b", "c", "a"])
        #expect(model.entries.map(\.id) == ["b", "a", "c"], "sorting the page shown does not reorder what the server sent")
    }

    @Test func equalTimesKeepTheServersOrder() async {
        let calls = FakeInstanceCalls()
        let date = Date(timeIntervalSince1970: 200)
        calls.state.withLock {
            $0.entries = [
                ActivityEntry(id: "b", date: date, who: "Mira", action: "item.update", resourceType: "item", resourceID: nil, address: nil),
                ActivityEntry(id: "a", date: date, who: "Ada", action: "item.create", resourceType: "item", resourceID: nil, address: nil),
            ]
        }
        let model = model(calls)
        await model.reload()
        #expect(model.listed.map(\.id) == ["b", "a"])
        model.toggleSort(.when)
        #expect(model.listed.map(\.id) == ["b", "a"], "the same instant stays in the order the server sent")
    }

    @Test func anOlderPageRefusedForWantOfAPermissionClearsTheRows() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let refreshed = RefreshCount()
        let model = ActivityModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.auditRead] }, refreshGrants: { refreshed.count += 1 }), calls: calls)
        await model.reload()
        calls.fail("activity", with: .notPermitted("audit.read"))
        await model.older()
        #expect(model.entries.isEmpty)
        #expect(model.failure == .notPermitted("audit.read"))
        #expect(model.range == nil)
        #expect(refreshed.count == 1)
    }

    @Test func aLateRefusalDoesNotClearANewerPage() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.entries = entries(45) }
        let pause = StatsPause()
        pause.hold()
        let model = ActivityModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.auditRead] }, refreshGrants: { await pause.park() }), calls: calls)
        await model.reload()
        calls.fail("activity", with: .notPermitted("audit.read"))
        let older = Task { await model.older() }
        #expect(await eventually { pause.waiting >= 1 })
        calls.fail("activity", with: nil)
        await model.reload()
        #expect(model.entries.first?.id == "e0")
        #expect(model.failure == nil)
        pause.release()
        await older.value
        #expect(model.entries.first?.id == "e0")
        #expect(model.failure == nil)
    }

    @Test func choosingWhenStartsNewestFirstAndAnyOtherColumnStartsAtA() {
        let model = model(FakeInstanceCalls())
        model.toggleSort(.who)
        model.toggleSort(.when)
        #expect(model.order == ActivityOrder(column: .when, ascending: false))
        model.toggleSort(.address)
        #expect(model.order == ActivityOrder(column: .address, ascending: true))
    }

    @Test func eachTabNamesThePermissionItNeeds() {
        #expect(MarfaSettingsPage.activity.permission == nil)
        #expect(ActivityTab.usage.permission == nil, "item counts follow type access, and storage asks for instance.read itself")
        #expect(ActivityTab.log.permission == .auditRead)
        #expect(ActivityTab.log.permissionLine == "The app isn’t allowed to read the server’s audit log.")
        #expect(ActivityTab.usage.permissionLine == "The app isn’t allowed to read how many items this Marfa holds.")
        #expect(ActivityTab.usage.permissionLine != ActivityTab.log.permissionLine)
        #expect(ActivityTab.usage.permissionLine != MarfaSettingsPage.fileStorage.permissionLine)
    }
}

@Suite(.hangLimit) @MainActor struct ActivityUsageTests {
    private func calendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func model(_ calls: FakeInstanceCalls, now: Date = Date(timeIntervalSince1970: 1_700_000_000)) -> ActivityUsageModel {
        ActivityUsageModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.instanceRead] }), calls: calls, now: { now }, calendar: calendar())
    }

    @Test func itemStatsAsksForTheGroupingAndTheDayBounds() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(3_600)
        let day = ClientInstanceCalls.itemStatsRequest(
            UsageStatsQuery(grouping: .source, updatedAfter: start, updatedBefore: end))
        #expect(day.grouping == .source)
        #expect(day.filters.updatedAfter == ItemDate.instant(start))
        #expect(day.filters.updatedBefore == ItemDate.instant(end))
        let open = ClientInstanceCalls.itemStatsRequest(UsageStatsQuery(grouping: .type))
        #expect(open.grouping == .type)
        #expect(open.filters.updatedAfter == nil)
        #expect(open.filters.updatedBefore == nil)
    }

    @Test func anEmptyMarfaIsZerosNotAFailure() async {
        let model = model(FakeInstanceCalls())
        await model.reload()
        #expect(model.hasStats)
        #expect(model.hasMetrics)
        #expect(model.statsFailure == nil)
        #expect(model.storedItems == 0)
        #expect(model.versionCount == 0)
        #expect(model.days.count == 7)
        #expect(model.typeRows.isEmpty)
        #expect(model.sourceRows.isEmpty)
        #expect(model.chart.series.isEmpty)
        #expect(model.chart.other == nil)
    }

    @Test func aTypeOrSourceWithNoItemsStaysInTheTableAndDoesNotBreakTheChart() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock {
            $0.allTimeType = ["core.note": 4, "core.empty": 0]
            $0.allTimeSource = ["app.marfa-mac": 4, "app.none": 0]
            $0.dayType = ["core.note": 1, "core.empty": 0]
            $0.periodSource = ["app.marfa-mac": 2, "app.none": 0]
        }
        let model = model(calls)
        await model.reload()
        #expect(model.typeRows.first { $0.key == "core.empty" } == UsageRow(key: "core.empty", items: 0, changed: 0))
        #expect(model.sourceRows.first { $0.key == "app.none" } == UsageRow(key: "app.none", items: 0, changed: 0))
        #expect(model.chart.series.map(\.key) == ["core.note"])
        #expect(model.chart.series.first?.values == Array(repeating: 1, count: 7))
        #expect(model.storedItems == 4)
    }

    @Test func aVeryLongTypeOrSourceNameIsKeptWhole() {
        let key = "x" + String(repeating: "y", count: 399)
        #expect(key.count == 400)
        let rows = UsageMath.rows(items: [key: 1], changed: [key: 0])
        #expect(rows == [UsageRow(key: key, items: 1, changed: 0)])
        let named = UsageNaming.typeName(key, plural: nil)
        #expect(named.count == 400)
        #expect(named.hasPrefix("X"))
        #expect(UsageNaming.sourceName(key, named: nil).count == 400)
        #expect(UsageNaming.typeName("core.rss_entry", plural: "RSS Entries") == "RSS Entries")
        #expect(UsageNaming.typeName("core.rss_entry", plural: nil) == "Rss Entry")
    }

    @Test func theChartKeepsFourAndFoldsTheRestAndADayIsHalfOpen() async {
        let daily = [
            ["a": 1, "b": 9, "c": 3, "d": 4, "e": 2],
            ["a": 1, "b": 1, "c": 1, "d": 1, "e": 1],
        ]
        let chart = UsageMath.chart(daily: daily)
        #expect(chart.series.map(\.key) == ["b", "d", "c", "e"], "the busiest is first, which the chart draws at the bottom")
        #expect(chart.other == [1, 1])
        #expect(UsageMath.chart(daily: [["only": 0]]).series.isEmpty)

        let calls = FakeInstanceCalls()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let model = model(calls, now: now)
        await model.reload()
        let queries = calls.state.withLock { $0.statQueries }
        let days = queries.filter { query in
            guard let start = query.updatedAfter, let end = query.updatedBefore else { return false }
            return end.timeIntervalSince(start) < 36 * 60 * 60
        }
        let period = queries.filter { query in
            guard let start = query.updatedAfter, let end = query.updatedBefore else { return false }
            return end.timeIntervalSince(start) >= 36 * 60 * 60
        }
        let open = queries.filter { $0.updatedAfter == nil && $0.updatedBefore == nil }
        #expect(days.count == 7)
        #expect(days.allSatisfy { $0.grouping == .type })
        #expect(Set(days.map(\.updatedAfter)) .count == 7)
        let today = calendar().startOfDay(for: now)
        #expect(days.map(\.updatedBefore).contains(calendar().date(byAdding: .day, value: 1, to: today)))
        #expect(period.count == 1)
        #expect(period.first?.grouping == .source)
        #expect(open.map(\.grouping).sorted { $0.rawValue < $1.rawValue } == [.source, .type])
    }

    @Test func aLateAnswerDoesNotReplaceThePeriodAskedForSince() async {
        let calls = FakeInstanceCalls()
        calls.holdStats()
        calls.state.withLock {
            $0.dayType = ["core.note": 1]
            $0.allTimeType = ["core.note": 4]
        }
        let model = model(calls)
        let first = Task { await model.reload() }
        #expect(await eventually { calls.waitingStats >= 1 })
        model.period = .last30Days
        calls.admitNewStats()
        await model.reload()
        calls.releaseStats()
        await first.value
        #expect(model.days.count == 30)
        #expect(model.typeRows.first { $0.key == "core.note" }?.changed == 30)
    }

    @Test func metricsFailingStillShowsTheItemCounts() async {
        let calls = FakeInstanceCalls()
        calls.fail("usageMetrics", with: .unreachable)
        calls.state.withLock {
            $0.allTimeType = ["core.note": 3]
            $0.dayType = ["core.note": 1]
        }
        let model = model(calls)
        await model.reload()
        #expect(model.hasStats)
        #expect(!model.hasMetrics)
        #expect(model.metricsFailure == .unreachable)
        #expect(model.storedItems == 3)
        #expect(model.versionCount == nil)
        #expect(model.fileBytes == nil)
        #expect(model.databaseBytes == nil)
        #expect(model.typeRows.first?.changed == 7)
    }

    @Test func aServerThatDoesNotAnswerShowsNoCounts() async {
        let calls = FakeInstanceCalls()
        calls.fail("itemStats", with: .unreachable)
        calls.fail("usageMetrics", with: .unreachable)
        let refreshed = RefreshCount()
        let model = ActivityUsageModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.instanceRead] }, refreshGrants: { refreshed.count += 1 }),
            calls: calls, now: { Date(timeIntervalSince1970: 1_700_000_000) }, calendar: calendar())
        await model.reload()
        #expect(!model.hasStats)
        #expect(!model.hasMetrics)
        #expect(model.storedItems == nil)
        #expect(model.statsFailure == .unreachable)
        #expect(model.typeRows.isEmpty)
        #expect(model.days.count == 7)
        #expect(refreshed.count == 0, "a server that does not answer is not a missing permission")
    }

    @Test func rowsAreMostItemsFirstAndATieIsTheKey() {
        let rows = UsageMath.rows(items: ["b": 2, "a": 2, "c": 9], changed: ["b": 5, "d": 1])
        #expect(rows.map(\.key) == ["c", "a", "b", "d"])
        #expect(rows.first { $0.key == "d" }?.items == 0)
        #expect(rows.first { $0.key == "b" }?.changed == 5)
    }

    @Test func anOlderReadThatWaitsOnGrantsDoesNotOverwriteANewerPeriod() async {
        let calls = FakeInstanceCalls()
        calls.fail("usageMetrics", with: .notPermitted("instance.read"))
        calls.state.withLock {
            $0.allTimeType = ["core.note": 9]
            $0.dayType = ["core.note": 1]
        }
        let pause = StatsPause()
        pause.hold()
        let model = ActivityUsageModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.instanceRead] }, refreshGrants: { await pause.park() }),
            calls: calls, now: { Date(timeIntervalSince1970: 1_700_000_000) }, calendar: calendar())
        model.period = .last30Days
        let first = Task { await model.reload() }
        #expect(await eventually { pause.waiting >= 1 })
        calls.fail("usageMetrics", with: nil)
        model.period = .last7Days
        await model.reload()
        #expect(model.shownPeriod == .last7Days)
        #expect(model.days.count == 7)
        #expect(model.typeRows.first { $0.key == "core.note" }?.changed == 7)
        pause.release()
        await first.value
        #expect(model.shownPeriod == .last7Days)
        #expect(model.days.count == 7)
        #expect(model.typeRows.first { $0.key == "core.note" }?.changed == 7)
    }

    @Test func theWindowIsReadAgainSoItMovesPastMidnight() async {
        let clock = Mutex(Date(timeIntervalSince1970: 1_700_000_000))
        let calls = FakeInstanceCalls()
        let model = ActivityUsageModel(
            context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.instanceRead] }), calls: calls,
            now: { clock.withLock { $0 } }, calendar: calendar())
        await model.reload()
        let first = model.days.first
        clock.withLock { $0 = $0.addingTimeInterval(2 * 86_400) }
        await model.reload()
        #expect(model.days.first != first)
        #expect(model.days.count == 7)
    }

    @Test func changingTheGroupingDoesNotReinterpretTheDays() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock {
            $0.dayType = ["core.note": 1]
            $0.allTimeType = ["core.note": 4]
            $0.periodSource = ["studio": 3]
            $0.allTimeSource = ["studio": 10]
        }
        let model = model(calls)
        await model.reload()
        #expect(model.shownGrouping == .type)
        #expect(model.sourceRows.first { $0.key == "studio" }?.changed == 3)
        #expect(model.chart.series.map(\.key) == ["core.note"])
        model.grouping = .source
        #expect(model.shownGrouping == .type)
        #expect(model.sourceRows.first { $0.key == "studio" }?.changed == 3, "the shown source changes stay the period that was read")
        #expect(model.chart.series.map(\.key) == ["core.note"])
    }

    @Test func aFailedDayKeepsTheAllTimeTotals() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock {
            $0.failDayStats = true
            $0.allTimeType = ["core.note": 4]
            $0.allTimeSource = ["studio": 4]
            $0.periodSource = ["studio": 2]
        }
        let model = model(calls)
        await model.reload()
        #expect(model.storedItems == 4)
        #expect(model.typeRows.first?.items == 4)
        #expect(model.typeRows.first?.changed == nil)
        #expect(model.sourceRows.first { $0.key == "studio" }?.changed == 2)
        #expect(!model.hasDaily)
        #expect(model.hasMetrics)
        #expect(model.statsFailure == .unreachable)
    }

    @Test func storageIsNotReadWithoutInstanceRead() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.reload(items: true, storage: false)
        #expect(!calls.calls.contains("usageMetrics"))
        #expect(calls.calls.contains("itemStats"))
        await model.reload()
        #expect(!calls.calls.contains("usageMetrics"), "Try Again repeats the parts that were asked for")
    }

    @Test func itemCountsFollowTypeAccessAndStorageFollowsInstanceRead() async {
        #expect(ActivityAccess.readsItems(["*:read"]))
        #expect(ActivityAccess.readsItems(["core.note:read"]))
        #expect(ActivityAccess.readsItems(["instance.read", "core.note:read"]))
        #expect(!ActivityAccess.readsItems(["*:write"]))
        #expect(!ActivityAccess.readsItems(["instance.read", "audit.read"]))
        #expect(!ActivityAccess.readsItems(["profile:read", "profile.name:read"]))
        #expect(!ActivityAccess.readsItems(["edge.parent-of:read"]))
        #expect(!ActivityAccess.readsItems(["metadata.edge_types:read"]))
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.reload(items: false, storage: true)
        #expect(!calls.calls.contains("itemStats"))
        #expect(calls.calls.contains("usageMetrics"))
    }
}

@Suite(.hangLimit) @MainActor struct StartUpTests {
    @Test func listsWhatTheServerStartedWithAndNeverAValue() async {
        let calls = FakeInstanceCalls()
        let store = StoredSettings(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.instanceRead] }), calls: calls)
        await store.load()
        let rows = store.snapshot?.startUp ?? []
        #expect(rows.map(\.name) == ["MARFA_PORT", "MARFA_MAX_CONNECTIONS", "MARFA_AUTH_SECRET"])
        #expect(rows.map(\.isSet) == [true, false, true])
        #expect(StartUpWording.what("MARFA_AUTH_SECRET") == "Signs sign-ins. Never shown.")
        #expect(StartUpWording.what("MARFA_FUTURE_THING") == "", "an unknown setting has no invented words")
    }

    @Test func eachNewPageNamesThePermissionItNeeds() {
        #expect(MarfaSettingsPage.activity.permission == nil, "Usage and Log each name their own permission")
        #expect(ActivityTab.log.permission == .auditRead)
        #expect(MarfaSettingsPage.monitoring.permission == .configManage)
        #expect(MarfaSettingsPage.limits.missingPermission(in: [.instanceRead]) == nil)
        #expect(MarfaSettingsPage.limits.missingPermission(in: [.configManage]) == nil)
        #expect(ActivityTab.log.permissionLine == "The app isn’t allowed to read the server’s audit log.")
        #expect(MarfaSettingsPage.monitoring.permissionLine == "The app isn’t allowed to see or change how the server is monitored.")
        #expect(MarfaSettingsPage.limits.permissionLine == "The app isn’t allowed to see or change the server’s limits.")
    }
}
