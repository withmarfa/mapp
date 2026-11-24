import Foundation
import struct Marfa.ItemSource
import Testing
@testable import MarfaMac

struct IndexRowsTests {
    private let catalogue = FakeItemLibrary.testCatalogue
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func item(_ title: String, type: String = "core.note", source: String? = nil, minutes: Double = 0) -> Item {
        var item = FakeItemLibrary.note(title, modified: base + minutes * 60)
        item.type = TypeID(type)
        item.source = source
        return item
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

    private let readwise = SourceInfo(code: "readwise", name: "Readwise", mark: "simple-icons:readwise", nameOrigin: .set)
    private let github = SourceInfo(code: "gh", name: "GitHub", mark: nil, nameOrigin: .key)

}

struct IndexPreferencesTests {
    private func defaults() -> UserDefaults {
        let defaults = ThrowawayDefaults.make("IndexPreferencesTests")
        return defaults
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
