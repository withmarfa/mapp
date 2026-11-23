import Foundation
import Marfa
import Testing
@testable import MarfaMac

@Suite struct PreferencesTypeTests {
    /// Every Mac is another OAuth client, and only the one that registered the type may replace it.
    @Test func theTypeNeverChangesShape() throws {
        let fixture = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/app.mapp.preferences.json")
        let frozen = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture)) as? NSDictionary
        let declared = try JSONSerialization.jsonObject(with: Data(PreferencesType.definition.json().utf8)) as? NSDictionary
        #expect(declared == frozen, "The type cannot change: see withmarfa/marfa#3462. Add a setting as a member of a field or a setting word in a table.")
    }

    @Test func aRowIDIsTheSameOnEveryMacAndShapedAsAUUIDv7() {
        let id = PreferencesMerge.rowID(.commands, setting: "shortcut", key: "newItem")
        // The id step 0 wrote on the demo instance, which took it.
        #expect(id == "718b5ad7-b598-7dd4-af21-c7ad31a98dd4")
        #expect(id.wholeMatch(of: /[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/) != nil)
        #expect(PreferencesMerge.rowID(.commands, setting: "shortcut", key: "newItems") != id)
    }
}

@Suite struct PreferencesMapTests {
    @Test func everyMacSettingIsSyncedOrStaysOnThisMac() {
        let synced = Set(PreferencesMap.syncedKeys)
        let staying = Set(PreferencesMap.staysOnMac)
        for key in MacSettings.keys {
            #expect(synced.contains(key) != staying.contains(key), "\(key) is neither synced nor named as staying on this Mac, or both")
        }
        #expect(synced.isSubset(of: Set(MacSettings.keys)))
        #expect(staying.isSubset(of: Set(MacSettings.keys)))
        #expect(PreferencesMap.syncedKeys.count == synced.count)
    }

    @Test func eachSettingOwnsItsOwnPlaces() {
        let units: [PreferenceUnit] = PreferencesMap.synced.map { setting in
            switch setting.place {
            case .member(let field), .serverMember(let field, _): .member(field, setting.key)
            case .rows(let table, let word, _, _, _, _), .serverRows(let table, let word, _), .set(let table, let word),
                 .placeRows(let table, let word, _): .row(table, setting: word, key: "x")
            case .sidebar: .row(.sidebar, setting: PreferencesSidebar.layoutSetting, key: "order")
            }
        }
        for unit in units {
            #expect(PreferencesMap.synced.filter { $0.owns(unit) }.count == 1, "\(unit)")
        }
    }
}

@Suite struct PreferencesValuesTests {
    private func defaults() throws -> UserDefaults {
        let suite = "MarfaMacTests.Preferences.\(UUID().uuidString)"
        return try #require(UserDefaults(suiteName: suite))
    }

    private func setting(_ key: String) throws -> SyncedSetting {
        try #require(PreferencesMap.synced.first { $0.key == key })
    }

    private func units(_ reading: PreferenceReading) -> PreferenceUnits {
        if case .units(let units) = reading { units } else { [:] }
    }

    @Test func aMemberKeepsItsKindThroughTheMarfa() throws {
        let here = try defaults(), there = try defaults()
        here.set(true, forKey: PageKey.foldsHeadings)
        here.set(1.25, forKey: LineSpacing.key)
        here.set(3, forKey: PageKey.titleLines)
        here.set("serif", forKey: AppearanceKey.textFont)
        for key in [PageKey.foldsHeadings, LineSpacing.key, PageKey.titleLines, AppearanceKey.textFont] {
            let setting = try setting(key)
            setting.write(units(setting.read(here, library: "a")), to: there, library: "a")
        }
        #expect(there.object(forKey: PageKey.foldsHeadings) as? Bool == true)
        #expect(there.double(forKey: LineSpacing.key) == 1.25)
        #expect(there.integer(forKey: PageKey.titleLines) == 3)
        #expect(there.string(forKey: AppearanceKey.textFont) == "serif")
        #expect(units(try setting(PageKey.foldsHeadings).read(there, library: "a")) == [.member(.editor, PageKey.foldsHeadings): "true"])
    }

