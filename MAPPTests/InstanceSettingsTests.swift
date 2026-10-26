import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A server's settings held in memory: it answers as the real one does, taking a patch field by field, and keeps
/// what it was sent.
nonisolated final class FakeInstanceConfig: InstanceConfigSource {
    let config: Mutex<InstanceConfig>
    let readFailure = Mutex<InstanceConfigFailure?>(nil)
    let updateFailure = Mutex<InstanceConfigFailure?>(nil)
    let patches = Mutex<[InstanceConfigPatch]>([])
    /// The instance each change said it expected.
    let expected = Mutex<[String?]>([])
    /// Run as a change arrives, to let a test move the server under it.
    let beforeUpdate = Mutex<(@Sendable () -> Void)?>(nil)

    init(_ values: [InstanceSetting: InstanceValue] = [:], instanceID: String = "instance-1") {
        config = Mutex(InstanceConfig(values: values, instanceID: instanceID))
    }

    func read() async throws(InstanceConfigFailure) -> InstanceConfig {
        if let failure = readFailure.withLock({ $0 }) { throw failure }
        return config.withLock { $0 }
    }

    func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig {
        patches.withLock { $0.append(patch) }
        expected.withLock { $0.append(instanceID) }
        beforeUpdate.withLock { $0 }?()
        if let failure = updateFailure.withLock({ $0 }) { throw failure }
        return try config.withLock { (config) throws(InstanceConfigFailure) in
            if let instanceID, instanceID != config.instanceID { throw .instanceChanged }
            for (setting, value) in patch.values { config.values[setting] = value }
            for setting in patch.clear { config.values[setting] = nil }
            return config
        }
    }

    var sent: [InstanceConfigPatch] { patches.withLock { $0 } }
}

@MainActor
@Suite struct InstanceSettingsTests {
    private func model(_ source: FakeInstanceConfig, id: String = "https://marfa.test") -> InstanceSettingsModel {
        InstanceSettingsModel { .init(id: id, source: source) }
    }

    private func loaded(_ values: [InstanceSetting: InstanceValue] = [:]) async -> (InstanceSettingsModel, FakeInstanceConfig) {
        let source = FakeInstanceConfig(values)
        let model = model(source)
        await model.load()
        return (model, source)
    }

    @Test func aSaveSendsOnlyTheFieldsThatChangedAndShowsTheAnswer() async {
        let (model, source) = await loaded([.name: .text("Library"), .trashRetentionDays: .number(30)])
        var renamed = 0
        model.onRenamed = { renamed += 1 }
        #expect(model.draft[.name] == "Library")

        model.draft[.name] = "  Home  "
        await model.save()

        #expect(source.sent == [InstanceConfigPatch(values: [.name: .text("Home")])])
        #expect(model.draft[.name] == "Home")
        #expect(model.saved == ["Name: Home"])
        #expect(renamed == 1)
        #expect(!model.canSave)
    }

    @Test func anEmptyFieldRemovesTheSettingSoItsDefaultApplies() async {
        let (model, source) = await loaded([.versionMaxVersions: .number(50), .name: .text("Library")])
        model.draft[.versionMaxVersions] = " "
        await model.save()
        // The default that replaces 50 is not known, so the person agrees first.
        #expect(source.sent.isEmpty)
        if let pending = model.pending { await model.confirm(pending) }
        #expect(source.sent == [InstanceConfigPatch(clear: [.versionMaxVersions])])
        #expect(model.loaded?.values[.versionMaxVersions] == nil)
        #expect(model.saved == ["Most versions kept per item: default, 500"])
    }

    @Test func whatTheContractRefusesIsRefusedBeforeAnythingIsSent() async {
        let (model, source) = await loaded()
        model.draft[.trashRetentionDays] = "-1"
        model.draft[.versionRecentDays] = "36501"
        model.draft[.versionMaxVersions] = "0"
        model.draft[.name] = String(repeating: "a", count: 201)
        #expect(model.problems[.trashRetentionDays] == .notWhole)
        #expect(model.problems[.versionRecentDays] == .outOfRange(0...36500))
        #expect(model.problems[.versionMaxVersions] != nil)
        #expect(model.problems[.name] == .nameTooLong)
        model.draft[.name] = "Home\u{202E}"
        #expect(model.problems[.name] == .nameHidden)
        #expect(!model.canSave)
        await model.save()
        #expect(source.sent.isEmpty)

        model.revert()
        model.draft[.versionRecentDays] = "100"
        model.draft[.versionDailyDays] = "50"
        #expect(model.problems[.versionDailyDays] == .shorterThan(.versionRecentDays))
    }

