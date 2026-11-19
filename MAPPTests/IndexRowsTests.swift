import Foundation
import Testing
@testable import MAPP

struct IndexRowsTests {
    private let catalogue = FakeItemLibrary.testCatalogue
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func item(_ title: String, type: String = "core.note", source: String? = nil, minutes: Double = 0) -> Item {
        var item = FakeItemLibrary.note(title, modified: base + minutes * 60)
        item.type = TypeID(type)
        item.source = source
        return item
    }

    @Test func aSourceCountsItsItemsAndKeepsTheLatestChange() throws {
        let rows = IndexRows.sources(
            of: [item("a", source: "rss", minutes: 5), item("b", source: "rss", minutes: 9), item("c", source: "agents", minutes: 1)],
            catalogue: catalogue)
        let rss = try #require(rows.first { $0.title == "rss" })
        #expect(rss.count == 2)
        #expect(rss.latest == base + 9 * 60)
        #expect(rss.place == .source("rss"))
    }

    @Test func itemsWithNoSourceBelongToNone() {
        let rows = IndexRows.sources(of: [item("a"), item("b", source: ""), item("c", source: "x")], catalogue: catalogue)
        #expect(rows.map(\.title) == ["x"])
    }

    @Test func sourcesAreInNameOrderAndAgreeWithTheLibrarysCounts() {
        let items = [item("a", source: "b"), item("b", source: "A"), item("c", source: "b"), item("d", source: "10"), item("e", source: "9")]
        let rows = IndexRows.sources(of: items, catalogue: catalogue)
        #expect(rows.map(\.title) == ["9", "10", "A", "b"])
        let library = FakeItemLibrary(items: items, now: base)
        #expect(Dictionary(uniqueKeysWithValues: rows.map { ($0.title, $0.count) })
            == Dictionary(uniqueKeysWithValues: library.sourceCounts.map { ($0.code, $0.count) }))
    }

    @Test func theBreakdownIsByTypeMostFirstThenByLabel() {
        let items = [
            item("a", type: "core.task"), item("b", type: "core.note"), item("c", type: "core.note"),
            item("d", type: "core.task"), item("e", type: "test.project"),
        ]
        let shares = IndexRows.breakdown(of: items, catalogue: catalogue)
        #expect(shares.map(\.label) == ["Note", "Task", "Project"])
        #expect(shares.map(\.count) == [2, 2, 1])
        #expect(shares.reduce(0) { $0 + $1.count } == items.count)
    }

    @Test func theTypeLineNamesThreeAndCountsTheRest() {
        let shares = (1...5).map { TypeShare(type: TypeID("t.\($0)"), label: "T\($0)", icon: nil, count: 1) }
        let line = IndexRows.summary(of: shares)
        #expect(line.contains("T1") && line.contains("T3"))
        #expect(!line.contains("T4"))
        #expect(line.contains("2"))
        #expect(IndexRows.summary(of: []) == "")
    }

    @Test func aCollectionCountsItsMembersAndNamesItsOwnType() throws {
        let collection = item("Garden", type: "test.collection", minutes: 100)
        let members = [item("a", minutes: 3), item("b", type: "core.task", minutes: 7)]
        let rows = IndexRows.collections([collection], membersOf: { _ in members }, catalogue: catalogue)
        let row = try #require(rows.first)
        #expect(row.place == .collection(collection.id))
        #expect(row.count == 2)
        #expect(row.breakdown.count == 2)
        #expect(row.tier == .library)
    }

    @Test func aCollectionsDateIsItsOwnChangeAndNotItsLatestMembers() throws {
        let collection = item("Garden", type: "test.collection", minutes: 100)
        let members = [item("a", minutes: 300)]
        let row = try #require(IndexRows.collections([collection], membersOf: { _ in members }, catalogue: catalogue).first)
        #expect(row.latest == base + 100 * 60)
    }

    @Test func anEmptyCollectionHasItsOwnDateAndNoTypes() throws {
        let rows = IndexRows.collections([item("Empty", type: "test.collection", minutes: 4)], membersOf: { _ in [] }, catalogue: catalogue)
        let row = try #require(rows.first)
        #expect(row.count == 0)
        #expect(row.latest == base + 4 * 60)
        #expect(row.breakdown.isEmpty)
    }

    @Test func aCollectionNamesTheSourceThatWroteItAsTheServerNamesIt() throws {
        let named = item("Named", type: "test.collection", source: "readwise")
        let unnamed = item("Unnamed", type: "test.collection", source: "x-code")
        let none = item("None", type: "test.collection")
        let blank = item("Blank", type: "test.collection", source: "")
        let directory = SourceDirectory(infos: ["readwise": readwise])
        let rows = IndexRows.collections([named, unnamed, none, blank], membersOf: { _ in [] }, catalogue: catalogue, directory: directory)
        #expect(rows.map(\.sourceName) == ["Readwise", "x-code", "", ""])
    }

    @Test func onlyACollectionThatIsNotReadOnlyCanBeDeleted() throws {
        var locked = item("Locked", type: "test.collection")
        locked.readOnly = true
        let open = item("Open", type: "test.collection")
        let rows = IndexRows.collections([locked, open], membersOf: { _ in [] }, catalogue: catalogue)
        #expect(rows.map(\.canDelete) == [false, true])
        #expect(IndexRows.sources(of: [item("a", source: "rss")], catalogue: catalogue).allSatisfy { !$0.canDelete })
    }

    @Test func theLatestItemsAreTheNewestFoundInOnePass() {
        let items = (0..<30).map { item("n\($0)", minutes: Double(($0 * 7) % 30)) }
        let newest = IndexRows.newest(items, limit: 4)
        #expect(newest.map(\.modified) == items.map(\.modified).sorted(by: >).prefix(4).map { $0 })
        #expect(IndexRows.newest(Array(items.prefix(2)), limit: 4).count == 2)
        #expect(IndexRows.newest(items, limit: 0).isEmpty)
        #expect(IndexRows.newest([], limit: 4).isEmpty)
    }

    @Test func sourcesAndTheirCountsComeFromOneGrouping() {
        let items = [item("a", source: "b"), item("b", source: "A"), item("c", source: "b"), item("d")]
        let library = FakeItemLibrary(items: items, now: base)
        let groups = IndexRows.groupedBySource(library.items(in: .allItems))
        #expect(library.sourceCounts.map(\.code) == groups.map(\.code))
        #expect(library.sourceCounts.map(\.count) == groups.map(\.items.count))
    }

    // MARK: Names, marks and counts from the server

    private let readwise = SourceInfo(code: "readwise", name: "Readwise", mark: "simple-icons:readwise", hasChosenName: true)
    private let github = SourceInfo(code: "gh", name: "GitHub", mark: nil, hasChosenName: false)

    private func directory(counts: [String: Int]? = nil) -> SourceDirectory {
        SourceDirectory(infos: ["readwise": readwise, "gh": github], counts: counts)
    }

    @Test func aSourceRowShowsTheServersNameAndMarkAndKeepsTheCodeAsItsPlace() throws {
        let rows = IndexRows.sources(
            of: [item("a", source: "readwise"), item("b", source: "gh"), item("c", source: "unnamed")], catalogue: catalogue,
            directory: directory())
        let row = try #require(rows.first { $0.title == "Readwise" })
        #expect(row.place == .source("readwise"))
        #expect(row.icon == .type("simple-icons:readwise"))
        #expect(try #require(rows.first { $0.title == "GitHub" }).icon == .symbol(SourceTile.fallbackSymbol))
        // A source the server has not named shows its code.
        #expect(rows.map(\.title) == ["GitHub", "Readwise", "unnamed"])
    }

    @Test func rowsAreInOrderOfTheNameShown() {
        let rows = IndexRows.sources(of: [item("a", source: "a-code"), item("b", source: "z-code")], catalogue: catalogue, directory: SourceDirectory(
            infos: ["a-code": .init(code: "a-code", name: "Zebra", mark: nil, hasChosenName: true), "z-code": .init(code: "z-code", name: "Apple", mark: nil, hasChosenName: true)]))
        #expect(rows.map(\.title) == ["Apple", "Zebra"])
    }

    @Test func aRowCountsWhatTheServerCountedAndTheLoadedItemsUntilItHas() throws {
        let items = [item("a", source: "readwise"), item("b", source: "readwise")]
        let before = IndexRows.sources(of: items, catalogue: catalogue, directory: directory())
        #expect(before.first?.count == 2)
        let after = IndexRows.sources(of: items, catalogue: catalogue, directory: directory(counts: ["readwise": 40]))
        #expect(after.first?.count == 40)
    }

    @Test func theLibrarysSourceCountsUseTheServersNamesAndCounts() {
        let library = FakeItemLibrary(items: [item("a", source: "readwise"), item("b", source: "gh")], now: base)
        library.sources = directory(counts: ["readwise": 7, "gh": 3])
        #expect(library.sourceCounts.map(\.name) == ["GitHub", "Readwise"])
        #expect(library.sourceCounts.map(\.count) == [3, 7])
        #expect(library.sourceCounts.map(\.code) == ["gh", "readwise"])
    }

    @Test func onceTheServerHasAnsweredEverySourceWithItemsHasARowAndNoOtherDoes() {
        let items = [item("a", source: "readwise"), item("b", source: "loaded-only")]
        let rows = IndexRows.sources(of: items, catalogue: catalogue, directory: directory(counts: ["readwise": 4, "gh": 9, "empty": 0]))
        #expect(rows.map(\.title) == ["GitHub", "Readwise"])
        #expect(rows.map(\.count) == [9, 4])
        // A source whose items are not loaded still has its row, with no types.
        #expect(rows.first?.types == "")
        #expect(rows.last?.types.isEmpty == false)
        #expect(IndexRows.sources(of: items, catalogue: catalogue, directory: directory(counts: [:])).isEmpty)
    }

    @Test func theSidebarsSourcesAreTheRowsSources() {
        let library = FakeItemLibrary(items: [item("a", source: "readwise")], now: base)
        library.sources = directory(counts: ["readwise": 4, "gh": 9, "empty": 0])
        #expect(library.sourceCounts.map(\.name) == IndexRows.sources(of: library.items(in: .allItems), catalogue: catalogue, directory: library.sources).map(\.title))
    }

    @Test func theInspectorsMarkIsTheSourcesMarkOrNone() {
        #expect(SourceTile.icon(for: readwise) == .type("simple-icons:readwise"))
        #expect(SourceTile.icon(for: .unnamed("x")) == .symbol(SourceTile.fallbackSymbol))
        #expect(directory().info("missing") == .unnamed("missing"))
        #expect(directory().name("missing") == "missing")
    }
}

