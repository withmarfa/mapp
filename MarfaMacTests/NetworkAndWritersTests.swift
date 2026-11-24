import Foundation
import Marfa
import MarfaAPI
import Synchronization
import Testing
@testable import MarfaMac

/// Who May Write (`enforcement.source_allowlist`) and Private Addresses (`allow_private_addresses`): both change who may reach
/// or write to the owner's Marfa, so each write is held to the levers and the setting as they were read.
@MainActor
@Suite(.hangLimit) struct WhoMayWriteTests {
    private let rows = [OwnerSource(code: "readwise", name: "Readwise"), OwnerSource(code: "rss", name: "RSS")]

    private let read = SourceLimit(
        instanceID: "instance-1", isOn: true, types: ["core.highlight"], sources: ["readwise"], strictTypes: ["core.task"],
        allowlist: (["core.note"], ["rss"]))

    private static func key(_ source: String, claims: [String] = [], expires: Date? = nil) -> KeyInfo {
        KeyInfo(id: "key-" + source, label: source, source: source, permissions: [], tier: .library, types: [:], expires: expires, claims: claims)
    }

    private func model(_ bench: OwnerBench) -> SourceLimitModel {
        bench.calls.state.withLock { [rows] in
            $0.sources = rows
            $0.keys = [Self.key("readwise"), Self.key("rss")]
        }
        return SourceLimitModel(rule: .allowlist, context: bench.context)
    }

    /// Each rule is written through the one enforcement writer, which sends the other levers as it read them.
    @Test func eachRuleIsSentWithTheOtherLeversAsTheyWereRead() async throws {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { [read] in $0.sourceLimit = read }
        let writers = model(bench)
        await writers.load()
        writers.types = ["core.bookmark"]
        writers.checkedSources = ["readwise"]
        await writers.save()
        let allowlist = try #require(bench.calls.state.withLock { $0.leversSent.last })
        let allowlistBody = try #require(ClientOwnerCalls.enforcement(allowlist).value)
        #expect(allowlistBody.sourceAllowlist?.types == ["core.bookmark"])
        #expect(allowlistBody.sourceAllowlist?.sources == ["readwise"])
        #expect(allowlistBody.sourceFilter?.types == ["core.highlight"])
        #expect(allowlistBody.sourceFilter?.sources == ["readwise"])
        #expect(allowlistBody.strictMode?.types == ["core.task"])

        let limit = SourceLimitModel(rule: .filter, context: bench.context)
        await limit.load()
        await limit.turnOff()
        let filter = try #require(bench.calls.state.withLock { $0.leversSent.last })
        let filterBody = try #require(ClientOwnerCalls.enforcement(filter).value)
        #expect(filterBody.sourceFilter == nil)
        #expect(filterBody.sourceAllowlist?.types == ["core.bookmark"])
        #expect(filterBody.sourceAllowlist?.sources == ["readwise"])
        #expect(filterBody.strictMode?.types == ["core.task"])

        // Turning off the last lever sends no enforcement at all.
        let alone = SourceLimit(instanceID: "instance-1", isOn: false, types: [], sources: [], strictTypes: nil, allowlist: nil)
        #expect(ClientOwnerCalls.enforcement(alone) == .null)
    }

    @Test func savingSendsTheAllowListAndLeavesLimitSourcesAsItWas() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { [read] in $0.sourceLimit = read }
        let model = model(bench)
        await model.load()
        #expect(model.types == ["core.note"])
        #expect(model.checkedSources == ["rss"])
        model.types = ["core.note", "core.bookmark"]
        model.checkedSources = ["rss", "readwise"]
        await model.save()