    @Test func aTablesWidthsStayWithTheViewOnThisMac() throws {
        let here = try defaults(), there = try defaults()
        here.set(#"{"v1":{"layout":"table","widths":"aGVyZQ=="}}"#, forKey: ViewLayouts.key)
        there.set(#"{"v1":{"layout":"list","widths":"dGhlcmU="}}"#, forKey: ViewLayouts.key)
        let setting = try setting(ViewLayouts.key)
        let read = units(setting.read(here, library: "a"))
        #expect(read == [.row(.views, setting: "viewLayout", key: "v1"): #"{"layout":"table"}"#])
        setting.write(read, to: there, library: "a")
        #expect(there.string(forKey: ViewLayouts.key) == #"{"v1":{"layout":"table","widths":"dGhlcmU="}}"#)
    }

    @Test func aServersEntryIsTheOnlyOneSynced() throws {
        let here = try defaults()
        let looks = #"{"a":{"core.note":{"date":"created"}},"b":{"core.task":{"date":"due"}}}"#
        here.set(Data(looks.utf8), forKey: TypeLooks.defaultsKey)
        let setting = try setting(TypeLooks.defaultsKey)
        let read = units(setting.read(here, library: "a"))
        #expect(read == [.row(.types, setting: "look", key: "core.note"): #"{"date":"created"}"#])
        setting.write([.row(.types, setting: "look", key: "core.event"): #"{"date":"start"}"#], to: here, library: "a")
        let stored = try #require(here.data(forKey: TypeLooks.defaultsKey))
        #expect(String(decoding: stored, as: UTF8.self) == #"{"a":{"core.event":{"date":"start"}},"b":{"core.task":{"date":"due"}}}"#)
    }

    @Test func theSidebarSplitsIntoRowsAndComesBackWhole() throws {
        let layout: [String: Any] = [
            "hidden": ["recents", "inbox"], "order": ["all", "view:1"], "colors": ["view:1": "blue", "sources": "red"],
            "homes": ["collection:9": "g1"], "tabs": [["id": "home"]],
        ]
        let units = try #require(PreferencesSidebar.rows(of: layout))
        #expect(units[.row(.sidebar, setting: "layout", key: "hidden")] == #"["inbox","recents"]"#)
        #expect(units[.row(.sidebar, setting: "color", key: "view:1")] == #""blue""#)
        #expect(units[.row(.sidebar, setting: "home", key: "collection:9")] == #""g1""#)
        let (joined, unreadable) = PreferencesSidebar.layout(from: units)
        #expect(unreadable.isEmpty)
        #expect(NSDictionary(dictionary: joined) == NSDictionary(dictionary: layout.merging(["hidden": ["inbox", "recents"]]) { _, new in new }))
    }

    @Test func aRowThatIsNotJSONIsSetAsideAndTheStoreKeepsItsDefault() throws {
        let here = try defaults()
        let setting = try setting(PagePlacements.key)
        setting.write([.row(.types, setting: "pagePlacements", key: "core.note"): "{not json"], to: here, library: "a")
        #expect(here.stringArray(forKey: PagePlacements.setAsideKey) == ["{not json"])
        #expect(here.string(forKey: PagePlacements.key) == nil)
    }

    @Test func storedTextThisMacCannotReadIsNeitherSentNorWrittenOver() throws {
        let here = try defaults()
        here.set(Data("not json".utf8), forKey: PlaceDefaults.key)
        #expect(try setting(PlaceDefaults.key).read(here, library: "a") == .unreadable)
    }

    @Test func includedSubtypesAreARowEach() throws {
        let here = try defaults()
        IncludedSubtypes.update(in: here) { $0.set("core.task", included: true); $0.set("aic.ticket", included: true) }
        let setting = try setting(IncludedSubtypes.key)
        let read = units(setting.read(here, library: "a"))
        #expect(Set(read.keys) == [.row(.types, setting: "includedSubtypes", key: "core.task"), .row(.types, setting: "includedSubtypes", key: "aic.ticket")])
        setting.write([.row(.types, setting: "includedSubtypes", key: "core.task"): "true"], to: here, library: "a")
        #expect(IncludedSubtypes.stored(in: here).types == ["core.task"])
    }
}

@Suite struct PreferencesMergeTests {
    let theme = PreferenceUnit.member(.appearance, "theme")
    let accent = PreferenceUnit.member(.appearance, "accentColor")
    let row = PreferenceUnit.row(.commands, setting: "shortcut", key: "newItem")

    @Test func aChangeOnOneSideGoesToTheOther() {
        let outcome = PreferencesMerge.reconcile(
            local: [theme: #""dark""#, accent: #""blue""#], remote: [theme: #""light""#, accent: #""red""#],
            base: [theme: #""light""#, accent: #""blue""#])
        #expect(outcome.merged == [theme: #""dark""#, accent: #""red""#])
        #expect(outcome.toRemote == [theme])
        #expect(outcome.toLocal == [accent])
    }

    @Test func nothingChangedWritesNothing() {
        let held: PreferenceUnits = [theme: #""dark""#, row: "{}"]
        let outcome = PreferencesMerge.reconcile(local: held, remote: held, base: held)
        #expect(outcome.toLocal.isEmpty && outcome.toRemote.isEmpty)
    }

    @Test func bothChangedKeepsThisMacsWhichIsTheLaterWrite() {
        let outcome = PreferencesMerge.reconcile(local: [row: "1"], remote: [row: "2"], base: [row: "0"])
        #expect(outcome.merged[row] == "1")
        #expect(outcome.toRemote == [row])
    }

    @Test func aRemovalIsAChangeToo() {
        let outcome = PreferencesMerge.reconcile(local: [:], remote: [row: "1"], base: [row: "1"])
        #expect(outcome.merged[row] == nil)
        #expect(outcome.toRemote == [row])
    }

    @Test func aFrozenSettingIsLeftAlone() {
        let outcome = PreferencesMerge.reconcile(local: [:], remote: [row: "2"], base: [row: "1"], frozen: { $0 == row })
        #expect(outcome.merged[row] == "1")
        #expect(outcome.toLocal.isEmpty && outcome.toRemote.isEmpty)
    }

    @Test func adoptingKeepsWhatTheItemHoldsAndFillsWhatItLacks() {
        let outcome = PreferencesMerge.adopt(remote: [theme: #""light""#], local: [theme: #""dark""#, row: "1"])
        #expect(outcome.merged == [theme: #""light""#, row: "1"])
        #expect(outcome.toLocal == [theme])
        #expect(outcome.toRemote == [row])
    }

    @Test func theItemMadeFirstIsFilledFromTheOthers() {
        let filled = PreferencesMerge.filling([theme: "a"], from: [[theme: "b", row: "c"]])
        #expect(filled == [theme: "a", row: "c"])
    }

    /// Two Macs change two members of one field at once: the server keeps one field and writes the other Mac's to a
    /// conflicted copy, and each member's own write survives. Only the member this Mac sent is reclaimed.
    @Test func membersOfOneFieldChangedOnTwoMacsAreBothKept() {
        let base: PreferenceUnits = [theme: #""light""#, accent: #""blue""#]
        let local: PreferenceUnits = [theme: #""light""#, accent: #""red""#]
        let remote: PreferenceUnits = [theme: #""dark""#, accent: #""blue""#]
        let conflicted: PreferenceUnits = [accent: #""red""#]
        let outcome = PreferencesMerge.reconcile(
            local: local, remote: remote, base: PreferencesMerge.base(base, reclaiming: conflicted, local: local, remote: remote))
        #expect(outcome.merged == [theme: #""dark""#, accent: #""red""#])
        #expect(outcome.toLocal == [theme])
        #expect(outcome.toRemote == [accent])
    }
}

@Suite(.hangLimit) struct PreferenceAnswersTests {
    private func write(_ id: String, _ verdict: Marfa.Verdict?) -> Marfa.QueuedWrite {
        Marfa.QueuedWrite(id: id, kind: .updateItem, itemId: "item", idempotencyKey: id, verdict: verdict, queuedAt: "")
    }

    /// Each answer is kept for the sync to take once, by the verdict it carries; a write with no answer yet is not.
    @Test func answersAreKeptByVerdictAndTakenOnce() async {
        let answers = PreferenceAnswers()
        var arrivals = answers.arrivals().makeAsyncIterator()
        answers.receive([
            write("a", .accepted), write("b", .merged(fields: ["appearance"])),
            write("c", .conflicted(siblingId: "sibling", fields: ["appearance"])), write("d", .dead), write("e", nil),
        ])
        #expect(await arrivals.next() != nil)
        #expect(answers.take() == ["a": .taken, "b": .taken, "c": .lost, "d": .notTaken])
        #expect(answers.take().isEmpty)
    }
}
