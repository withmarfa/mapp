import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

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
        /// A refusal the server gives a write, in its words, instead of taking it.
        var refusal: String?
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
            number("max_request_bytes", 1_048_576), number("max_bulk_request_bytes", 16_777_216),
            number("rate_limit_requests", 4000), number("rate_limit_keys_requests", 200), number("rate_limit_window_seconds", 60),
            number("enrichment_max_blob_bytes", 20_971_520), number("enrichment_max_text_chars", 100_000),
            number("enrichment_max_attempts", 3), number("inbound_max_bytes", 26_214_400),
            number("rate_limit_inbound_requests", 600), number("inbound_backlog_deliveries", 10_000),
            number("event_stream_max_viewers", 0), number("mcp_fetch_max_bytes", 52_428_800), number("mcp_fetch_timeout_seconds", 60),
            flag("rate_limit_enabled", true), flag("mcp_fetch_enabled", true), flag("heartbeat_enabled", true),
            flag("error_reporting_enabled", true), flag("telemetry_enabled", true),
            secret("heartbeat_url"), secret("posthog_host"), secret("posthog_project_token"),
            secret("otel_exporter_otlp_endpoint"), secret("otel_exporter_otlp_headers"),
        ]
        return Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })
    }()

    let state = Mutex(State())

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

    static func kind(of action: String) -> ActivityKind {
        switch action.split(separator: ".").first.map(String.init) ?? "" {
        case "auth", "owner", "key": .access
        case "config", "webhook": .settings
        case "items": .housekeeping
        default: .data
        }
    }

    func storedSettings() async throws(OwnerFailure) -> InstanceSettingsSnapshot {
        try enter("storedSettings")
        return state.withLock { InstanceSettingsSnapshot(instanceID: $0.instanceID, settings: $0.settings, startUp: $0.startUp) }
    }

    func change(_ changes: [String: StoredSettingChange], instanceID: String?) async throws(OwnerFailure) {
        try enter("change")
        try state.withLock { state throws(OwnerFailure) in
            state.instanceIDsSent.append(instanceID)
            guard instanceID == nil || instanceID == state.instanceID else { throw .conflict }
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
    @Test func sizesAreShownInMegabytesAndSentInBytes() {
        #expect(LimitSetting.largestRequest.text(for: 1_048_576) == "1")
        #expect(LimitSetting.largestBulkRequest.text(for: 16_777_216) == "16")
        #expect(LimitSetting.largestRequest.text(for: 1_572_864) == "1.5")
        #expect(LimitSetting.largestRequest.entry(from: "2") == .value(2_097_152))
        #expect(LimitSetting.largestRequest.entry(from: "0,5") == .value(524_288), "a comma is a decimal")
        #expect(LimitSetting.requestsPerWindow.text(for: 4000) == "4,000", "thousands are separated, as the board shows them")
        #expect(LimitSetting.mostTextKept.text(for: 100_000) == "100,000")
        #expect(LimitSetting.mostTextKept.entry(from: "100,000") == .value(100_000), "what the field shows can be typed back")
        #expect(LimitSetting.largestRequest.entry(from: "1,024") == .value(1_073_741_824))
        #expect(LimitSetting.requestsPerWindow.entry(from: "4000") == .value(4000))
    }

    @Test func aValueOutOfRangeIsToldBeforeAnythingIsSent() {
        #expect(LimitSetting.largestBulkRequest.entry(from: "33") == .invalid("Use a number above 0, up to 32 MB."))
        #expect(LimitSetting.tries.entry(from: "0") == .invalid("Use a number from 1 to 100 times."))
        #expect(LimitSetting.tries.entry(from: "101") == .invalid("Use a number from 1 to 100 times."))
        #expect(LimitSetting.tries.entry(from: "2.5") == .invalid("Use a whole number."))
        #expect(LimitSetting.tries.entry(from: "three") == .invalid("Use digits only."))
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

    @Test func aRefusedWriteKeepsTheInputWithOneLineInPlainWords() async {
        let calls = FakeInstanceCalls()
        calls.state.withLock { $0.refusal = "`max_request_bytes` can't be less than the bulk limit; PATCH /config refused." }
        let model = limitsModel(calls)
        await model.load()
        model.drafts["max_request_bytes"] = "2"
        await model.commit(.largestRequest)
        #expect(model.text(.largestRequest) == "2", "what was typed stays")
        #expect(model.line(.largestRequest) == "The server refused this change. Nothing was changed.", "no backticks, names or routes")
        #expect(model.hasProblem(.largestRequest))
        calls.state.withLock { $0.refusal = "A request can't be larger than the bulk limit." }
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
        #expect(model.notice == "This changed somewhere else, so MAPP read it again. Nothing was changed.")
    }

    @Test func anotherInstanceAnsweringIsToldAndNothingIsWritten() async {
        let calls = FakeInstanceCalls()
        let model = limitsModel(calls)
        await model.load()
        calls.state.withLock { $0.instanceID = "instance-2" }
        model.drafts["enrichment_max_attempts"] = "4"
        await model.commit(.tries)
        #expect(calls.sent.isEmpty)
        #expect(model.notice != nil)
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
        #expect(model.line(.tries) == OwnerWording.permissionLine("config.manage"))
        #expect(model.text(.tries) == "4", "the input stays")
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

    @Test func whatWasTypedAndNotSentIsHandedBackWhenSettingsCloses() async {
        let model = limitsModel()
        await model.load()
        model.drafts["max_request_bytes"] = "9"
        model.drafts["enrichment_max_attempts"] = "3"
        #expect(model.takeDrafts() == [.typed(title: "Largest Request", text: "9")], "a value the server already holds is no draft")
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

        model.begin(.heartbeatAddress)
        #expect(model.canRemove(model.sheet!))
        await model.remove()
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
        #expect(model.removalNote(model.sheet!) != nil)
        await model.remove()
        #expect(Set(calls.sent.last?.keys.map { $0 } ?? []) == ["posthog_host", "posthog_project_token"])
        #expect(!model.isSet(.postHogHost) && !model.isSet(.postHogToken))
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

    @Test func wordsAreMAPPsAndNeverTheServersKeys() {
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
        #expect(MarfaSettingsPage.activity.permission == .auditRead)
        #expect(MarfaSettingsPage.monitoring.permission == .configManage)
        #expect(MarfaSettingsPage.limits.permission == .configManage)
        #expect(MarfaSettingsPage.startUp.permission == .instanceRead)
        #expect(MarfaSettingsPage.activity.permissionLine == "MAPP isn’t allowed to read the audit log.")
    }
}
