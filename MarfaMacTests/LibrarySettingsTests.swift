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

    /// With no address saved, nothing says which spelling was open last: both values are kept, one in use and the
    /// other in the file, which says so.
    @Test func withNothingToSayWhichWasLaterBothValuesAreKept() throws {
        let bench = HostBench()
        try olderSettings(bench)
        let libraries = libraries(bench)
        let key = libraries.host.libraryKey(for: bare)
        #expect(key == libraries.host.libraryKey(for: withPort))
        #expect(Set(libraries.typeLooks.choices(for: key).keys).count == 3)
        let entries = try setAside()
        #expect(entries.count == 2)
        #expect(entries.allSatisfy { $0["why"] as? String == "unknown" })
        for entry in entries {
            let held = [entry["kept"] as? [String: Any]] + ((entry["setAside"] as? [[String: Any]]) ?? []).map { $0 }
            #expect(Set(held.compactMap { $0?["library"] as? String }) == [bareKey, portKey])
        }
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
}
