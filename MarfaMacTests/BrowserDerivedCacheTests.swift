import Foundation
import Testing
@testable import MarfaMac

/// What the window works out from a place's items is kept until something it depends on changes, and a hit lists no
/// items (`Browser.sections`, `tableContent`, `availableViewModes`), so a click costs nothing it has done before.
@MainActor
struct BrowserDerivedCacheTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func library() -> FakeItemLibrary {
        FakeItemLibrary(items: (1...5).map { FakeItemLibrary.note("Note \($0)", modified: date) }, now: date)
    }

    @Test func theSectionsOfAnUnchangedPlaceListNothingTheSecondTime() {
        let library = library()
        let browser = Browser()
        let first = browser.sections(in: library, order: ItemOrder(), now: date)
        let reads = library.placeReads
        let second = browser.sections(in: library, order: ItemOrder(), now: date)
        #expect(library.placeReads == reads)
        #expect(second.map { $0.items.map(\.id) } == first.map { $0.items.map(\.id) })
    }

    @Test func anEditToAnItemMakesTheSectionsAgain() {
        let library = library()
        let browser = Browser()
        _ = browser.sections(in: library, order: ItemOrder(), now: date)
        library.items[0].title = "Renamed"
        let titles = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(titles.contains("Renamed"))
    }

    @Test func theTableOfAnUnchangedPlaceIsTheSameAndListsNothing() {
        let library = library()
        let browser = Browser()
        let first = browser.tableContent(in: library)
        let reads = library.placeReads
        #expect(browser.tableContent(in: library) === first)
        #expect(library.placeReads == reads)
    }

    @Test func theFilteredSectionsAreKeptAndKeyOnTheFilters() {
        let library = library()
        let browser = Browser()
        let before = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.id) }
        #expect(before.count == 5)
        browser.tableOptions[.library] = ItemTableOptions(filter: FilterState(clauses: [FilterClause(field: "edited", op: .before, values: ["2000-01-01"])]))
        let filtered = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.id) }
        #expect(filtered.count < before.count)
        let reads = library.placeReads
        _ = browser.sections(in: library, order: ItemOrder(), now: date)
        #expect(library.placeReads == reads)
        browser.tableOptions[.library] = nil
        #expect(browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.id) } == before)
    }

    @Test func anUnfilteredPlaceBuildsNoTableForTheList() {
        let library = library()
        let browser = Browser()
        _ = browser.sections(in: library, order: ItemOrder(), now: date)
        #expect(!browser.holdsTableContent)
        browser.tableOptions[.library] = ItemTableOptions(sort: [ItemTableComparator(column: .title)])
        _ = browser.sections(in: library, order: ItemOrder(), now: date)
        #expect(browser.holdsTableContent)
    }

    /// Three tickets with a status, which the table groups by on its own.
    private func tasks() -> FakeItemLibrary {
        let ticket = TypeID("test.ticket")
        let status = ItemTypeInfo.Field(
            key: "status", label: "Status",
            kind: .status([StatusWord(value: "todo", group: .notStarted), StatusWord(value: "done", group: .completed)]), declaredBy: ticket)
        let library = FakeItemLibrary(items: ["todo", "done", "todo"].enumerated().map { index, status in
            Item(
                id: ItemID("t\(index)"), type: ticket, title: "Task \(index)", name: "Task \(index)", titleRule: .firstLine,
                properties: [Property(key: "status", value: .string(status))], version: ItemVersion(1), created: date, modified: date)
        }, now: date)
        library.catalogue = Catalogue(
            itemTypes: Array(FakeItemLibrary.testCatalogue.itemTypes.values)
                + [ItemTypeInfo(id: ticket, label: "Ticket", fields: [status], titleField: "title", bodyField: "body", parent: nil)],
            edgeTypes: Array(FakeItemLibrary.testCatalogue.edgeTypes.values))
        return library
    }

    @Test func aNewViewFromASortedListKeepsNoGroupingTheListDoesNotShow() {
        let library = tasks()
        let browser = Browser()
        browser.tableOptions[.library] = ItemTableOptions(sort: [ItemTableComparator(column: .title)])
        browser.viewMode = .table
        #expect(SavedViews.window(browser, in: library, order: ItemOrder()).grouping != nil)
        for mode in [ItemViewMode.list, .gallery] {
            browser.viewMode = mode
            #expect(SavedViews.window(browser, in: library, order: ItemOrder()).grouping == nil, "\(mode) kept the table's grouping")
        }
        browser.tableOptions[.library]?.grouping = .column("field.status")
        browser.viewMode = .list
        #expect(SavedViews.window(browser, in: library, order: ItemOrder()).grouping != nil)
    }

    @Test func aNegationOnAColumnWithNoFilterMakesNeitherTheTableNorTheSectionsAgain() {
        let library = library()
        let browser = Browser()
        browser.tableOptions[.library] = ItemTableOptions(sort: [ItemTableComparator(column: .title)])
        let table = browser.tableContent(in: library)
        let sections = browser.sections(in: library, order: ItemOrder(), now: date)
        // A filter that says too little to filter by changes nothing the rows depend on.
        browser.tableOptions[.library]?.filter = FilterState(clauses: [FilterClause(field: "field.status", op: .is)])
        #expect(browser.tableContent(in: library) === table)
        let reads = library.placeReads
        _ = browser.sections(in: library, order: ItemOrder(), now: date)
        #expect(library.placeReads == reads)
        #expect(browser.sections(in: library, order: ItemOrder(), now: date).map { $0.items.map(\.id) } == sections.map { $0.items.map(\.id) })
    }

    @Test func aSearchKeepsKeyingOnWhatItFinds() {
        let library = library()
        let browser = Browser()
        browser.searchText = "Note 1"
        let one = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.title) }
        browser.searchText = "Note 2"
        let two = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(one == ["Note 1"])
        #expect(two == ["Note 2"])
    }

    @Test func aSavedViewKeepsKeyingOnTheItemsItListsWhichArriveWithoutAChangeToTheLibrary() {
        let library = library()
        let view = LibraryView(id: .mint(), title: "Some")
        library.views = [view]
        let browser = Browser()
        browser.show(.view(view.id), in: library, order: ItemOrder())
        #expect(browser.sections(in: library, order: ItemOrder(), now: date).isEmpty)
        library.viewMembers[view.id] = [library.items[0].id]
        let titles = browser.sections(in: library, order: ItemOrder(), now: date).flatMap { $0.items.map(\.title) }
        #expect(titles == ["Note 1"])
    }

    @Test func theLayoutsOfAPlaceAreKeptUntilTheLibraryChangesWhatItHolds() {
        let library = library()
        let browser = Browser()
        let first = browser.availableViewModes(in: library)
        let reads = library.placeReads
        #expect(browser.availableViewModes(in: library) == first)
        #expect(library.placeReads == reads)
        library.items.append(FakeItemLibrary.note("Another", modified: date))
        _ = browser.availableViewModes(in: library)
        #expect(library.placeReads > reads)
    }
}

/// Where the window goes when the place it shows is gone, worked out without moving it, so a view can watch the
/// answer (`Browser.placeFallback`) instead of a list of the library's items.
@MainActor
@Suite(.hangLimit)
struct PlaceFallbackTests {
    private let date = Date(timeIntervalSinceReferenceDate: 800_000_000)
}

private nonisolated final class Told: @unchecked Sendable {
    private(set) var isSet = false
    func set() { isSet = true }
}