    @Test func aShorterRetentionWaitsForTheirAgreementAndNothingElseDoes() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60)])

        model.draft[.trashRetentionDays] = "7"
        await model.save()
        #expect(source.sent.isEmpty)
        #expect(model.pending?.shortenings == [.init(setting: .trashRetentionDays, change: .shorter(from: 60, to: 7))])
        model.cancelPending()
        #expect(source.sent.isEmpty)

        await model.save()
        if let pending = model.pending { await model.confirm(pending) }
        #expect(source.sent == [InstanceConfigPatch(values: [.trashRetentionDays: .number(7)])])

        // Longer, and no limit at all, ask nothing.
        model.draft[.trashRetentionDays] = "0"
        await model.save()
        #expect(model.pending == nil)
        #expect(source.sent.count == 2)
    }

    /// What `save` would ask about for `typed` on a server that holds `held`.
    private func asked(_ held: [InstanceSetting: InstanceValue], _ typed: [InstanceSetting: String]) async -> [InstanceSettingsModel.Shortening] {
        let (model, _) = await loaded(held)
        for (setting, text) in typed { model.draft[setting] = text }
        await model.save()
        return model.pending?.shortenings ?? []
    }

    @Test func aValueTypedForAnUnsetRetentionAsksBecauseTheServersDefaultIsNotKnown() async {
        // A server whose environment sets a default of 365 days of trash would lose items sooner at 100.
        #expect(await asked([:], [.trashRetentionDays: "100"]) == [.init(setting: .trashRetentionDays, change: .mayBeShorter(to: 100))])
        // Even a value longer than the documented default, and one equal to it.
        #expect(await asked([:], [.trashRetentionDays: "90"]).count == 1)
        #expect(await asked([:], [.trashRetentionDays: "60"]).count == 1)
        #expect(await asked([:], [.versionWeeklyDays: "400"]) == [.init(setting: .versionWeeklyDays, change: .mayBeShorter(to: 400))])
        #expect(await asked([:], [.versionMaxVersions: "900"]) == [.init(setting: .versionMaxVersions, change: .mayBeShorter(to: 900))])
        // A zero window is empty, so it is the least a window keeps.
        #expect(await asked([:], [.versionRecentDays: "0"]).count == 1)
    }

    @Test func aValueNothingCouldOutlastAsksNothing() async {
        #expect(await asked([:], [.trashRetentionDays: "0"]).isEmpty)
        #expect(await asked([:], [.trashRetentionDays: "36500"]).isEmpty)
        #expect(await asked([:], [.versionRecentDays: "36500", .versionDailyDays: "36500", .versionWeeklyDays: "36500"]).isEmpty)
        #expect(await asked([:], [.versionMaxVersions: "9007199254740991"]).isEmpty)
        #expect(await asked([:], [.name: "Home"]).isEmpty)
    }

    @Test func clearingASetRetentionAsksAndNamesNoDefault() async {
        let shortenings = await asked([.trashRetentionDays: .number(45), .versionMaxVersions: .number(50)], [.trashRetentionDays: "", .versionMaxVersions: " "])
        #expect(shortenings == [
            .init(setting: .trashRetentionDays, change: .toDefault(from: 45)),
            .init(setting: .versionMaxVersions, change: .toDefault(from: 50)),
        ])
        let words = shortenings.map(InstanceWording.consequence)
        #expect(words[0].contains("may remove items sooner than the server’s current setting"))
        #expect(words[0].contains("45 days"))
        #expect(!words[0].contains("60"))
        #expect(!words[1].contains("500"))
    }

    @Test func clearingASettingThatCannotKeepLessAsksNothing() async {
        #expect(await asked([.versionRecentDays: .number(0)], [.versionRecentDays: ""]).isEmpty)
        #expect(await asked([.trashRetentionDays: .number(1)], [.trashRetentionDays: ""]).isEmpty)
        #expect(await asked([.versionMaxVersions: .number(1)], [.versionMaxVersions: ""]).isEmpty)
        // No limit on trash keeps the most, so any default may keep less.
        #expect(await asked([.trashRetentionDays: .number(0)], [.trashRetentionDays: ""]).count == 1)
    }

    @Test func aSetRetentionIsComparedWithWhatTheServerHolds() async {
        #expect(await asked([.trashRetentionDays: .number(60)], [.trashRetentionDays: "59"]) == [.init(setting: .trashRetentionDays, change: .shorter(from: 60, to: 59))])
        #expect(await asked([.trashRetentionDays: .number(30)], [.trashRetentionDays: "60"]).isEmpty)
        #expect(await asked([.trashRetentionDays: .number(30)], [.trashRetentionDays: "30"]).isEmpty)
        #expect(await asked([.trashRetentionDays: .number(30)], [.trashRetentionDays: "0"]).isEmpty)
        #expect(await asked([.trashRetentionDays: .number(0)], [.trashRetentionDays: "30"]).count == 1)
        #expect(await asked([.versionMaxVersions: .number(100)], [.versionMaxVersions: "99"]).count == 1)
    }

    @Test func theWordsSayAnUnknownSettingMayRemoveItemsSooner() {
        let typed = InstanceSettingsModel.Shortening(setting: .trashRetentionDays, change: .mayBeShorter(to: 100))
        let words = InstanceWording.consequence(typed)
        #expect(words.contains("may remove items sooner than the server’s current setting"))
        #expect(words.contains("100 days"))
        let known = InstanceWording.consequence(.init(setting: .trashRetentionDays, change: .shorter(from: 60, to: 7)))
        #expect(!known.contains("sooner than"))
    }

    @Test func aSettingChangedElsewhereIsShownAndNotOverwritten() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        source.config.withLock { $0.values[.name] = .text("Office") }

        await model.save()

        #expect(source.sent.isEmpty)
        #expect(model.elsewhere == [.name])
        #expect(model.loaded?.name == "Office")
        #expect(model.draft[.name] == "Home")
        #expect(model.elsewhereMessage?.contains("Office") == true)
    }

    @Test func aKeyWithoutPermissionSeesNoSettings() async {
        let source = FakeInstanceConfig()
        source.readFailure.withLock { $0 = .notPermitted }
        let model = model(source)
        await model.load()
        #expect(model.loaded == nil)
        #expect(model.failure == .notPermitted)
        #expect(!model.isAvailable)
    }

    @Test func aKeyThatLosesPermissionHidesTheFieldsButKeepsWhatWasTyped() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        source.readFailure.withLock { $0 = .notPermitted }
        await model.load()
        #expect(model.failure == .notPermitted)
        #expect(!model.isAvailable)
        #expect(!model.canSave)
        #expect(model.isEdited(.name))
        #expect(model.draft[.name] == "Home")

        // Once the key may manage the settings again, the next read keeps the draft and takes the rest.
        source.readFailure.withLock { $0 = nil }
        source.config.withLock { $0.values[.trashRetentionDays] = .number(20) }
        await model.load()
        #expect(model.isAvailable)
        #expect(model.draft[.name] == "Home")
        #expect(model.draft[.trashRetentionDays] == "20")
        #expect(model.patch == InstanceConfigPatch(values: [.name: .text("Home")]))
    }

    @Test func aSaveThatMeetsAKeyWithoutPermissionKeepsWhatWasTyped() async {
        let (model, source) = await loaded([.name: .text("Library")])
        source.updateFailure.withLock { $0 = .notPermitted }
        model.draft[.name] = "Home"
        await model.save()
        #expect(model.failure == .notPermitted)
        #expect(!model.isAvailable)
        #expect(model.draft[.name] == "Home")
        #expect(model.isEdited(.name))
    }

    @Test func aServerThatCannotBeReachedKeepsTheLastAnswerAndWhatWasTyped() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        source.readFailure.withLock { $0 = .unreachable }
        await model.load()
        #expect(model.failure == .unreachable)
        #expect(model.loaded?.name == "Library")
        #expect(model.draft[.name] == "Home")

        // Saving offline fails the same way, and nothing is sent.
        await model.save()
        #expect(model.failure == .unreachable)
        #expect(source.sent.isEmpty)
    }

    @Test func aRefusedValueKeepsWhatWasTypedAndSaysWhy() async {
        let (model, source) = await loaded([.name: .text("Library")])
        source.updateFailure.withLock { $0 = .refused("The name is not allowed.") }
        model.draft[.name] = "Home"
        await model.save()
        #expect(model.failure == .refused("The name is not allowed."))
        #expect(model.draft[.name] == "Home")
        #expect(model.loaded?.name == "Library")
        #expect(model.canSave)
    }

    @Test func aChangeAgreedToForOneServerIsNotSentToAnotherThatReplacedIt() async {
        let first = FakeInstanceConfig([.trashRetentionDays: .number(60)])
        let second = FakeInstanceConfig([.trashRetentionDays: .number(60)])
        var current = (id: "one", source: first)
        let model = InstanceSettingsModel { .init(id: current.id, source: current.source) }
        await model.load()
        model.draft[.trashRetentionDays] = "7"
        await model.save()
        guard let pending = model.pending else { Issue.record("a shorter retention should ask first"); return }

        // The dialog is open when the connection moves to another server.
        current = (id: "two", source: second)
        await model.confirm(pending)

        #expect(first.sent.isEmpty)
        #expect(second.sent.isEmpty)
        #expect(model.loaded == nil)
        #expect(model.draft.isEmpty)
        #expect(!model.isSaving)
    }

    @Test func aChangeIsAddressedToTheInstanceThePageWasReadFrom() async {
        let (model, source) = await loaded([.name: .text("Library")])
        #expect(model.loaded?.instanceID == "instance-1")
        model.draft[.name] = "Home"
        await model.save()
        #expect(source.expected == ["instance-1"])
    }

    @Test func anotherInstanceAnsweringAtTheAddressRefusesTheChangeAndTheModelStartsAgain() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        // Between the read before sending and the change, another instance takes the address.
        source.beforeUpdate.withLock { [source] in
            $0 = { source.config.withLock { $0 = InstanceConfig(values: [.name: .text("Elsewhere")], instanceID: "instance-2") } }
        }

        await model.save()

        #expect(source.expected == ["instance-1"])
        #expect(source.config.withLock { $0.name } == "Elsewhere")
        #expect(model.serverChanged)
        #expect(model.failure == nil)
        #expect(model.loaded?.instanceID == "instance-2")
        #expect(model.draft[.name] == "Elsewhere")
        #expect(!model.hasEdits)
        #expect(!model.isSaving)
        // The next save starts from the new instance.
        source.beforeUpdate.withLock { $0 = nil }
        model.draft[.name] = "Home"
        await model.save()
        #expect(!model.serverChanged)
        #expect(source.expected.last == "instance-2")
        #expect(source.config.withLock { $0.name } == "Home")
    }

    @Test func anInstanceThatAnsweredDifferentlyBeforeTheChangeIsNotWrittenTo() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        source.config.withLock { $0 = InstanceConfig(values: [.name: .text("Library")], instanceID: "instance-2") }

        await model.save()

        #expect(source.sent.isEmpty)
        #expect(model.serverChanged)
        #expect(model.loaded?.instanceID == "instance-2")
        #expect(model.draft[.name] == "Library")
    }

    @Test func anotherServerStartsFromNothing() async {
        let first = FakeInstanceConfig([.name: .text("One")])
        let second = FakeInstanceConfig([.name: .text("Two")])
        var current = (id: "one", source: first)
        let model = InstanceSettingsModel { .init(id: current.id, source: current.source) }
        await model.load()
        model.draft[.name] = "Typed for one"
        current = (id: "two", source: second)
        await model.load()
        #expect(model.loaded?.name == "Two")
        #expect(model.draft[.name] == "Two")
    }
}

