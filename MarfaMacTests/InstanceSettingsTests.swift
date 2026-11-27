import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

// The package names the same things; these tests mean the app's.
typealias InstanceConfig = MarfaMac.InstanceConfig
typealias InstanceConfigPatch = MarfaMac.InstanceConfigPatch

/// A server's settings held in memory: it answers as the real one does, taking a patch field by field, and keeps
/// what it was sent.
nonisolated final class FakeInstanceConfig: InstanceConfigSource {
    let config: Mutex<InstanceConfig>
    let readFailure = Mutex<InstanceConfigFailure?>(nil)
    let updateFailure = Mutex<InstanceConfigFailure?>(nil)
    let patches = Mutex<[InstanceConfigPatch]>([])
    /// The instance each change said it expected.
    let expectations = Mutex<[String?]>([])
    /// Run as a change arrives, to let a test move the server under it.
    let beforeUpdate = Mutex<(@Sendable () -> Void)?>(nil)
    /// Whether the next read holds its answer, and the reads holding theirs until `answerHeldReads`.
    private let heldReads = Mutex((holdsNext: false, waiting: [CheckedContinuation<Void, Never>]()))

    init(_ values: [InstanceSetting: InstanceValue] = [:], instanceID: String = "instance-1") {
        config = Mutex(InstanceConfig(values: values, instanceID: instanceID))
    }

    func read() async throws(InstanceConfigFailure) -> InstanceConfig {
        if let failure = readFailure.withLock({ $0 }) { throw failure }
        let answer = config.withLock { $0 }
        await withCheckedContinuation { waiter in
            let holds = heldReads.withLock { reads in
                guard reads.holdsNext else { return false }
                reads.holdsNext = false
                reads.waiting.append(waiter)
                return true
            }
            if !holds { waiter.resume() }
        }
        return answer
    }

    /// The next read takes the settings as they are and holds its answer until `answerHeldReads`.
    func holdNextRead() {
        heldReads.withLock { $0.holdsNext = true }
    }

    var holdsARead: Bool { heldReads.withLock { !$0.waiting.isEmpty } }

    func answerHeldReads() {
        let waiting = heldReads.withLock { reads in
            defer { reads.waiting = [] }
            return reads.waiting
        }
        for waiter in waiting { waiter.resume() }
    }

    func update(_ patch: InstanceConfigPatch, expecting instanceID: String?) async throws(InstanceConfigFailure) -> InstanceConfig {
        patches.withLock { $0.append(patch) }
        expectations.withLock { $0.append(instanceID) }
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
    var expected: [String?] { expectations.withLock { $0 } }
}

@MainActor
@Suite(.hangLimit) struct InstanceSettingsTests {
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
        model.onSaved = { _, settings, _ in if settings.contains(.name) { renamed += 1 } }
        #expect(model.draft[.name] == "Library")

        model.draft[.name] = "  Home  "
        await model.save()

        #expect(source.sent == [InstanceConfigPatch(values: [.name: .text("Home")])])
        #expect(model.draft[.name] == "Home")
        #expect(model.saved == ["Name: Home"])
        #expect(renamed == 1)
        #expect(!model.canSave)
    }

    @Test func rejectedRetentionChoicesShowTheAppliedValue() async throws {
        let (model, source) = await loaded([.versionDailyDays: .number(30), .versionWeeklyDays: .number(90)])
        await model.choose(7, for: .versionWeeklyDays, defaultValue: 365)
        #expect(model.draft[.versionWeeklyDays] == "90")
        #expect(model.failure != nil)
        #expect(model.pending == nil)
        await model.choose(60, for: .versionWeeklyDays, defaultValue: 365)
        let pending = try #require(model.pending)
        source.config.withLock { $0.values[.versionWeeklyDays] = .number(180) }
        await model.load()
        await model.confirm(pending)
        #expect(model.draft[.versionWeeklyDays] == "180")
        #expect(model.elsewhereMessage?.contains("Then one a week up to: 180 days") == true)
        #expect(source.sent.isEmpty)
    }

    @Test func retentionChoicesCompareTheEffectiveValuesIncludingWhenCleared() async {
        for (stored, standard, choice, asks) in [
            (nil, 90, 60, true), (nil, 14, 60, false), (nil, 0, 36500, true),
            (60, 90, nil, false), (60, 14, nil, true), (60, 0, nil, false), (0, 90, nil, true),
        ] as [(Int?, Int, Int?, Bool)] {
            let (model, source) = await loaded(stored.map { [.trashRetentionDays: .number($0)] } ?? [:])
            await model.choose(choice, for: .trashRetentionDays, defaultValue: standard)
            #expect((model.pending != nil) == asks)
            #expect(source.sent.isEmpty == asks)
        }
    }

    @Test(arguments: [InstanceSetting.versionWeeklyDays, .versionRecentDays])
    func lengtheningAVersionWindowWaitsForConfirmation(setting: InstanceSetting) async throws {
        let allZero = setting == .versionWeeklyDays
        let (model, source) = await loaded([
            .versionRecentDays: .number(0), .versionDailyDays: .number(allZero ? 0 : 7),
            .versionWeeklyDays: .number(allZero ? 0 : 30), .versionMaxVersions: .number(3),
        ])
        await model.choose(7, for: setting, defaultValue: nil)
        #expect(source.sent.isEmpty)
        let pending = try #require(model.pending)
        #expect(pending.shortenings.map(InstanceWording.consequence) == ["The server may permanently remove older versions at its next cleanup."])
        #expect(InstanceSettingsQuestion.button(pending) == "Change and Save")
        await model.confirm(pending)
        #expect(source.sent == [.init(values: [setting: .number(7)])])
    }

    @Test func raisingOnlyTheVersionCapSavesImmediately() async {
        let (model, source) = await loaded([.versionMaxVersions: .number(3)])
        await model.choose(4, for: .versionMaxVersions, defaultValue: nil)
        #expect(model.pending == nil)
        #expect(source.sent == [.init(values: [.versionMaxVersions: .number(4)])])
    }

    @Test func extendingAllWindowsAndRaisingTheCapStillAsksOnce() async throws {
        let (model, source) = await loaded([.versionMaxVersions: .number(3)])
        for setting in InstanceSetting.versionWindows { model.draft[setting] = "36500" }
        model.draft[.versionMaxVersions] = "4"
        await model.save()
        #expect(source.sent.isEmpty)
        let pending = try #require(model.pending)
        #expect(pending.shortenings.map(\.setting) == InstanceSetting.versionWindows)
        #expect(InstanceSettingsQuestion.message(pending) == "The server may permanently remove older versions at its next cleanup.")
        model.cancelPending()
        #expect(source.sent.isEmpty)
        #expect(!model.hasEdits)
    }

    @Test(arguments: [90, nil] as [Int?])
    func aRetentionClearedElsewhereShowsTheServerDefault(standard: Int?) async throws {
        let (model, source) = await loaded([.trashRetentionDays: .number(30)])
        await model.choose(7, for: .trashRetentionDays, defaultValue: standard)
        let pending = try #require(model.pending)
        source.config.withLock { $0.values[.trashRetentionDays] = nil }
        await model.confirm(pending)
        #expect(source.sent.isEmpty)
        let message = try #require(model.elsewhereMessage)
        #expect(message.contains(standard == nil ? "Default." : "Default (90 days)."))
        #expect(!message.contains("60"))
    }

    @Test func aRefusedDiskReserveReturnsTheTypedTextAndShowsTheAppliedValue() async {
        let (model, source) = await loaded([.diskReserveMegabytes: .number(128)])
        var returned: [OwnerDraft] = []
        model.returnDraft = { returned.append($0) }
        source.updateFailure.withLock { $0 = .refused("Disk unavailable") }
        model.draft[.diskReserveMegabytes] = " 0256 "
        await model.save([.diskReserveMegabytes], revertsOnFailure: true)
        #expect(model.draft[.diskReserveMegabytes] == "128")
        #expect(returned == [.typed(title: InstanceSetting.diskReserveMegabytes.title, text: " 0256 ")])
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
        #expect(model.saved == ["Most versions per item: Default"])
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

    @Test func shorteningTrashRetentionWaitsForAgreementAndUnlimitedRetentionSavesImmediately() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60)])

        model.draft[.trashRetentionDays] = "7"
        await model.save()
        #expect(source.sent.isEmpty)
        #expect(model.pending?.shortenings == [.init(setting: .trashRetentionDays, change: .shorter(from: 60, to: 7))])
        model.cancelPending()
        #expect(source.sent.isEmpty)
        // Keeping things as they were puts the field back.
        #expect(model.draft[.trashRetentionDays] == "60")

        model.draft[.trashRetentionDays] = "7"
        await model.save()
        if let pending = model.pending { await model.confirm(pending) }
        #expect(source.sent == [InstanceConfigPatch(values: [.trashRetentionDays: .number(7)])])

        // Longer, and no limit at all, ask nothing.
        model.draft[.trashRetentionDays] = "0"
        await model.save()
        #expect(model.pending == nil)
        #expect(source.sent.count == 2)
    }

    @Test func revertingTheDraftTakesAwayAQuestionStillOpen() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60)])
        model.draft[.trashRetentionDays] = "7"
        await model.save()
        #expect(model.pending != nil)

        model.revert()

        #expect(model.pending == nil)
        #expect(model.draft[.trashRetentionDays] == "60")
        #expect(source.sent.isEmpty)
    }

    @Test func aSaveWhileAQuestionIsOpenChangesNeitherTheQuestionNorWhatIsSent() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60), .versionRecentDays: .number(14)])
        model.draft[.trashRetentionDays] = "7"
        await model.save()
        let asked = model.pending
        #expect(asked != nil)

        model.draft[.versionRecentDays] = "2"
        #expect(!model.canSave([.versionRecentDays]))
        await model.save([.versionRecentDays])
        await model.save()

        #expect(model.pending?.id == asked?.id)
        #expect(model.pending?.shortenings.map(\.setting) == [.trashRetentionDays])
        #expect(source.sent.isEmpty)
    }

    @Test func aChangeAgreedToAndOnItsWayIsNotAChangeLeftUnsaved() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60)])
        model.draft[.trashRetentionDays] = "7"
        await model.save()
        guard let asked = model.pending else { Issue.record("a shorter retention should ask first"); return }
        #expect(model.hasUnsentEdits)

        // Agreed, and closing Settings before the call is answered.
        let sending = model.agree(asked)
        #expect(!model.hasUnsentEdits)
        #expect(!model.canSave([.trashRetentionDays]))
        model.revert()
        await sending.value

        #expect(source.sent == [InstanceConfigPatch(values: [.trashRetentionDays: .number(7)])])
        #expect(model.draft[.trashRetentionDays] == "7")
        #expect(model.saved == ["Delete from Trash after: 7 days"])
        #expect(!model.hasUnsentEdits)
    }

    @Test func aChangeAgreedToThatTheServerRefusesIsLeftUnsavedAgain() async {
        let (model, source) = await loaded([.trashRetentionDays: .number(60)])
        source.updateFailure.withLock { $0 = .refused("No.") }
        model.draft[.trashRetentionDays] = "7"
        await model.save()
        if let asked = model.pending { await model.confirm(asked) }
        #expect(model.failure == .refused("No."))
        #expect(model.draft[.trashRetentionDays] == "7")
        #expect(model.hasUnsentEdits)
    }

    @Test func reducingUnusedFileRetentionToZeroNamesTheNextSweep() async throws {
        let (model, source) = await loaded([.blobCleanupGraceSeconds: .number(86_400)])
        model.draft[.blobCleanupGraceSeconds] = "0"
        await model.save([.blobCleanupGraceSeconds], revertsOnFailure: true)
        let confirmation = try #require(model.pending)
        #expect(source.sent.isEmpty)
        #expect(confirmation.shortenings.map(InstanceWording.consequence) == ["The next sweep can permanently remove files already reported as unused."])
        await model.confirm(confirmation)
        #expect(source.sent == [.init(values: [.blobCleanupGraceSeconds: .number(0)])])
    }

    @Test func aConfirmedTrashChangeThatFailsRestoresTheServerValueAndExplainsWhy() async throws {
        let (model, source) = await loaded([.trashRetentionDays: .number(0)])
        model.draft[.trashRetentionDays] = "36500"
        await model.save([.trashRetentionDays], revertsOnFailure: true)
        let confirmation = try #require(model.pending)
        #expect(confirmation.shortenings == [.init(setting: .trashRetentionDays, change: .shorter(from: 0, to: 36_500))])
        source.updateFailure.withLock { $0 = .refused("The server is busy.") }
        await model.confirm(confirmation)
        #expect(model.failure == .refused("The server is busy."))
        #expect(model.draft[.trashRetentionDays] == "0")
        #expect(!model.hasUnsentEdits)
    }

    @Test func keepingLessFreeOnDiskAsksFirstAndNamesTheOldAndNewValues() async {
        // A "5" on the way to "500" is not sent as it is typed.
        let (model, source) = await loaded([.diskReserveMegabytes: .number(500)])
        model.draft[.diskReserveMegabytes] = "5"
        await model.save([.diskReserveMegabytes])
        #expect(source.sent.isEmpty)
        #expect(model.pending?.shortenings == [.init(setting: .diskReserveMegabytes, change: .shorter(from: 500, to: 5))])
        let words = model.pending?.shortenings.map(InstanceWording.consequence).joined() ?? ""
        #expect(words.contains("5 MB"))
        #expect(words.contains("500 MB"))
        model.cancelPending()
        #expect(model.draft[.diskReserveMegabytes] == "500")

        // More free space, or the same, asks nothing.
        model.draft[.diskReserveMegabytes] = "5000"
        await model.save([.diskReserveMegabytes])
        #expect(model.pending == nil)
        #expect(source.sent == [InstanceConfigPatch(values: [.diskReserveMegabytes: .number(5000)])])
    }

    @Test func keepingLessFreeOnDiskUsesTheServerDefaultWhereNothingIsSet() async {
        let setting = InstanceSetting.diskReserveMegabytes
        let defaults = [setting: 256]
        #expect(await asked([:], [setting: "128"], defaults: defaults) == [.init(setting: setting, change: .shorter(from: 256, to: 128))])
        #expect(await asked([:], [setting: "256"], defaults: defaults).isEmpty)
        #expect(await asked([:], [setting: "1024"], defaults: defaults).isEmpty)
        #expect(await asked([setting: .number(500)], [setting: ""], defaults: defaults) == [.init(setting: setting, change: .shorter(from: 500, to: 256))])
        #expect(await asked([setting: .number(100)], [setting: ""], defaults: defaults).isEmpty)
        #expect(await asked([:], [setting: "128"]) == [.init(setting: setting, change: .mayBeShorter(to: 128))])
    }

    /// What `save` would ask about for `typed` on a server that holds `held`.
    private func asked(_ held: [InstanceSetting: InstanceValue], _ typed: [InstanceSetting: String], defaults: [InstanceSetting: Int] = [:]) async -> [InstanceSettingsModel.Shortening] {
        let (model, _) = await loaded(held)
        for (setting, text) in typed { model.draft[setting] = text }
        await model.save(Set(typed.keys), defaults: defaults)
        return model.pending?.shortenings ?? []
    }

    @Test func aValueTypedForAnUnsetRetentionAsksBecauseTheServersDefaultIsNotKnown() async {
        // A server whose environment sets a default of 365 days of trash would lose items sooner at 100.
        #expect(await asked([:], [.trashRetentionDays: "100"]) == [.init(setting: .trashRetentionDays, change: .mayBeShorter(to: 100))])
        // Even a value longer than the documented default, and one equal to it.
        #expect(await asked([:], [.trashRetentionDays: "90"]).count == 1)
        #expect(await asked([:], [.trashRetentionDays: "60"]).count == 1)
        #expect(await asked([:], [.trashRetentionDays: "36500"]).count == 1, "Even the longest finite period shortens unlimited retention.")
        #expect(await asked([:], [.versionWeeklyDays: "400"]) == [.init(setting: .versionWeeklyDays, change: .versionPolicy)])
        #expect(await asked([:], [.versionMaxVersions: "900"]) == [.init(setting: .versionMaxVersions, change: .versionPolicy)])
        #expect(await asked([:], [.versionRecentDays: "0"]).count == 1)
    }

    @Test func aValueNothingCouldOutlastAsksNothing() async {
        #expect(await asked([:], [.trashRetentionDays: "0"]).isEmpty)
        #expect(await asked([:], [.versionMaxVersions: "1000000"]).isEmpty)
        #expect(await asked([:], [.name: "Home"]).isEmpty)
    }

    @Test func clearingASetRetentionAsksAndNamesNoDefault() async {
        let shortenings = await asked([.trashRetentionDays: .number(45), .versionMaxVersions: .number(50)], [.trashRetentionDays: "", .versionMaxVersions: " "])
        #expect(shortenings == [
            .init(setting: .trashRetentionDays, change: .toDefault(from: 45)),
            .init(setting: .versionMaxVersions, change: .versionPolicy),
        ])
        let words = shortenings.map(InstanceWording.consequence)
        #expect(words[0].contains("may remove deleted items sooner than the server’s current setting"))
        #expect(words[0].contains("45 days"))
        #expect(!words[0].contains("60"))
        #expect(!words[1].contains("500"))
    }

    @Test func clearingASettingAsksWhenTheDefaultCouldRemoveData() async {
        #expect(await asked([.versionRecentDays: .number(0)], [.versionRecentDays: ""]) == [.init(setting: .versionRecentDays, change: .versionPolicy)])
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

    @Test func aSettingChangedElsewhereIsShownAndNotOverwritten() async {
        let (model, source) = await loaded([.name: .text("Library")])
        model.draft[.name] = "Home"
        source.config.withLock { $0.values[.name] = .text("Office") }

        await model.save()

        #expect(source.sent.isEmpty)
        #expect(model.loaded?.name == "Office")
        #expect(model.draft[.name] == "Home")
        #expect(model.elsewhereMessage?.contains("Name: Office") == true)
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
