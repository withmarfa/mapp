import Foundation
import Marfa
import Testing
@testable import MAPP

@MainActor @Suite(.hangLimit) final class PreferencesSyncTests {
    let defaults: UserDefaults
    let suite = "MAPPTests.PreferencesSync.\(UUID().uuidString)"
    var reloads = 0
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let accent = PreferenceUnit.member(.appearance, AppearanceKey.accent)
    let placement = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.note")

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    deinit { UserDefaults().removePersistentDomain(forName: suite) }

    private func sync(_ copy: FakePreferencesCopy, library: String = "marfa:https://one") async -> PreferencesSync {
        let sync = PreferencesSync(defaults: defaults, enabled: true, coalescing: .milliseconds(50)) { [weak self] in self?.reloads += 1 }
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

    @Test func aMacThatAdoptedAnotherMarfaStartsANewOneFromMAPPsDefaults() async throws {
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
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        // The server kept another Mac's field, which changed the theme, and wrote this Mac's to a conflicted copy.
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
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
}
