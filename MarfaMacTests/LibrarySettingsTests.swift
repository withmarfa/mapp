import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// The settings an earlier build kept for one Marfa under each spelling of its address are joined under the name the
/// library has now before anything reads or syncs them: every part kept, a conflict decided by which library was open
/// last, the value that lost saved in a file, and nothing removed from the Marfa.
@Suite(.hangLimit)
@MainActor final class LibrarySettingsTests {
    private let bare = try! MarfaConnection(address: "https://marfa.test")
    private let withPort = try! MarfaConnection(address: "https://marfa.test:443")
    private let points = RestorePoints(folder: URL.temporaryDirectory.appending(path: "LibrarySettingsTests-\(UUID().uuidString)"))
    private var aside: URL { points.folder.appending(path: LibrarySettings.asideFolderName, directoryHint: .isDirectory) }

    deinit {
        try? FileManager.default.removeItem(at: points.folder)
    }

    private var bareKey: String { "marfa:" + bare.address.absoluteString }
    private var portKey: String { "marfa:" + withPort.address.absoluteString }

    /// What an earlier build left, the same bytes whichever spelling was edited last: a look and a search choice each
    /// spelling holds differently, and a look and a sidebar part only one holds.
    private func olderSettings(_ bench: HostBench) throws {
        for connection in [bare, withPort] {
            try FileManager.default.createDirectory(at: bench.location.directory(for: connection), withIntermediateDirectories: true)
        }
        let looks = #"{"\#(bareKey)":{"core.note":{"date":"created"},"core.task":{"date":"edited"}},"\#(portKey)":{"core.note":{"date":"edited"},"core.event":{"date":"created"}}}"#
        bench.defaults.set(Data(looks.utf8), forKey: TypeLooks.defaultsKey)
        let leaveOuts = #"{"\#(bareKey)":{"sources":["github"],"types":[]},"\#(portKey)":{"sources":["rss"],"types":[]}}"#
        bench.defaults.set(Data(leaveOuts.utf8), forKey: SearchLeaveOuts.defaultsKey)
        bench.defaults.set(Data(#"{"\#(portKey)":{"hidden":["feed"]}}"#.utf8), forKey: SidebarLayouts.defaultsKey)
    }

    private func libraries(_ bench: HostBench) -> Libraries {
        Libraries(host: bench.host(), defaults: bench.defaults, handOverPages: { $0(true) }, restorePoints: points)
    }

    private func storedLibraries(_ bench: HostBench, _ key: String) -> Set<String> {
        guard let data = bench.defaults.data(forKey: key),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        return Set(object.keys)
    }

    private func stored(_ bench: HostBench, _ key: String) throws -> [String: Any] {
        let data = try #require(bench.defaults.data(forKey: key))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func setAside() throws -> [[String: Any]] {
        let files = try FileManager.default.contentsOfDirectory(at: aside, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let file = try #require(files.first)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        #expect((object["about"] as? String)?.contains("never removes") == true)
        return try #require(object["settings"] as? [[String: Any]])
    }

    @Test(arguments: [false, true])
    func bothSpellingsAreJoinedAtLaunchWithTheAddressOpenLastWinning(portOpenLast: Bool) throws {
        let bench = HostBench()
        try olderSettings(bench)
        let last = portOpenLast ? withPort : bare
        bench.defaults.set(last.address.absoluteString, forKey: MarfaHost.addressKey)
        let libraries = libraries(bench)
        let key = libraries.libraryKey

        let choices = libraries.typeLooks.choices(for: key)
        #expect(Set(choices.keys) == [TypeID("core.note"), TypeID("core.task"), TypeID("core.event")])
        #expect(choices[TypeID("core.note")]?.date == (portOpenLast ? .edited : .created))
        #expect(libraries.searchLeaveOut.sources == (portOpenLast ? ["rss"] : ["github"]))
        #expect(libraries.sidebarLayout.hidden == ["feed"])
        for stored in [TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey, SidebarLayouts.defaultsKey] {
            #expect(storedLibraries(bench, stored) == [key], "\(stored)")
        }

        let entries = try setAside()
        #expect(entries.count == 2)
        let winner = portOpenLast ? portKey : bareKey
        let loser = portOpenLast ? bareKey : portKey
        for entry in entries {
            #expect(entry["why"] as? String == "lastOpen")
            #expect(entry["library"] as? String == key)
            #expect((entry["kept"] as? [String: Any])?["library"] as? String == winner)
            #expect((entry["setAside"] as? [[String: Any]])?.map { $0["library"] as? String } == [loser])
        }
        let note = try #require(entries.first { $0["setting"] as? String == TypeLooks.defaultsKey })
        let lost = try #require((note["setAside"] as? [[String: Any]])?.first?["value"] as? String)
        #expect(lost.contains(portOpenLast ? "created" : "edited"))
    }

    /// With no address saved, nothing says which spelling was open last. Until the copy says which Marfa it holds, the
    /// parts held differently stay under both names and do not sync; then the value that Marfa holds wins, whichever
    /// name holds it, and the other is kept in the file, which says so.
    @Test(arguments: [false, true])
    func withNothingToSayWhichWasLaterTheMarfasValueWinsOnceItIsKnown(marfaHoldsPorts: Bool) throws {
        let bench = HostBench()
        try olderSettings(bench)
        let libraries = libraries(bench)
        let provisional = libraries.host.libraryKey(for: bare)
        #expect(provisional == libraries.host.libraryKey(for: withPort))
        #expect(LibrarySettings.instance(of: provisional) == nil)
        #expect(storedLibraries(bench, TypeLooks.defaultsKey) == [bareKey, portKey])
        #expect(storedLibraries(bench, SearchLeaveOuts.defaultsKey) == [bareKey, portKey])
        #expect(storedLibraries(bench, SidebarLayouts.defaultsKey) == [provisional], "a part one name held moves")
        #expect(libraries.librarySettings.unsettled[provisional] == [TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey])
        #expect(libraries.preferences.unsettled(provisional) == [TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey])
        #expect(!FileManager.default.fileExists(atPath: aside.path))

        // The copy is read later and says its Marfa, which holds one name's values.
        let look = PreferenceUnit.row(.types, setting: "look", key: "core.note")
        let search = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        var record = PreferencesSync.Record()
        record.marfas["instance-x"] = .init(item: "settings", base: [
            look: marfaHoldsPorts ? #"{"date":"edited"}"# : #"{"date":"created"}"#,
            search: marfaHoldsPorts ? #"{"sources":["rss"],"types":[]}"# : #"{"sources":["github"],"types":[]}"#,
        ])
        record.save(bench.defaults)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        try libraries.librarySettings.settle(rename: { libraries.host.currentLibraryKey(forStored: $0) })
        #expect(libraries.librarySettings.unsettled.isEmpty)
        let key = "marfa:instance-x"
        let looks = TypeLooks(defaults: bench.defaults).choices(for: key)
        #expect(Set(looks.keys) == [TypeID("core.note"), TypeID("core.task"), TypeID("core.event")])
        #expect(looks[TypeID("core.note")]?.date == (marfaHoldsPorts ? .edited : .created))
        #expect(SearchLeaveOuts(defaults: bench.defaults).leaveOut(for: key).sources == (marfaHoldsPorts ? ["rss"] : ["github"]))
        #expect(SidebarLayouts(defaults: bench.defaults).layout(for: key).hidden == ["feed"])
        let entries = try setAside()
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0["why"] as? String == "unknown" })
        for entry in entries {
            #expect((entry["kept"] as? [String: Any])?["library"] as? String == (marfaHoldsPorts ? portKey : bareKey))
            let held = [entry["kept"] as? [String: Any]] + ((entry["setAside"] as? [[String: Any]]) ?? []).map { $0 }
            #expect(Set(held.compactMap { $0?["library"] as? String }) == [bareKey, portKey])
        }
    }

    /// With the Marfa holding neither value, the first name wins, and the other is kept.
    @Test func withNothingToSayAndTheMarfaHoldingNeitherTheFirstNameWins() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let libraries = libraries(bench)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        try libraries.librarySettings.settle(rename: { libraries.host.currentLibraryKey(forStored: $0) })
        #expect(TypeLooks(defaults: bench.defaults).choices(for: "marfa:instance-x")[TypeID("core.note")]?.date == .created)
        #expect(try setAside().allSatisfy { ($0["kept"] as? [String: Any])?["library"] as? String == bareKey })
    }