struct IndexPreferencesTests {
    private func defaults() -> UserDefaults {
        let suite = "IndexPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aNewPageShowsAllAndItsDefaultOrder() {
        let defaults = defaults()
        for place in IndexPlace.allCases {
            #expect(IndexPreferences.tab(for: place, in: defaults) == .all)
            #expect(IndexPreferences.sort(for: place, in: defaults) == place.defaultSort)
        }
        #expect(IndexPlace.sources.defaultSort == IndexSort(column: .count, ascending: false))
        #expect(IndexPlace.collections.defaultSort == IndexSort(column: .name, ascending: true))
    }

    @Test func eachPageHasItsOwnColumns() {
        #expect(IndexPlace.collections.columns == [.name, .source, .count, .latest])
        #expect(IndexPlace.sources.columns == [.name, .types, .count, .latest])
        for place in IndexPlace.allCases { #expect(place.columns.contains(place.defaultSort.column)) }
    }

    @Test func aKeptSortOfAColumnThePageLacksFallsBack() {
        let defaults = defaults()
        defaults.set("types.asc", forKey: IndexPlace.collections.sortKey)
        #expect(IndexPreferences.sort(for: .collections, in: defaults) == IndexPlace.collections.defaultSort)
        defaults.set("source.desc", forKey: IndexPlace.collections.sortKey)
        #expect(IndexPreferences.sort(for: .collections, in: defaults) == IndexSort(column: .source, ascending: false))
        defaults.set("source.desc", forKey: IndexPlace.sources.sortKey)
        #expect(IndexPreferences.sort(for: .sources, in: defaults) == IndexPlace.sources.defaultSort)
    }

    @Test func eachPageKeepsItsOwnTabAndSort() {
        let defaults = defaults()
        IndexPreferences.set(.keys, for: .sources, in: defaults)
        IndexPreferences.set(.fromApps, for: .collections, in: defaults)
        IndexPreferences.set(IndexSort(column: .latest, ascending: false), for: .sources, in: defaults)
        #expect(IndexPreferences.tab(for: .sources, in: defaults) == .keys)
        #expect(IndexPreferences.tab(for: .collections, in: defaults) == .fromApps)
        #expect(IndexPreferences.sort(for: .sources, in: defaults) == IndexSort(column: .latest, ascending: false))
        #expect(IndexPreferences.sort(for: .collections, in: defaults) == IndexPlace.collections.defaultSort)
    }

    @Test func anUnreadableOrForeignStoredValueFallsBack() {
        let defaults = defaults()
        defaults.set("kanban", forKey: IndexPlace.sources.tabKey)
        defaults.set("sideways", forKey: IndexPlace.sources.sortKey)
        #expect(IndexPreferences.tab(for: .sources, in: defaults) == .all)
        #expect(IndexPreferences.sort(for: .sources, in: defaults) == IndexPlace.sources.defaultSort)
        // A tab of the other page is not one of this page's.
        defaults.set("yours", forKey: IndexPlace.sources.tabKey)
        #expect(IndexPreferences.tab(for: .sources, in: defaults) == .all)
        defaults.set("name.up", forKey: IndexPlace.collections.sortKey)
        #expect(IndexPreferences.sort(for: .collections, in: defaults) == IndexPlace.collections.defaultSort)
    }

    @Test func theTabsAreAllThenTheTwoKindsOfThePage() {
        #expect(IndexPlace.collections.tabs == [.all, .yours, .fromApps])
        #expect(IndexPlace.sources.tabs == [.all, .apps, .keys])
    }

    @Test func onlyTheTwoIndexesAreIndexPages() {
        #expect(IndexPlace(.sources) == .sources)
        #expect(IndexPlace(.collections) == .collections)
        #expect(IndexPlace(.allItems) == nil)
        #expect(IndexPlace(.source("rss")) == nil)
    }
}

@MainActor
struct IndexRowsModelTests {
    @Test func changingThePlaceNeverShowsTheOldPlacesRows() {
        let library = FakeItemLibrary(items: [FakeItemLibrary.note("a", modified: .now)], now: .now)
        var note = FakeItemLibrary.note("n", modified: .now)
        note.source = "rss"
        let model = IndexRowsModel()
        model.follow(.sources, in: FakeItemLibrary(items: [note], now: .now))
        #expect(model.rows(for: .sources).map(\.title) == ["rss"])
        #expect(model.rows(for: .collections).isEmpty)
        #expect(!model.isBuilt(for: .collections))

        model.follow(.collections, in: library)
        #expect(model.rows(for: .sources).isEmpty)
        #expect(!model.isBuilt(for: .sources))
        #expect(model.isBuilt(for: .collections))
        model.stop()
    }
}
