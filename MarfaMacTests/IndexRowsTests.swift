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

    @Test func aReadOnlyCollectionIsMarkedSo() {
        var locked = item("Locked", type: "test.collection")
        locked.readOnly = true
        let open = item("Open", type: "test.collection")
        let rows = IndexRows.collections([locked, open], count: { _ in 0 }, catalogue: catalogue)
        #expect(rows.map(\.readOnly) == [true, false])
    }

    @Test func sourcesAndTheirCountsComeFromOneGrouping() {
        let items = [item("a", source: "b"), item("b", source: "A"), item("c", source: "b"), item("d")]
        let library = FakeItemLibrary(items: items, now: base)
        let groups = IndexRows.groupedBySource(library.items(in: .library))
        #expect(library.sourceCounts.map(\.code) == groups.map(\.code))
        #expect(library.sourceCounts.map(\.count) == groups.map(\.items.count))
    }

    /// The chosen row stays where the person saw it while a large table is sorted again behind it.
    @Test func theChosenRowKeepsItsPlaceThroughAReSort() {
        let rows = ["a", "b", "c", "d"].map { ItemTableRow(item: item($0), typeLabel: "", typeIcon: nil, parent: nil) }
        let resorted = [rows[2], rows[0], rows[3], rows[1]]
        let held = Browser.holding(rows[1].id, in: resorted, as: rows)
        #expect(held.map(\.item.displayTitle) == ["c", "b", "a", "d"])
        #expect(Browser.holding(nil, in: resorted, as: rows) == resorted)
        #expect(Browser.holding(rows[3].id, in: resorted, as: rows).last?.id == rows[3].id)
    }

    // MARK: Names, marks and counts from the server

    private let readwise = SourceInfo(code: "readwise", name: "Readwise", mark: "simple-icons:readwise", nameOrigin: .set)
    private let github = SourceInfo(code: "gh", name: "GitHub", mark: nil, nameOrigin: .key)

}