/// What goes on the wire, and how the server's refusals are told.
@Suite struct MarfaServerConfigTests {
    @Test func theBodyNamesOnlyTheChangedSettingsAndNullRemovesOne() throws {
        let patch = InstanceConfigPatch(values: [.name: .text("Home"), .versionMaxVersions: .number(200)], clear: [.trashRetentionDays])
        let data = try JSONEncoder().encode(MarfaServerConfig.payload(patch))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(json.keys) == ["name", "version_max_versions", "trash_retention_days"])
        #expect(json["name"] as? String == "Home")
        #expect(json["version_max_versions"] as? Int == 200)
        #expect(json["trash_retention_days"] is NSNull)
    }

    @Test func theChangeNamesTheInstanceItExpects() {
        let patch = InstanceConfigPatch(values: [.name: .text("Home")])
        #expect(MarfaServerConfig.input(patch, expecting: "0197a7d6-0000-7000-8000-000000000000").headers.xMarfaInstanceId == "0197a7d6-0000-7000-8000-000000000000")
        #expect(MarfaServerConfig.input(patch, expecting: nil).headers.xMarfaInstanceId == nil)
    }

    @Test func aRefusalForAnotherInstanceIsTold() {
        #expect(MarfaServerConfig.failure(MarfaError.server(status: 409, code: "instance_changed", message: "other")) == .instanceChanged)
        #expect(MarfaServerConfig.failure(MarfaError.server(status: 409, code: "version_conflict", message: "stale")) == .failed("stale"))
    }

    @Test func aRefusalGivesTheServersReasonWithoutItsDetails() {
        let error = MarfaError.validation(code: "invalid_config", message: "Windows must not decrease. Details: {\"x\":1}")
        #expect(MarfaServerConfig.failure(error) == .refused("Windows must not decrease."))
        #expect(MarfaServerConfig.failure(MarfaError.forbidden(code: "forbidden", message: "no")) == .notPermitted)
    }
}