        let sent = bench.calls.state.withLock { $0.allowlistsSent }
        let held = bench.calls.state.withLock { $0.sourceLimit }
        #expect(sent == [SourceRuleValue(types: ["core.bookmark", "core.note"], sources: ["readwise", "rss"])])
        #expect(held.value(of: .filter) == SourceRuleValue(types: ["core.highlight"], sources: ["readwise"]))
        #expect(held.strictTypes == ["core.task"])
        #expect(!model.hasEdits)
    }

    @Test func anotherLeverChangedElsewhereIsSentAsItNowIsAndNotWrittenOver() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { [read] in $0.sourceLimit = read }
        let model = model(bench)
        await model.load()
        model.checkedSources = ["rss", "readwise"]
        // Another app changes Limit Sources and a type's Strict switch after the page read the levers.
        bench.calls.state.withLock {
            $0.sourceLimit.sources = ["readwise", "rss"]
            $0.sourceLimit.strictTypes = ["core.task", "user.job"]
        }
        await model.save()

        #expect(bench.calls.state.withLock { $0.allowlistsSent } == [SourceRuleValue(types: ["core.note"], sources: ["readwise", "rss"])])
        let held = bench.calls.state.withLock { $0.sourceLimit }
        #expect(held.value(of: .filter) == SourceRuleValue(types: ["core.highlight"], sources: ["readwise", "rss"]))
        #expect(held.strictTypes == ["core.task", "user.job"])
        #expect(model.line == nil)
    }

    @Test func theAllowListChangedElsewhereIsToldByName() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { [read] in $0.sourceLimit = read }
        let model = model(bench)
        await model.load()
        model.checkedSources = ["rss", "readwise"]
        bench.calls.state.withLock { $0.sourceLimit.allowlist = (["core.note"], ["github"]) }
        await model.save()

        #expect(bench.calls.state.withLock { $0.leversSent.isEmpty })
        #expect(model.line?.hasPrefix("Who May Write was changed somewhere else") == true)
        #expect(model.value?.sources == ["github"])
    }

    @Test func aListNoCurrentKeyOrAppWritesUnderIsRefused() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench)
        bench.calls.state.withLock {
            $0.sources = [OwnerSource(code: "restored:oauth:old-app", name: "Old App")]
            $0.keys = [Self.key("connector-host:host-1"), Self.key("ended", expires: .distantPast)]
        }
        await model.load()
        model.types = ["core.note"]
        model.checkedSources = ["restored:oauth:old-app", "connector-host:host-1", "ended"]
        #expect(model.waitsFor != nil)
        #expect(!model.canSave)
        await model.save()
        #expect(bench.calls.state.withLock { $0.leversSent.isEmpty })
    }

    @Test func theChoicesHoldKeysAndAppsThatHaveWrittenNothingAndALimitedSource() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench)
        bench.calls.state.withLock {
            $0.keys = [Self.key("readwise", claims: ["shared"])]
            $0.apps = [AppAccess(id: "grant-1", clientID: "client-1", kind: .app, name: "Sketches", origins: [], scopes: [])]
        }
        await model.load()
        let codes = Set(model.sourceChoices.map(\.code))
        #expect(codes == ["readwise", "rss", "shared", "oauth:client-1"])
        #expect(model.sourceChoices.contains { $0.code == "oauth:client-1" && $0.title == "Sketches" })
    }

    @Test func aWriterEndedSinceTheReadIsFoundAtSaveAndNothingIsSent() async {
        let bench = OwnerBench(grants: [.configManage])
        bench.calls.state.withLock { [read] in $0.sourceLimit = read }
        let model = model(bench)
        await model.load()
        model.checkedSources = ["readwise"]
        #expect(model.canSave)
        bench.calls.state.withLock { $0.keys = [Self.key("rss")] }
        await model.save()
        #expect(bench.calls.state.withLock { $0.leversSent.isEmpty })
        #expect(model.line != nil)
        #expect(model.checkedSources == ["readwise"])
    }

    @Test func aListThatWouldLetNoSourceWriteIsRefusedWithAReason() async {
        let bench = OwnerBench(grants: [.configManage])
        let model = model(bench)
        await model.load()
        model.types = ["core.note"]
        #expect(model.waitsFor != nil)
        #expect(!model.canSave)
        await model.save()
        #expect(bench.calls.state.withLock { $0.leversSent.isEmpty })
    }
}

@MainActor
@Suite(.hangLimit) struct PrivateAddressesTests {
    private func model(_ calls: FakeInstanceCalls) -> PrivateAddressesModel {
        PrivateAddressesModel(context: OwnerContext(calls: FakeOwnerCalls(), grants: { [.configManage] }), calls: calls)
    }

    @Test func turningItOnAsksFirstAndSendsOnlyOnceAllowed() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.load()
        await model.set(true)
        #expect(model.asksToAllow)
        #expect(calls.sent.isEmpty)
        #expect(!model.isOn)

        await model.allow()
        #expect(calls.sent == [[PrivateAddressesModel.key: .set(.bool(true))]])
        #expect(calls.state.withLock { $0.instanceIDsSent } == ["instance-1"])
        #expect(model.isOn)
    }

    @Test func aChangeMadeElsewhereIsToldAndNotWrittenOver() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        await model.load()
        calls.changeElsewhere(PrivateAddressesModel.key, to: .bool(true))
        await model.set(true)
        await model.allow()
        #expect(calls.sent.isEmpty)
        #expect(model.notice?.contains("Private Addresses was changed elsewhere") == true)
        #expect(model.isOn)
    }

    @Test func aRefusedTurnOffKeepsTheSwitchAsTheServerHoldsIt() async {
        let calls = FakeInstanceCalls()
        let model = model(calls)
        calls.state.withLock { $0.settings[PrivateAddressesModel.key]?.value = .bool(true) }
        await model.load()
        let line = "The heartbeat address isn’t public. Change it first, then turn this off."
        calls.state.withLock { $0.refusal = line }
        await model.set(false)
        #expect(model.isOn)
        #expect(model.line == line)
    }

    @Test func theServersRefusalNamesEachDestinationByItsName() {
        let refusal = MarfaError.validation(
            code: "validation_error", message: "The settings cannot be used together",
            details: [
                "errors": [
                    ["path": "heartbeat_url", "message": "names an address that is not public; allow one by setting allow_private_addresses"],
                    ["path": "object_store_endpoint", "message": "names an address that is not public; allow one by setting allow_private_addresses"],
                ]
            ], server: nil)
        #expect(StoredSettingWording.notPublic(refusal) == "The heartbeat address and object store address aren’t public. Change them first, then turn this off.")
        let other = MarfaError.validation(
            code: "validation_error", message: "The settings cannot be used together",
            details: ["errors": [["path": "posthog_host", "message": "needs posthog_project_token"]]], server: nil)
        #expect(StoredSettingWording.notPublic(other) == nil)
    }
}