    /// A choice made while the library is named by its copy's folder is later than either earlier name's, so it wins
    /// once the Marfa is known.
    @Test func aChoiceMadeBeforeTheMarfaIsKnownWins() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let libraries = libraries(bench)
        let provisional = libraries.host.libraryKey(for: bare)
        libraries.searchLeaveOuts.update(provisional) { $0.sources = ["mastodon"] }
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        try libraries.librarySettings.settle(rename: { libraries.host.currentLibraryKey(forStored: $0) })
        #expect(SearchLeaveOuts(defaults: bench.defaults).leaveOut(for: "marfa:instance-x").sources == ["mastodon"])
        let search = try #require(try setAside().first { $0["setting"] as? String == SearchLeaveOuts.defaultsKey })
        #expect(search["why"] as? String == "later")
        #expect(Set(((search["setAside"] as? [[String: Any]]) ?? []).compactMap { $0["library"] as? String }) == [bareKey, portKey])
    }

    /// A move that cannot save what would not win moves nothing, and the settings do not sync.
    @Test func aMoveThatCannotSaveWhatLosesMovesNothing() throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        try FileManager.default.createDirectory(at: points.folder, withIntermediateDirectories: true)
        try Data().write(to: aside)
        let before = bench.defaults.data(forKey: TypeLooks.defaultsKey)
        let libraries = libraries(bench)
        #expect(bench.defaults.data(forKey: TypeLooks.defaultsKey) == before)
        #expect(storedLibraries(bench, SearchLeaveOuts.defaultsKey) == [bareKey, portKey])
        #expect(libraries.host.notices.waiting.contains { $0.title == "Settings Not Synced" })
    }

    /// The library opens offline and its copy says which Marfa it holds: the settings move to that name before the
    /// sync follows it, so the sync reads every part the Marfa holds and removes none.
    @Test func theSyncFindsEveryPartUnderTheInstanceAndRemovesNothingFromTheMarfa() async throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        bench.signIns.save("k", for: bare.address)
        bench.servers.instances.withLock { $0 = [bare: "instance-x"] }
        // The Marfa holds what the bare spelling synced last.
        let look = { (type: String) in PreferenceUnit.row(.types, setting: "look", key: type) }
        let synced: PreferenceUnits = [
            look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
            .member(.search, SearchLeaveOuts.defaultsKey): #"{"sources":["github"],"types":[]}"#,
        ]
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-x"))
        let item = await copy.add(synced)
        var record = PreferencesSync.Record()
        record.marfas["instance-x"] = .init(item: item, base: synced)
        record.last = "instance-x"
        record.save(bench.defaults)

        let libraries = libraries(bench)
        await libraries.launch()
        #expect(libraries.libraryKey == "marfa:instance-x")
        #expect(storedLibraries(bench, TypeLooks.defaultsKey) == ["marfa:instance-x"])

        let sync = PreferencesSync(defaults: bench.defaults, domain: bench.suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {}
        sync.attach(copy, library: libraries.libraryKey, name: { nil })
        await sync.flush()
        #expect(sync.standing == .syncing)
        let held = await copy.unitsHeld(item)
        for (unit, value) in synced { #expect(held[unit] == value, "\(unit)") }
        #expect(held[look("core.event")] == #"{"date":"created"}"#, "the other spelling's own part reaches the Marfa")
        #expect(held[.row(.sidebar, setting: "layout", key: "hidden")] == #"["feed"]"#)
    }

    /// A Marfa this Mac never synced takes every part both spellings held.
    @Test func aMarfaNeverSyncedTakesEveryPart() async throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(withPort.address.absoluteString, forKey: MarfaHost.addressKey)
        bench.signIns.save("k", for: withPort.address)
        bench.servers.instances.withLock { $0 = [withPort: "instance-x"] }
        let libraries = libraries(bench)
        await libraries.launch()
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-x"))
        let sync = PreferencesSync(defaults: bench.defaults, domain: bench.suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points) {}
        sync.attach(copy, library: libraries.libraryKey, name: { nil })
        await sync.flush()
        let item = try #require(await copy.activeIDs.first)
        let held = await copy.unitsHeld(item)
        let looks = held.keys.filter { if case .row(.types, "look", _) = $0 { true } else { false } }
        #expect(looks.count == 3)
        #expect(held[.row(.types, setting: "look", key: "core.note")] == #"{"date":"edited"}"#)
        #expect(held[.member(.search, SearchLeaveOuts.defaultsKey)] == #"{"sources":["rss"],"types":[]}"#)
    }

    /// A value written since the order began to be kept wins over any held before it, whichever library was open last.
    @Test func aLaterWriteWinsOverTheLibraryOpenLast() throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: bareKey)
        let leaveOuts = SearchLeaveOuts(defaults: bench.defaults)
        leaveOuts.update(portKey) { $0.sources = ["mastodon"] }
        let host = bench.host()
        try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        let key = host.libraryKey(for: bare)
        #expect(SearchLeaveOuts(defaults: bench.defaults).leaveOut(for: key).sources == ["mastodon"])
        #expect(TypeLooks(defaults: bench.defaults).choices(for: key)[TypeID("core.note")]?.date == .created, "held before, open last")
        let entries = try setAside()
        #expect(Set(entries.compactMap { $0["why"] as? String }) == ["later", "lastOpen"])
    }

    /// A move that stopped after writing the new name, before taking the old ones away, ends as it would have when
    /// the next launch tries again.
    @Test func aMoveThatStoppedPartWayEndsTheSameWhenTriedAgain() throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        _ = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: bareKey)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let key = host.libraryKey(for: bare)
        let stored = try #require(bench.defaults.data(forKey: TypeLooks.defaultsKey))
        var looks = try #require(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        looks[key] = ["core.note": ["date": "created"], "core.task": ["date": "edited"], "core.event": ["date": "created"]]
        bench.defaults.set(try JSONSerialization.data(withJSONObject: looks), forKey: TypeLooks.defaultsKey)

        let relaunched = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: bareKey)
        try relaunched.settle(rename: { host.currentLibraryKey(forStored: $0) })
        let choices = TypeLooks(defaults: bench.defaults).choices(for: key)
        #expect(Set(choices.keys).count == 3)
        #expect(choices[TypeID("core.note")]?.date == .created)
        #expect(SearchLeaveOuts(defaults: bench.defaults).leaveOut(for: key).sources == ["github"])
        #expect(storedLibraries(bench, TypeLooks.defaultsKey) == [key])
        #expect(storedLibraries(bench, SearchLeaveOuts.defaultsKey) == [key])
    }

    /// The address an earlier build named is the copy it opened then: once the address serves another Marfa, the
    /// first Marfa's settings stay its own.
    @Test func anAddressThatNowServesAnotherMarfaDoesNotTakeTheFirstsSettings() async throws {
        let bench = HostBench()
        try olderSettings(bench)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        let first = bench.location.directory(for: bare).lastPathComponent
        let libraries = libraries(bench)
        let earlier = libraries.libraryKey
        bench.servers.instances.withLock { $0 = [bare: "instance-b"] }
        try bench.location.copies.change { $0.instances[first] = "instance-a" }
        try await libraries.host.connect(address: bare.address.absoluteString, key: "k")
        #expect(libraries.libraryKey == "marfa:instance-b")
        #expect(libraries.typeLooks.choices(for: libraries.libraryKey).isEmpty)
        #expect(libraries.typeLooks.choices(for: "marfa:instance-a").count == 3, "moved from \(earlier)")
    }

    // MARK: A name that cannot be read

    /// One earlier name holds a look and a sidebar it cannot read, the other spelling good ones. The good ones move, the
    /// unreadable ones stay as stored, and the sync, followed on the library's Marfa, removes none of the Marfa's rows.
    @Test func anUnreadableNameStaysAsStoredAndTheSyncRemovesNothing() async throws {
        let bench = HostBench()
        try FileManager.default.createDirectory(at: bench.location.directory(for: bare), withIntermediateDirectories: true)
        let looks = #"{"\#(bareKey)":"broken","\#(portKey)":{"core.note":{"date":"edited"},"core.event":{"date":"created"}}}"#
        bench.defaults.set(Data(looks.utf8), forKey: TypeLooks.defaultsKey)
        bench.defaults.set(Data(#"{"\#(bareKey)":7,"\#(portKey)":{"hidden":["feed"]}}"#.utf8), forKey: SidebarLayouts.defaultsKey)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        let key = "marfa:instance-x"

        // What the bare spelling synced last.
        let look = { (type: String) in PreferenceUnit.row(.types, setting: "look", key: type) }
        let synced: PreferenceUnits = [
            look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#,
            .row(.sidebar, setting: "layout", key: "hidden"): #"["inbox"]"#,
        ]
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-x"))
        let item = await copy.add(synced)
        var record = PreferencesSync.Record()
        record.marfas["instance-x"] = .init(item: item, base: synced)
        record.last = "instance-x"
        record.save(bench.defaults)

        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: bareKey)
        let moved = try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        #expect(moved.libraries[key]?.contains(portKey) == true)
        #expect(settings.unsettled[key] == [TypeLooks.defaultsKey, SidebarLayouts.defaultsKey])
        let looksHeld = try stored(bench, TypeLooks.defaultsKey)
        #expect(looksHeld[bareKey] as? String == "broken", "kept as stored")
        #expect(looksHeld[portKey] == nil)
        #expect((looksHeld[key] as? [String: Any])?.keys.sorted() == ["core.event", "core.note"])
        let sidebar = try stored(bench, SidebarLayouts.defaultsKey)
        #expect(sidebar[bareKey] as? Int == 7)
        #expect(sidebar[key] != nil)

        let sync = PreferencesSync(
            defaults: bench.defaults, domain: bench.suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points,
            unsettled: { settings.unsettled[$0] ?? [] }) {}
        sync.attach(copy, library: key, name: { nil })
        await sync.flush()
        #expect(sync.standing == .syncing)
        let held = await copy.unitsHeld(item)
        for (unit, value) in synced { #expect(held[unit] == value, "\(unit)") }
        #expect(held[look("core.event")] == nil, "an unsettled setting sends nothing either")
        #expect(TypeLooks(defaults: bench.defaults).choices(for: key)[TypeID("core.note")]?.date == .edited, "nor takes the Marfa's")
    }

    /// An earlier name holds looks its store cannot read, which the store sets aside as it starts, before the move
    /// sees them. Each launch keeps the looks out of the sync until the copy says which Marfa it holds; then the
    /// Marfa's rows that name held stay, the other name's own look moves, the stored bytes are kept in the file, and
    /// two syncs later the Marfa and this Mac hold the same while a choice of another setting still syncs.
    @Test(arguments: [true, false])
    func whatAStoreSetsAsideAtLaunchKeepsTheMarfasRows(wholeEntry: Bool) async throws {
        let bench = HostBench()
        try FileManager.default.createDirectory(at: bench.location.directory(for: bare), withIntermediateDirectories: true)
        let bareLooks = wholeEntry ? #""broken""# : #"{"core.note":{"date":7},"core.task":{"date":"edited"}}"#
        let original = Data(#"{"\#(bareKey)":\#(bareLooks),"\#(portKey)":{"core.event":{"date":"created"}}}"#.utf8)
        bench.defaults.set(original, forKey: TypeLooks.defaultsKey)
        bench.defaults.set(Data(#"{"\#(portKey)":{"sources":["rss"],"types":[]}}"#.utf8), forKey: SearchLeaveOuts.defaultsKey)
        bench.defaults.set(bare.address.absoluteString, forKey: MarfaHost.addressKey)
        bench.signIns.save("k", for: bare.address)
        let look = { (type: String) in PreferenceUnit.row(.types, setting: "look", key: type) }
        let search = PreferenceUnit.member(.search, SearchLeaveOuts.defaultsKey)
        // What the bare spelling synced last, which only it held.
        let synced: PreferenceUnits = [look("core.note"): #"{"date":"created"}"#, look("core.task"): #"{"date":"edited"}"#]
        let copy = FakePreferencesCopy()
        await copy.set(PreferencesReadiness(filled: true, holdsType: true, tablesWhole: true, instance: "instance-x"))
        let item = await copy.add(synced)
        var record = PreferencesSync.Record()
        record.marfas["instance-x"] = .init(item: item, base: synced)
        record.last = "instance-x"
        record.save(bench.defaults)

        // Two launches before the copy says its Marfa: the store sets the looks aside once, and they stay out of the sync.
        for _ in 0..<2 {
            let libraries = libraries(bench)
            #expect(bench.defaults.array(forKey: TypeLooks.setAsideKey)?.count == 1)
            #expect(libraries.librarySettings.unsettled[libraries.libraryKey]?.contains(TypeLooks.defaultsKey) == true)
        }

        bench.servers.instances.withLock { $0 = [bare: "instance-x"] }
        let key = "marfa:instance-x"
        let expected: [TypeID: LookDate?] = [TypeID("core.note"): .created, TypeID("core.task"): .edited, TypeID("core.event"): .created]
        for launch in 0..<2 {
            let libraries = libraries(bench)
            await libraries.launch()
            #expect(libraries.libraryKey == key)
            #expect(libraries.librarySettings.unsettled.isEmpty, "launch \(launch)")
            let sync = PreferencesSync(
                defaults: bench.defaults, domain: bench.suite, enabled: true, coalescing: .milliseconds(50), restorePoints: points,
                unsettled: { libraries.librarySettings.unsettled[$0] ?? [] }) {}
            sync.attach(copy, library: key, name: { nil })
            await sync.flush()
            #expect(sync.standing == .syncing)
            let held = await copy.unitsHeld(item)
            for (unit, value) in synced { #expect(held[unit] == value, "launch \(launch): \(unit)") }
            #expect(held[look("core.event")] == #"{"date":"created"}"#, "launch \(launch)")
            #expect(held[search] == #"{"sources":["rss"],"types":[]}"#, "launch \(launch)")
            let choices = TypeLooks(defaults: bench.defaults).choices(for: key)
            #expect(choices.mapValues(\.date) == expected, "launch \(launch)")
            #expect(storedLibraries(bench, TypeLooks.defaultsKey) == [key])
            if launch == 1 {
                libraries.searchLeaveOuts.update(key) { $0.sources = ["github"] }
                await sync.flush()
                #expect(await copy.unitsHeld(item)[search] == #"{"sources":["github"],"types":[]}"#)
            }
            sync.detach()
        }
        #expect(bench.defaults.array(forKey: TypeLooks.setAsideKey)?.count == 1)

        let files = try FileManager.default.contentsOfDirectory(at: aside, includingPropertiesForKeys: nil)
        #expect(files.count == 1)
        let file = try #require(files.first)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let unreadable = try #require(object["unreadable"] as? [[String: Any]])
        #expect(unreadable.count == 1)
        #expect(unreadable.first?["library"] as? String == bareKey)
        #expect(unreadable.first?["setting"] as? String == TypeLooks.defaultsKey)
        #expect((unreadable.first?["stored"] as? String).flatMap { Data(base64Encoded: $0) } == original)
    }

    /// A removal later than the other name's value wins even where it took the last part its name held, so the name
    /// holds nothing any more.
    @Test func aRemovalOfANamesLastPartStillWins() throws {
        let bench = HostBench()
        try FileManager.default.createDirectory(at: bench.location.directory(for: bare), withIntermediateDirectories: true)
        let looks = #"{"\#(bareKey)":{"core.note":{"date":"created"}},"\#(portKey)":{"core.note":{"date":"edited"}}}"#
        bench.defaults.set(Data(looks.utf8), forKey: TypeLooks.defaultsKey)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: portKey)
        TypeLooks(defaults: bench.defaults).restore(TypeID("core.note"), in: bareKey)
        #expect(storedLibraries(bench, TypeLooks.defaultsKey) == [portKey])
        try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        #expect(TypeLooks(defaults: bench.defaults).choices(for: "marfa:instance-x")[TypeID("core.note")] == nil)
        #expect(storedLibraries(bench, TypeLooks.defaultsKey).isEmpty)
    }

    // MARK: Removals

    private func writeLook(_ bench: HostBench, _ library: String, _ type: String, _ date: String?) throws {
        var object = (try bench.defaults.data(forKey: TypeLooks.defaultsKey).flatMap { try JSONSerialization.jsonObject(with: $0) as? [String: Any] }) ?? [:]
        var types = object[library] as? [String: Any] ?? [:]
        types[type] = date.map { ["date": $0] }
        object[library] = types.isEmpty ? nil : types
        bench.defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: TypeLooks.defaultsKey)
    }

    /// A look removed under one name and written under the other: the later of the two wins, a removal as much as a
    /// value, and what lost is kept in the file. Parts only one name held stay.
    @Test(arguments: [false, true])
    func aRemovalAndAWriteTheLaterWins(removedFirst: Bool) throws {
        let bench = HostBench()
        try olderSettings(bench)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: nil)
        let remove = { TypeLooks(defaults: bench.defaults).restore(TypeID("core.note"), in: self.bareKey) }
        if removedFirst {
            remove()
            try writeLook(bench, portKey, "core.note", "occurred")
        } else {
            try writeLook(bench, portKey, "core.note", "occurred")
            remove()
        }
        try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        let key = "marfa:instance-x"
        let choices = TypeLooks(defaults: bench.defaults).choices(for: key)
        #expect(choices[TypeID("core.task")]?.date == .edited, "only the bare spelling held it")
        #expect(choices[TypeID("core.event")]?.date == .created, "only the other spelling held it")
        let note = try #require(try setAside().first { $0["part"] as? String == "types.look.core.note" })
        #expect(note["why"] as? String == "later")
        let kept = try #require(note["kept"] as? [String: Any])
        let lost = try #require((note["setAside"] as? [[String: Any]])?.first)
        if removedFirst {
            #expect(choices[TypeID("core.note")]?.date == .occurred)
            #expect(kept["library"] as? String == portKey)
            #expect(lost["library"] as? String == bareKey)
            #expect(lost["removed"] as? Bool == true)
        } else {
            #expect(choices[TypeID("core.note")] == nil, "the removal stands")
            #expect(kept["library"] as? String == bareKey)
            #expect(kept["removed"] as? Bool == true)
            #expect((lost["value"] as? String)?.contains("occurred") == true)
        }

        // The removal moves with the library, so a later join with the same old value does not bring it back.
        if !removedFirst {
            try writeLook(bench, bareKey, "core.note", "edited")
            try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
            #expect(TypeLooks(defaults: bench.defaults).choices(for: key)[TypeID("core.note")]?.date == .edited, "written after the removal")
        }
    }

    /// A look removed and then chosen again under the same name is the later write.
    @Test func aLookRemovedAndChosenAgainIsTheLaterWrite() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: nil)
        TypeLooks(defaults: bench.defaults).restore(TypeID("core.note"), in: portKey)
        try writeLook(bench, portKey, "core.note", "occurred")
        try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        #expect(TypeLooks(defaults: bench.defaults).choices(for: "marfa:instance-x")[TypeID("core.note")]?.date == .occurred)
    }

    /// What a store sets aside because it cannot read it is no removal of the person's, so the other name's value moves.
    @Test func whatAStoreSetsAsideIsNoRemoval() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        let settings = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: nil)
        var object = try stored(bench, TypeLooks.defaultsKey)
        object[bareKey] = "written by a later version"
        bench.defaults.set(try JSONSerialization.data(withJSONObject: object), forKey: TypeLooks.defaultsKey)
        _ = TypeLooks(defaults: bench.defaults)
        #expect(bench.defaults.array(forKey: TypeLooks.setAsideKey)?.count == 1)
        try settings.settle(rename: { host.currentLibraryKey(forStored: $0) })
        let choices = TypeLooks(defaults: bench.defaults).choices(for: "marfa:instance-x")
        #expect(choices[TypeID("core.note")]?.date == .edited)
        #expect(choices[TypeID("core.event")]?.date == .created)
    }

    /// A look removed while a store sets something aside elsewhere in the same launch is still no removal, until the
    /// store's own value is seen to change.
    @Test func aLookRemovedAtLaunchBeforeTheOrderWasReadIsNotInferred() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let host = bench.host()
        host.bindOrigin(of: bare)
        let folder = bench.location.directory(for: bare).lastPathComponent
        try bench.location.copies.change { $0.instances[folder] = "instance-x" }
        _ = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: nil)
        // Between launches, an earlier name's looks went with nothing seeing them go.
        try writeLook(bench, bareKey, "core.note", nil)
        try writeLook(bench, bareKey, "core.task", nil)
        bench.defaults.set([Data("{}".utf8)], forKey: TypeLooks.setAsideKey)
        let relaunched = LibrarySettings(defaults: bench.defaults, aside: aside, lastOpen: nil)
        try relaunched.settle(rename: { host.currentLibraryKey(forStored: $0) })
        #expect(TypeLooks(defaults: bench.defaults).choices(for: "marfa:instance-x")[TypeID("core.note")]?.date == .edited)
    }

    // MARK: An address that later opens another Marfa

    /// The names an earlier build gave by address are read as the folder they first opened, even where the move then
    /// fails: once the address opens another Marfa's copy, that Marfa takes none of them, whichever spelling was saved.
    @Test(arguments: [false, true])
    func anAddressKeepsTheFolderItFirstOpenedAfterAFailedMove(portSaved: Bool) async throws {
        let bench = HostBench()
        try olderSettings(bench)
        let saved = portSaved ? withPort : bare
        bench.defaults.set(saved.address.absoluteString, forKey: MarfaHost.addressKey)
        try FileManager.default.createDirectory(at: points.folder, withIntermediateDirectories: true)
        try Data().write(to: aside)
        let libraries = libraries(bench)
        #expect(libraries.host.notices.waiting.contains { $0.title == "Settings Not Synced" })
        let first = bench.location.directory(for: saved).lastPathComponent
        #expect(bench.location.copies.current.addresses == [bareKey: first, portKey: first])

        try FileManager.default.removeItem(at: aside)
        try bench.location.copies.change { $0.instances[first] = "instance-a" }
        bench.servers.instances.withLock { $0 = [saved: "instance-b"] }
        try await libraries.host.connect(address: saved.address.absoluteString, key: "k")
        #expect(libraries.libraryKey == "marfa:instance-b")
        #expect(bench.location.directory(for: saved).lastPathComponent != first)
        #expect(libraries.typeLooks.choices(for: "marfa:instance-b").isEmpty)
        #expect(libraries.searchLeaveOut.sources.isEmpty)
        #expect(libraries.sidebarLayout.hidden.isEmpty)
        #expect(libraries.typeLooks.choices(for: "marfa:instance-a").count == 3)
        for stored in [TypeLooks.defaultsKey, SearchLeaveOuts.defaultsKey, SidebarLayouts.defaultsKey] {
            #expect(storedLibraries(bench, stored) == ["marfa:instance-a"], "\(stored)")
        }
    }
}
