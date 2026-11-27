import Foundation
import Testing
@testable import MarfaMac

extension PreferencesGroupTests {
    @Test func readingAResumedDateFormatDoesNotDeleteItFromTheMarfa() async throws {
        let libraries = Libraries(host: HostBench().host(), defaults: defaults, handOverPages: { $0(true) },
                                 syncsPreferences: true, restorePoints: points, defaultsDomain: defaults.suite)
        let item = await copy.add([:])
        let date = PreferenceUnit.member(.general, DateFormat.key)
        let sync = libraries.preferences
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        try await sync.setSyncing(false, for: .general, in: "instance-1")
        await copy.change(item, [date: #""future-format""#])
        try await sync.setSyncing(true, for: .general, in: "instance-1")
        #expect(defaults.object(forKey: DateFormat.key) == nil)
        #expect(PreferencesSync.Record.read(defaults).marfas[instance]?.base[date] == nil)
        _ = DateFormat.stored(in: defaults)
        #expect(defaults.stringArray(forKey: DateFormat.setAsideKey) == ["future-format"])
        await sync.flush()
        #expect(await copy.unitsHeld(item)[date] == #""future-format""#)
        #expect(await copy.updates.isEmpty)
        sync.detach()
    }

    @Test func protectedSearchTakesTheRemoteValueWhenAvailable() async throws {
        let unit = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        let store = SearchLeaveOuts(defaults: defaults)
        var protected = false
        let remote = #"{"sources":["other"],"types":[]}"#
        let item = await copy.add([:])
        let sync = PreferencesSync(defaults: defaults, domain: defaults.suite, enabled: true,
                                   restorePoints: points, unsettled: { _ in protected ? [SearchLeaveOuts.defaultsKey] : [] },
                                   reload: store.reload)
        sync.attach(copy, library: "one", name: { nil })
        await sync.flush()
        try await sync.setSyncing(false, for: .search, in: "instance-1")
        store.update("one") { $0.sources = ["local"] }
        let snippets = PreferenceUnit.member(.search, SearchOptions.showsSnippetsKey)
        await copy.change(item, [unit: remote, snippets: "false"])
        protected = true
        try await sync.setSyncing(true, for: .search, in: "instance-1")
        await copy.change(item, [accent: #""red""#])
        await sync.flush()
        #expect(store.leaveOut(for: "one").sources == ["local"])
        #expect(defaults.object(forKey: SearchOptions.showsSnippetsKey) == nil)
        #expect(defaults.string(forKey: AppearanceKey.accent) == "red")
        #expect(PreferencesSync.Record.read(defaults).paused?[instance] == [.search])
        protected = false
        await sync.flush()
        #expect(points.list().count { $0.reason == .resumingGroup } == 1)
        #expect(store.leaveOut(for: "one").sources == ["other"])
        #expect(defaults.object(forKey: SearchOptions.showsSnippetsKey) as? Bool == false)
        #expect(await copy.unitsHeld(item)[unit] == remote)
        #expect(await copy.updates.isEmpty)
        sync.detach()
    }

    @Test func resumingOlderPlaceRowsDoesNotOverwriteANewerRow() async throws {
        let item = await copy.add([:])
        let sync = await connect()
        try await sync.setSyncing(false, for: .viewsAndPlaces, in: "instance-1")
        let old = PreferenceUnit.row(.places, setting: "placeDensity", key: #"{"recents":{}}"#)
        let new = PreferenceUnit.row(.places, setting: "placeDensity", key: PlaceView.library.storageKey)
        await copy.change(item, [old: #""compact""#])
        try await sync.setSyncing(true, for: .viewsAndPlaces, in: "instance-1")
        await copy.change(item, [new: #""standard""#])
        await sync.flush()
        #expect(await copy.unitsHeld(item)[new] == #""standard""#)
        #expect(PlaceDensities.stored(in: defaults).density(for: .library) == .standard)
        #expect(await copy.batches.isEmpty)
        sync.detach()
    }

    @Test func otherMacCanRecoverItsConflictAfterThisMacResumes() async throws {
        let item = await copy.add([accent: #""blue""#])
        let b = ThrowawayDefaults.make("PreferencesGroups.OtherMac")
        let mine = await connect()
        let theirs = PreferencesSync(defaults: b, domain: b.suite, enabled: true) {}
        try await mine.setSyncing(false, for: .appearance, in: "instance-1")
        mine.detach()
        theirs.attach(copy, library: "one", name: { nil })
        await theirs.flush()
        await copy.holdNextAnswer()
        b.set("red", forKey: AppearanceKey.accent)
        await theirs.flush()
        theirs.detach()
        await copy.change(item, [accent: #""blue""#])
        let sibling = await copy.add([accent: #""red""#], conflicted: true)
        await copy.reopen()
        mine.attach(copy, library: "one", name: { nil })
        await mine.flush()
        #expect(await copy.activeIDs.contains(sibling))
        let other = await copy.add([week: "3"], conflicted: true)
        try await mine.setSyncing(true, for: .appearance, in: "instance-1")
        #expect(await copy.removed.contains(other))
        mine.detach()
        mine.attach(copy, library: "one", name: { nil })
        await mine.flush()
        #expect(await copy.activeIDs.contains(sibling))
        mine.detach()
        theirs.attach(copy, library: "one", name: { nil })
        await theirs.flush()
        #expect(b.string(forKey: AppearanceKey.accent) == "red")
        #expect(await copy.unitsHeld(item)[accent] == #""red""#)
        theirs.detach()
    }

    @Test func unreadableDensityDoesNotDisplaceItsReadableNeighbor() async throws {
        let here = PreferenceUnit.row(.places, setting: "placeDensity", key: PlaceView.library.storageKey)
        let other = PreferenceUnit.row(.places, setting: "placeDensity", key: PlaceView.feed.storageKey)
        let item = await copy.add([:])
        let sync = await connect()
        try await sync.setSyncing(false, for: .viewsAndPlaces, in: instance)
        await copy.change(item, [here: "99", other: #""compact""#])
        try await sync.setSyncing(true, for: .viewsAndPlaces, in: instance)
        #expect(PlaceDensities.stored(in: defaults).density(for: .feed) == .compact)
        #expect(PreferencesSync.Record.read(defaults).marfas[instance]?.base[here] == nil)
        PlaceDensities.update(in: defaults) { $0.set(.standard, for: .feed) }
        await sync.flush()
        #expect(await copy.unitsHeld(item) == [here: "99", other: #""standard""#])
        sync.detach()
    }

    @Test func aStepAlreadyReadingCannotSendAnOffGroupsEditOnResume() async throws {
        let item = await copy.add([accent: #""blue""#])
        let sync = await connect()
        try await sync.setSyncing(false, for: .appearance, in: "instance-1")
        defaults.set("green", forKey: AppearanceKey.accent)
        await copy.pauseNextItems()
        let step = Task { await sync.flush() }
        #expect(try await eventuallyAsking { await copy.isHoldingItems })
        let turnOn = Task { try await sync.setSyncing(true, for: .appearance, in: "instance-1") }
        await Task.yield()
        await copy.resume()
        await step.value
        try await turnOn.value
        await sync.flush()
        #expect(await copy.unitsHeld(item)[accent] == #""blue""#)
        #expect(defaults.string(forKey: AppearanceKey.accent) == "blue")
        #expect(await copy.updates.isEmpty)
        sync.detach()
    }
}
