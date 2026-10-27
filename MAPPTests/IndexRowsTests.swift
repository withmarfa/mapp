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
            == Dictionary(uniqueKeysWithValues: library.sourceCounts.map { ($0.name, $0.count) }))
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

    @Test func manyTypesCollapseIntoOneOtherShareThatKeepsTheTotal() {
        let shares = (1...6).map { TypeShare(type: TypeID("t.\($0)"), label: "T\($0)", count: 10 - $0) }
        let collapsed = IndexRows.collapsing(shares, limit: 4)
        #expect(collapsed.count == 4)
        #expect(collapsed.prefix(3).map(\.label) == ["T1", "T2", "T3"])
        #expect(collapsed.last?.type == nil)
        #expect(collapsed.reduce(0) { $0 + $1.count } == shares.reduce(0) { $0 + $1.count })
        #expect(IndexRows.collapsing(Array(shares.prefix(4)), limit: 4) == Array(shares.prefix(4)))
    }

    @Test func theTypeLineNamesThreeAndCountsTheRest() {
        let shares = (1...5).map { TypeShare(type: TypeID("t.\($0)"), label: "T\($0)", count: 1) }
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
        #expect(row.latest == base + 7 * 60)
        #expect(row.breakdown.count == 2)
        #expect(row.secondary == TypeSymbol.label(for: collection.type, in: catalogue))
    }

    @Test func anEmptyCollectionHasNoLatestItemAndSortsAsTheOldest() throws {
        let rows = IndexRows.collections([item("Empty", type: "test.collection")], membersOf: { _ in [] }, catalogue: catalogue)
        let row = try #require(rows.first)
        #expect(row.count == 0)
        #expect(row.latest == nil)
        #expect(row.latestOrOldest == .distantPast)
        #expect(row.breakdown.isEmpty)
    }

    @Test func everySourceHasTheSameIconUntilItsKindIsKnown() {
        #expect(SourceTile.symbol(forSource: "workbench-folder") == SourceTile.symbol(forSource: "agents"))
    }
}

struct IndexPreferencesTests {
    private func defaults() -> UserDefaults {
        let suite = "IndexPreferencesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func aNewPageIsAListAndNarrow() {
        let defaults = defaults()
        for place in IndexPlace.allCases {
            #expect(IndexPreferences.layout(for: place, in: defaults) == .list)
            #expect(IndexPreferences.width(for: place, in: defaults) == .narrow)
        }
    }

    @Test func eachPageKeepsItsOwnChoices() {
        let defaults = defaults()
        IndexPreferences.set(.table, for: .sources, in: defaults)
        IndexPreferences.set(.wide, for: .sources, in: defaults)
        IndexPreferences.set(.cards, for: .collections, in: defaults)
        #expect(IndexPreferences.layout(for: .sources, in: defaults) == .table)
        #expect(IndexPreferences.width(for: .sources, in: defaults) == .wide)
        #expect(IndexPreferences.layout(for: .collections, in: defaults) == .cards)
        #expect(IndexPreferences.width(for: .collections, in: defaults) == .narrow)
    }

    @Test func anUnreadableStoredValueFallsBackToTheDefault() {
        let defaults = defaults()
        defaults.set("kanban", forKey: IndexPlace.sources.layoutKey)
        defaults.set(3, forKey: IndexPlace.sources.widthKey)
        #expect(IndexPreferences.layout(for: .sources, in: defaults) == .list)
        #expect(IndexPreferences.width(for: .sources, in: defaults) == .narrow)
    }

    @Test func theWidthsAreNarrowStandardAndTheWholeWindow() {
        #expect(IndexWidth.narrow.points == 720)
        #expect(IndexWidth.standard.points == 1000)
        #expect(IndexWidth.wide.points == nil)
    }

    @Test func onlyTheTwoIndexesAreIndexPages() {
        #expect(IndexPlace(.sources) == .sources)
        #expect(IndexPlace(.collections) == .collections)
        #expect(IndexPlace(.allNotes) == nil)
        #expect(IndexPlace(.source("rss")) == nil)
    }
}
