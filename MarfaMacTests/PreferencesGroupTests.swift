import Foundation
import Testing
@testable import MarfaMac

@MainActor @Suite(.hangLimit) struct PreferencesGroupTests {
    let defaults = ThrowawayDefaults.make("MarfaMacTests.PreferencesGroups")
    let points = RestorePoints.temporary()
    let copy = FakePreferencesCopy()
    let instance = "instance-1"
    let theme = PreferenceUnit.member(.appearance, AppearanceKey.theme)
    let accent = PreferenceUnit.member(.appearance, AppearanceKey.accent)
    let week = PreferenceUnit.member(.general, WeekStart.key)
    let row = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.note")

    func connect(groupNotSaved: @escaping @MainActor () -> Void = {}) async -> PreferencesSync {
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true, restorePoints: points,
                                   groupNotSaved: groupNotSaved) {}
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        return sync
    }

    @Test func eachSyncedSettingHasOneGroupAndFilesOnlySettingsHaveNone() {
        #expect(Set(PreferencesMap.synced.compactMap(\.group)) == Set(PreferenceGroup.allCases))
        #expect(PreferencesMap.synced.allSatisfy { $0.group != nil })
        #expect(PreferencesMap.inFilesOnly.allSatisfy { $0.group == nil })
        #expect(PreferencesMap.synced.first { $0.key == SearchLeaveOuts.defaultsKey }?.group == .search)
    }

    @Test func offSkipsLocalEditsRemovalsAndRemoteChangesAcrossSteps() async throws {
        let item = await copy.add([theme: #""light""#, accent: #""blue""#, row: #"{"pins":[]}"#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        try await sync.setSyncing(false, for: .layouts, in: instance)
        defaults.set("mine", forKey: AppearanceKey.theme)
        defaults.removeObject(forKey: AppearanceKey.accent)
        defaults.removeObject(forKey: PagePlacements.key)
        defaults.set(2, forKey: WeekStart.key)
        await copy.change(item, [theme: #""dark""#, row: #"{"pins":["due"]}"#])
        for _ in 0..<3 { await sync.flush() }
        #expect(await copy.unitsHeld(item) == [theme: #""dark""#, accent: #""blue""#, row: #"{"pins":["due"]}"#, week: "2"])
        #expect(await copy.updates == [[.general]])
        #expect(await copy.batches.isEmpty)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "mine")
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(defaults.object(forKey: PagePlacements.key) == nil)
    }

    @Test func enablingWaitsForTheWholeCopyThenTakesItsSettingsEvenAfterRelaunch() async throws {
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        await copy.set(.init(filled: true, holdsType: true, tablesWhole: false, instance: instance))
        await copy.change(item, [theme: #""dark""#], removing: [accent])
        defaults.set("mine", forKey: AppearanceKey.theme)
        defaults.set("green", forKey: AppearanceKey.accent)
        try await sync.setSyncing(true, for: .appearance, in: instance)
        #expect(defaults.string(forKey: AppearanceKey.theme) == "mine")
        #expect(await copy.updates.isEmpty)
        let point = try #require(points.list().first)
        #expect(point.reason == .resumingGroup)
        #expect(try points.snapshot(of: point.id).value(forKey: AppearanceKey.theme) as? String == "mine")
        sync.detach()
        let reopened = await connect()
        await copy.set(.init(filled: true, holdsType: true, tablesWhole: true, instance: instance))
        await reopened.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        await reopened.flush()
        #expect(await copy.updates.isEmpty)
        #expect(try points.snapshot(of: point.id).value(forKey: AppearanceKey.accent) as? String == "green")
    }

    @Test func editsMadeWhileWaitingForAWholeCopyMustAlsoHaveARestorePoint() async throws {
        let item = await copy.add([theme: #""light""#])
        var told = 0
        let sync = await connect { told += 1 }
        try await sync.setSyncing(false, for: .appearance, in: instance)
        await copy.set(.init(filled: false, holdsType: true, tablesWhole: true, instance: instance))
        try await sync.setSyncing(true, for: .appearance, in: instance)
        defaults.set("later", forKey: AppearanceKey.theme)
        try FileManager.default.removeItem(at: points.folder)
        try Data().write(to: points.folder)
        await copy.set(.init(filled: true, holdsType: true, tablesWhole: true, instance: instance))
        await sync.flush()
        #expect(told == 1)
        #expect(!sync.groups.isOn(.appearance, in: instance))
        #expect(defaults.string(forKey: AppearanceKey.theme) == "later")
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
    }

    @Test func failedRestorePointLeavesGroupOff() async throws {
        let item = await copy.add([theme: #""light""#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        try FileManager.default.removeItem(at: points.folder)
        try Data().write(to: points.folder)
        await #expect(throws: RestorePoints.Failure.notSaved) {
            try await sync.setSyncing(true, for: .appearance, in: instance)
        }
        await copy.change(item, [theme: #""dark""#])
        await sync.flush()
        #expect(!sync.groups.isOn(.appearance, in: instance))
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
    }

    @Test func lostWriteInAnOffFieldIsNeitherReclaimedNorTaken() async throws {
        let item = await copy.add([theme: #""light""#, accent: #""blue""#])
        let sync = await connect()
        await copy.holdNextAnswer()
        defaults.set("red", forKey: AppearanceKey.accent)
        await sync.flush()
        let write = try #require(await copy.writeIDs.last)
        try await sync.setSyncing(false, for: .appearance, in: instance)
        await copy.change(item, [theme: #""dark""#, accent: #""blue""#])
        let sibling = await copy.add([theme: #""light""#, accent: #""red""#], conflicted: true)
        await copy.answer(write, .lost)
        await sync.flush()
        #expect(await copy.writeIDs == [write])
        #expect(defaults.string(forKey: AppearanceKey.theme) == "light")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""blue""#)
        #expect(await copy.activeIDs.contains(sibling))
    }

    @Test func restoringAndImportingWhileOffOnlyChangeThisMac() async throws {
        defaults.set("original", forKey: AppearanceKey.theme)
        let item = await copy.add([theme: #""light""#])
        let sync = await connect()
        let point = try #require(points.list().first)
        try await sync.setSyncing(false, for: .appearance, in: instance)
        try await sync.restore(point.id)
        #expect(!sync.groups.isOn(.appearance, in: instance))
        #expect(defaults.string(forKey: AppearanceKey.theme) == "original")
        try await sync.importSettings(SettingsFile(units: [theme: #""imported""#], build: "", date: .now), sections: [.appearance])
        #expect(defaults.string(forKey: AppearanceKey.theme) == "imported")
        #expect(await copy.unitsHeld(item)[theme] == #""light""#)
        #expect(await copy.updates.isEmpty)
        #expect(try SettingsSnapshot(of: defaults, domain: defaults.suite).value(forKey: PreferenceGroups.key) == nil)
    }

    @Test func switchingMarfasLoadsOnlyThatInstancesChoices() async throws {
        let item = await copy.add([theme: #""one""#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        let other = FakePreferencesCopy()
        await other.set(.init(filled: true, holdsType: true, tablesWhole: true, instance: "two"))
        await other.add([theme: #""two""#])
        sync.attach(other, library: "other", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "two")
        sync.attach(copy, library: "alias-for-one", name: { nil })
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "two")
        #expect(await copy.unitsHeld(item)[theme] == #""one""#)
    }

    @Test func resetClearsTheSwitchesWithoutSendingDeletionsForAnOffGroup() async throws {
        let libraries = Libraries(host: HostBench().host(), defaults: defaults, handOverPages: { $0(true) },
                                  syncsPreferences: true, restorePoints: points, defaultsDomain: defaults.suite)
        let sync = libraries.preferences
        let item = await copy.add([theme: #""light""#, week: "2"])
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        defaults.set("dark", forKey: AppearanceKey.theme)
        libraries.resetMacSettings()
        await sync.flush()
        #expect(defaults.object(forKey: PreferenceGroups.key) == nil)
        #expect(sync.groups.isOn(.appearance, in: instance))
        #expect(await copy.unitsHeld(item) == [theme: #""light""#])
    }

    @Test func firstAdoptionNeverFillsAnOffFieldFromAnotherItemOrThisMac() async throws {
        await copy.set(.init(filled: false, holdsType: true, tablesWhole: false, instance: instance))
        let item = await copy.add([theme: #""first""#])
        await copy.add([accent: #""other""#])
        defaults.set("local", forKey: AppearanceKey.theme)
        defaults.set(2, forKey: WeekStart.key)
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        await copy.set(.init(filled: true, holdsType: true, tablesWhole: true, instance: instance))
        await sync.flush()
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "local")
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(await copy.unitsHeld(item) == [theme: #""first""#, week: "2"])
        #expect(await copy.updates == [[.general]])
    }

    @Test func resumingBeforeFirstAdoptionUsesDefaultsForMissingValues() async throws {
        await copy.set(.init(filled: false, holdsType: true, tablesWhole: false, instance: instance))
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        defaults.set("green", forKey: AppearanceKey.accent)
        try await sync.setSyncing(true, for: .appearance, in: instance)
        await copy.set(.init(filled: true, holdsType: true, tablesWhole: true, instance: instance))
        await sync.flush()
        let item = try #require(await copy.activeIDs.first)
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(await copy.unitsHeld(item).isEmpty)
    }

    @Test func resumingLeavesANewerFieldOnAnotherMacAfterAConflict() async throws {
        let item = await copy.add([:])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        defaults.set("green", forKey: AppearanceKey.accent)
        await copy.holdNextAnswer()
        try await sync.setSyncing(true, for: .appearance, in: instance)
        await copy.change(item, [accent: #""red""#])
        if let write = await copy.writeIDs.last { await copy.answer(write, .lost) }
        await sync.flush()
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.writeIDs.isEmpty)
    }

    @Test func resumingLeavesARowWrittenAfterThisMacReadTheItem() async throws {
        let existing = PreferenceUnit.row(.types, setting: "pagePlacements", key: "core.task")
        let item = await copy.add([existing: #"{"pins":[]}"#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .layouts, in: instance)
        defaults.set(#"{"core.note":{"pins":["here"]},"core.task":{"pins":["local"]}}"#, forKey: PagePlacements.key)
        await copy.whileReading { await copy.change(item, [row: #"{"pins":["other"]}"#]) }
        try await sync.setSyncing(true, for: .layouts, in: instance)
        await sync.flush()
        #expect(await copy.batches.isEmpty)
        #expect(await copy.unitsHeld(item)[row] == #"{"pins":["other"]}"#)
        #expect(defaults.string(forKey: PagePlacements.key) == #"{"core.note":{"pins":["other"]},"core.task":{"pins":[]}}"#)
    }

    @Test func disablingSearchKeepsTheConnectedLibrarysExclusionsLocal() async throws {
        let exclusions = SearchLeaveOuts(defaults: defaults)
        exclusions.update("one") { $0.sources = ["rss"] }
        exclusions.update("two") { $0.sources = ["mail"] }
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true,
                                   restorePoints: points, reload: exclusions.reload)
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        let item = try #require(await copy.activeIDs.first)
        let unit = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        try await sync.setSyncing(false, for: .search, in: instance)
        exclusions.update("one") { $0 = SearchLeaveOut() }
        let remote = #"{"sources":["remote"],"types":[]}"#
        await copy.change(item, [unit: remote])
        await sync.flush()
        #expect(exclusions.leaveOut(for: "one").isEmpty)
        #expect(await copy.unitsHeld(item)[unit] == remote)
        try await sync.setSyncing(true, for: .search, in: instance)
        #expect(exclusions.leaveOut(for: "one").sources == ["remote"])
        #expect(exclusions.leaveOut(for: "two").sources == ["mail"])
    }

    @Test func resumingReadsBothOriginalItemsWhileFollowingTheOlderOne() async throws {
        let older = await copy.add([theme: #""dark""#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: instance)
        let newer = await copy.add([theme: #""light""#, accent: #""red""#], createdAt: "2026-01-02")
        defaults.set("green", forKey: AppearanceKey.accent)
        try await sync.setSyncing(true, for: .appearance, in: instance)
        await sync.flush()
        #expect(defaults.string(forKey: AppearanceKey.theme) == "dark")
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(older) == [theme: #""dark""#])
        #expect(await copy.unitsHeld(newer) == [theme: #""light""#, accent: #""red""#])
        #expect(await copy.updates.isEmpty)
        #expect(await copy.batches.isEmpty)
        #expect(await copy.removed.isEmpty)

        // An explicit edit goes to the older item. Clearing it later must not bring the second item's value back.
        defaults.set("blue", forKey: AppearanceKey.accent)
        await sync.flush()
        defaults.removeObject(forKey: AppearanceKey.accent)
        await sync.flush()
        await sync.flush()
        #expect(defaults.object(forKey: AppearanceKey.accent) == nil)
        #expect(await copy.unitsHeld(older) == [theme: #""dark""#])
    }

    @Test func resumingDoesNotRecordAnExclusionTheStoreRejectedAsShared() async throws {
        let exclusions = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        let item = await copy.add([:])
        let store = SearchLeaveOuts(defaults: defaults)
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true,
                                   restorePoints: points, reload: store.reload)
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        try await sync.setSyncing(false, for: .search, in: instance)
        let unreadable = #""unknown format""#
        await copy.change(item, [exclusions: unreadable])
        try await sync.setSyncing(true, for: .search, in: instance)
        let adopted = try #require(PreferencesSync.Record.read(defaults).marfas[instance])
        #expect(adopted.base[exclusions] == nil)
        #expect(store.leaveOut(for: "one").isEmpty)
        await sync.flush()
        #expect(await copy.unitsHeld(item)[exclusions] == unreadable)
        #expect(await copy.updates.isEmpty)
        #expect(defaults.array(forKey: SearchLeaveOuts.setAsideKey)?.count == 1)
        #expect(PreferencesSync.Record.read(defaults).marfas[instance]?.base[exclusions] == nil)
    }

    @Test func settingAsideUnreadableSearchDataOnResumeKeepsTheRemoteExclusions() async throws {
        let exclusions = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        let snippets = PreferenceUnit.member(.search, SearchOptions.showsSnippetsKey)
        let remote = #"{"sources":["rss"],"types":[]}"#
        let item = await copy.add([exclusions: remote, snippets: "true"])
        let store = SearchLeaveOuts(defaults: defaults)
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true,
                                   restorePoints: points, reload: store.reload)
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        try await sync.setSyncing(false, for: .search, in: instance)
        let unreadable = Data("unreadable".utf8)
        defaults.set(unreadable, forKey: SearchLeaveOuts.defaultsKey)
        defaults.set(false, forKey: SearchOptions.showsSnippetsKey)
        try await sync.setSyncing(true, for: .search, in: instance)
        await sync.flush()
        #expect(defaults.array(forKey: SearchLeaveOuts.setAsideKey) as? [Data] == [unreadable])
        #expect(store.leaveOut(for: "one").sources == ["rss"])
        #expect(await copy.unitsHeld(item) == [exclusions: remote, snippets: "true"])
        #expect(await copy.updates.isEmpty)
    }
}
