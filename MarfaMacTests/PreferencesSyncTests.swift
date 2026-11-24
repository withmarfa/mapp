import Foundation
import Marfa
import Testing
@testable import MarfaMac

@MainActor @Suite(.hangLimit) final class PreferencesSyncTests {
    let defaults: UserDefaults
    var reloads = 0
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let accent = PreferenceUnit.member(.appearance, AppearanceKey.accent)
    let placement = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.note")

    init() {
        defaults = ThrowawayDefaults.make("MarfaMacTests.PreferencesSync")
    }

    private func sync(_ copy: FakePreferencesCopy, library: String = "marfa:https://one") async -> PreferencesSync {
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50)) { [weak self] in self?.reloads += 1 }
        sync.attach(copy, library: library, name: { "Demo" })
        await sync.flush()
        return sync
    }

    /// A sync whose stores read the defaults again as the app's do, setting aside what they cannot read.
    private func syncWithStores(_ copy: FakePreferencesCopy, library: String = "marfa:https://one") async -> PreferencesSync {
        let stores = (
            SidebarLayouts(defaults: defaults), TypeLooks(defaults: defaults), SearchLeaveOuts(defaults: defaults),
            ShortcutBindings(defaults: defaults), AnyAppShortcuts(defaults: defaults, registrar: NoHotKeys()))
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50)) {
            stores.0.reload()
            stores.1.reload()
            stores.2.reload()
            stores.3.reload()
            stores.4.reload()
        }
        sync.attach(copy, library: library, name: { "Demo" })
        await sync.flush()
        return sync
    }

    // MARK: The first launch

    @Test func aMarfaWithNoSettingsTakesThisMacsAndKeepsACopyFirst() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(#"{"core.note":{"pins":["due_at"]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 1)
        let item = try #require(await copy.activeIDs.first)
        let held = await copy.unitsHeld(item)
        #expect(held[theme] == #""dark""#)
        #expect(held[placement] == #"{"pins":["due_at"]}"#)
        let kept = try #require(defaults.string(forKey: PreferencesSync.beforeSyncKey))
        #expect(kept.contains(#""theme":"dark""#))
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }

    @Test func withoutThePermissionNothingChanges() async {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: false, tablesWhole: false, instance: "instance-1"))
        let sync = await sync(copy)
        #expect(sync.standing == .off(.needsPermission))
        #expect(await copy.creates == 0)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.object(forKey: PreferencesSync.beforeSyncKey) == nil)
    }

    @Test func aCopyThatIsNotWholeDecidesNothing() async {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        await copy.add([theme: #""light""#])
        for readiness in [
            PreferencesReadiness(filled: false, holdsType: true, tablesWhole: true, instance: "instance-1"),
            PreferencesReadiness(filled: true, holdsType: true, tablesWhole: false, instance: "instance-1"),
        ] {
            await copy.set(readiness)
            let sync = await sync(copy)
            #expect(sync.standing == .off(.notFilled))
            sync.detach()
        }
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.updates.isEmpty)
        #expect(defaults.object(forKey: PreferencesSync.beforeSyncKey) == nil)
    }

    @Test func anItemAnotherMacMadeWinsAndIsFilledFromThisMac() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set("blue", forKey: AppearanceKey.accent)
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await sync(copy)
        #expect(sync.standing == .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(await copy.unitsHeld(item)[accent] == #""blue""#)
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
        #expect(reloads == 1)
        #expect(defaults.object(forKey: PreferencesSync.beforeSyncKey) != nil)
    }

    @Test func twoItemsUseTheOneMadeFirstFilledFromTheOther() async throws {
        let copy = FakePreferencesCopy()
        let first = await copy.add([theme: #""light""#], createdAt: "2026-01-01T00:00:00Z")
        let second = await copy.add([theme: #""dark""#, accent: #""red""#], createdAt: "2026-01-02T00:00:00Z")
        _ = await sync(copy)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(first)[accent] == #""red""#)
        #expect(await copy.unitsHeld(second) == [theme: #""dark""#, accent: #""red""#])
    }

    @Test func aMacThatAdoptedAnotherMarfaStartsANewOneFromTheAppsDefaults() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [theme: #""dark""#])
        record.last = "instance-0"
        record.save(defaults)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        _ = await sync(copy)
        #expect(defaults.object(forKey: AppearanceKey.theme) == nil)
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item).isEmpty)
        #expect(try #require(defaults.string(forKey: PreferencesSync.beforeSyncKey)).contains("dark"))
    }

    // MARK: Following

    @Test func anotherMacsChangeReachesTheDefaultsAndIsNotSentBack() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let reloaded = reloads
        await copy.change(item, [theme: #""light""#, placement: #"{"pins":[]}"#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(defaults.string(forKey: PagePlacements.key) == #"{"core.note":{"pins":[]}}"#)
        #expect(reloads == reloaded + 1)
        let updates = await copy.updates.count
        let batches = await copy.batches
        await sync.flush()
        #expect(await copy.updates.count == updates)
        #expect(await copy.batches == batches)
    }

    @Test func aChangeOnThisMacIsCoalescedIntoOneWrite() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let before = await copy.updates.count
        for size in 1...20 { defaults.set(Double(size), forKey: InterfaceKey.textSize) }
        #expect(try await eventuallyAsking { await copy.updates.count == before + 1 })
        // Lets a second write, which would be wrong, arrive if one were coming.
        try await Task.sleep(for: .milliseconds(300))
        #expect(await copy.updates.count == before + 1)
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item)[.member(.appearance, InterfaceKey.textSize)] == "20")
        _ = sync
    }

    @Test func aMarfaValueThatCannotBeReadIsSetAsideOnceAndLeftInTheMarfa() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [placement: "{not json"])
        await sync.flush()
        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == ["{not json"])
        #expect(defaults.string(forKey: PagePlacements.key) == nil)
        await sync.flush()
        #expect(defaults.stringArray(forKey: PagePlacements.setAsideKey) == ["{not json"])
        #expect(await copy.unitsHeld(item)[placement] == "{not json")
    }

    @Test func aConflictedFieldKeepsEachMembersLaterWrite() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        // The server kept another Mac's field, which changed the theme, and wrote this Mac's to a conflicted copy.
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await copy.answer(try #require(await copy.writeIDs.last), .lost)
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.unitsHeld(item)[theme] == #""dark""#)
        #expect(await copy.removed == [sibling])
    }

    @Test func resetPutsTheMarfasSettingsBackInOneWriteAndOneBatchPerTable() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        defaults.set(true, forKey: PageKey.foldsHeadings)
        defaults.set(#"{"core.note":{"pins":[]}}"#, forKey: PagePlacements.key)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        let (updates, batches) = (await copy.updates.count, await copy.batches)
        MacSettings.reset(in: defaults)
        await sync.flush()
        #expect(await copy.unitsHeld(item).isEmpty)
        #expect(await copy.updates.count == updates + 1)
        #expect(await copy.updates.last == [.appearance, .editor])
        #expect(await copy.batches[.types] == (batches[.types] ?? 0) + 1)
    }

    @Test func removedSettingsAreNotMadeAgain() async throws {
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        try await sync.remove()
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        #expect(await copy.creates == 1)
        try await sync.startAgain()
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 2)
    }

    // MARK: Review findings

    /// A value a later version of the app wrote, which a store here sets aside, stays in the Marfa for the Macs that read it: the
    /// store dropping it on this Mac is no change of the person's.
    @Test(arguments: [
        PreferenceUnit.row(.types, setting: "look", key: "core.note"),
        PreferenceUnit.row(.sidebar, setting: "layout", key: "tabs"),
        PreferenceUnit.member(.search, "searchLeaveOuts"),
        PreferenceUnit.row(.commands, setting: "shortcut", key: "newItem"),
        PreferenceUnit.row(.commands, setting: "anyAppShortcut", key: "quickAdd"),
    ])
    func aValueAStoreCannotReadIsNeverDeletedFromTheMarfa(unit: PreferenceUnit) async throws {
        let later = #""a shape a later version of the app writes""#
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#])
        let sync = await syncWithStores(copy)
        await copy.change(item, [unit: later])
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
        // A change to another setting, here one in the same field as the search member, still writes the member.
        defaults.set(true, forKey: SearchOptions.keys[0])
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[unit] == later)
    }

    /// Connecting to another Marfa starts the settings shared by every Marfa from the app's defaults, but keeps what this
    /// Mac already holds for this Marfa alone.
    @Test func aNewMarfaKeepsItsOwnSettingsOnThisMac() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [theme: #""dark""#])
        record.last = "instance-0"
        record.save(defaults)
        defaults.set("dark", forKey: AppearanceKey.theme)
        let leaveOut = #"{"marfa:https://one":{"sources":[],"types":["core.note"]}}"#
        defaults.set(Data(leaveOut.utf8), forKey: SearchLeaveOuts.defaultsKey)
        let copy = FakePreferencesCopy()
        _ = await sync(copy)
        #expect(defaults.object(forKey: AppearanceKey.theme) == nil)
        let stored = try #require(defaults.data(forKey: SearchLeaveOuts.defaultsKey))
        #expect(String(decoding: stored, as: UTF8.self).contains("core.note"))
        let item = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(item)[.member(.search, SearchLeaveOuts.defaultsKey)] == #"{"sources":[],"types":["core.note"]}"#)
    }

    /// Another Mac's change arrives late, after the server kept its field and before the conflicted copy reached
    /// this Mac: the member this Mac wrote is still its later write.
    @Test func aConflictedCopyThatArrivesLateStillKeepsThisMacsMember() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        let write = try #require(await copy.writeIDs.last)
        // The item's new value reaches the copy before the answer is taken.
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        await copy.answer(write, .lost)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        // The conflicted copy arrives last.
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.removed == [sibling])
    }

    /// A write the item took, then another Mac's later change of the same member: the later change wins here too.
    @Test func anotherMacsChangeAfterThisMacsWriteWasTakenWins() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        let write = try #require(await copy.writeIDs.last)
        await copy.answer(write, .taken)
        await copy.change(item, [accent: #""green""#])
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "green")
        #expect(await copy.unitsHeld(item)[accent] == #""green""#)
    }

    /// A field write answered while the app was not running, whose answer no sync took, is judged by its conflicted copy.
    @Test func aWriteAnsweredBeforeARelaunchIsJudgedByItsConflictedCopy() async throws {
        let copy = FakePreferencesCopy()
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await sync(copy)
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        sync.detach()
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await copy.reopen()
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(await copy.removed == [sibling])
    }

    /// A setting a store dropped is tried again by another app build, which may read it.
    @Test func aDroppedSettingIsTriedAgainByAnotherBuild() async throws {
        let look = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look: #""later""#])
        let looks = TypeLooks(defaults: defaults)
        let first = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50), build: "1") { looks.reload() }
        first.attach(copy, library: "marfa:https://one", name: { nil })
        await first.flush()
        #expect(defaults.data(forKey: TypeLooks.defaultsKey).map { String(decoding: $0, as: UTF8.self) }?.contains("later") != true)
        first.detach()
        // A build whose store reads the value keeps it.
        let second = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50), build: "2") {}
        second.attach(copy, library: "marfa:https://one", name: { nil })
        await second.flush()
        #expect(defaults.data(forKey: TypeLooks.defaultsKey).map { String(decoding: $0, as: UTF8.self) }?.contains("later") == true)
        #expect(await copy.unitsHeld(item)[look] == #""later""#)
    }

    /// A binned settings item's tables, which the copy never fills, and another type's tables, do not keep the
    /// settings from being judged whole.
    @Test func onlyTheTablesOfItemsOutsideTheBinCount() {
        let whole = PreferencesTable.allCases.map { HeldTable(itemId: "kept", table: $0.rawValue, state: .whole, rows: 0) }
        let binned = PreferencesTable.allCases.map { HeldTable(itemId: "binned", table: $0.rawValue, state: .owed, rows: 0) }
        let other = HeldTable(itemId: "other-type", table: PreferencesTable.commands.rawValue, state: .filling, rows: 0)
        #expect(WorkingCopyPreferences.tablesWhole(whole + binned + [other], of: ["kept"]))
        #expect(!WorkingCopyPreferences.tablesWhole(whole + binned, of: ["kept", "binned"]))
    }

    /// Start Again after another Marfa was adopted keeps this Mac's settings, as it says.
    @Test func startingAgainKeepsThisMacsSettings() async throws {
        var record = PreferencesSync.Record()
        record.marfas["instance-0"] = .init(item: "elsewhere", base: [:])
        record.save(defaults)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        defaults.set("dark", forKey: AppearanceKey.theme)
        await sync.flush()
        try await sync.remove()
        await sync.flush()
        try await sync.startAgain()
        #expect(sync.standing == .syncing)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        let made = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(made)[theme] == #""dark""#)
    }

    /// A change the person makes while a step reads the Marfa is not written over by what the step read.
    @Test func aChangeMadeWhileAStepReadsIsKept() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let item = try #require(await copy.activeIDs.first)
        await copy.change(item, [theme: #""light""#])
        await copy.whileReading { [defaults] in defaults.set("green", forKey: AppearanceKey.theme) }
        await sync.flush()
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "green")
        #expect(await copy.unitsHeld(item)[theme] == #""green""#)
    }

    /// An item that went without passing through the bin, as a discarded offline create or a restored server leaves
    /// it, is made again from this Mac's settings; only a binned item means the settings were removed.
    @Test func anItemGoneWithoutTheBinIsMadeAgain() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = await sync(copy)
        let first = try #require(await copy.activeIDs.first)
        await copy.forget(first)
        await sync.flush()
        #expect(sync.standing == .syncing)
        #expect(await copy.creates == 2)
        let made = try #require(await copy.activeIDs.first)
        #expect(await copy.unitsHeld(made)[theme] == #""dark""#)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
    }

    @Test func switchingMarfasLoadsEachOnesSettings() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let one = FakePreferencesCopy()
        let sync = await sync(one)
        let other = FakePreferencesCopy()
        await other.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-2"))
        await other.add([theme: #""light""#])
        sync.attach(other, library: "marfa:https://two", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        sync.attach(one, library: "marfa:https://one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(await one.updates.isEmpty)
    }

    @Test func aDroppedSettingThePersonChangesAndThenClearsIsDeletedFromTheMarfa() async throws {
        let look = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let copy = FakePreferencesCopy()
        let item = await copy.add([look: #""later""#])
        let looks = TypeLooks(defaults: defaults)
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50), build: "1") { looks.reload() }
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == #""later""#)
        defaults.set(Data(#"{"marfa:https://one":{"core.note":{"date":"created"}}}"#.utf8), forKey: TypeLooks.defaultsKey)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == #"{"date":"created"}"#)
        defaults.set(Data(#"{"marfa:https://one":{}}"#.utf8), forKey: TypeLooks.defaultsKey)
        await sync.flush()
        await sync.flush()
        #expect(await copy.unitsHeld(item)[look] == nil)
    }

    @Test func removedSettingsStayRemovedOnceTheBinIsEmptied() async throws {
        defaults.set("dark", forKey: AppearanceKey.theme)
        let copy = FakePreferencesCopy()
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50)) {}
        sync.attach(copy, library: "marfa:https://one", name: { nil })
        await sync.flush()
        let first = try #require(await copy.activeIDs.first)
        try await sync.remove()
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        await copy.forget(first)
        await sync.flush()
        #expect(sync.standing == .off(.removed))
        #expect(await copy.creates == 1)
    }
}

@MainActor @Suite(.hangLimit) struct PreferencesWiringTests {
    /// The library's copy is followed as it opens and let go as it closes; a copy whose slice lacks the type, as the
    /// sample's does, changes nothing on this Mac.
    @Test func theSettingsFollowTheOpenLibrary() async throws {
        let bench = HostBench()
        let host = bench.host(opener: { connection, _, _ in SampleLibrary.open(connection) })
        let libraries = Libraries(host: host, defaults: bench.defaults, syncsPreferences: true)
        bench.defaults.set("dark", forKey: AppearanceKey.theme)
        #expect(libraries.preferences.standing == .off(.noMarfa))
        try await host.connect(address: SampleLibrary.connection.address.absoluteString, key: "sample")
        #expect(await eventually { libraries.preferences.standing != .off(.noMarfa) })
        await libraries.preferences.flush()
        #expect(libraries.preferences.standing != .syncing)
        #expect(bench.defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(bench.defaults.object(forKey: PreferencesSync.beforeSyncKey) == nil)
        try await host.disconnect()
        #expect(libraries.preferences.standing == .off(.noMarfa))
    }
}
