import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// The table's content is worked out once for a window and shared (`Browser.tableContent(in:)`), and its sort reads
/// each row's values once. These check that sharing never shows stale rows, and that the sort puts rows where the
/// comparison it replaced did.
@MainActor
@Suite(.hangLimit) struct TableContentTests {
    private let tasks = SidebarItem.itemType("aic.ticket.task")

    private func browser(showing place: SidebarItem) -> Browser {
        let browser = Browser()
        browser.sidebarItem = place
        browser.viewMode = .table
        return browser
    }

    @Test func oneContentServesEveryReaderUntilSomethingItDependsOnChanges() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: tasks)
        let first = browser.tableContent(in: library)
        #expect(browser.tableContent(in: library) === first)
        // A selection is not something the table is made of.
        browser.selection = [try #require(first.allRows.first?.id)]
        #expect(browser.tableContent(in: library) === first)
    }

    @Test func anEditToOneItemShowsInAGroupedAndFilteredTable() async throws {
        let (library, source) = try await BigLibrary.loaded()
        let browser = browser(showing: tasks)
        browser.tableOptions[tasks] = ItemTableOptions(grouping: .column("field.status"), filter: FilterState(is: ["field.status": ["todo"]]))
        let before = browser.tableContent(in: library)
        let edited = try #require(before.rows.first)
        // Grouped by its words, every word is a group, and only the filter's holds items.
        #expect(before.groups.filter { !$0.rows.isEmpty }.map(\.id) == ["todo"])

        var changed = edited.item
        changed.properties = changed.properties.map { $0.key == "status" ? Property(key: "status", value: .string("done")) : $0 }
        changed.title = "Renamed"
        changed.version = ItemVersion(2)
        source.send(.upserted([changed]))
        try #require(await eventually { library.item(changed.id)?.title == "Renamed" })

        let after = browser.tableContent(in: library)
        #expect(after !== before)
        #expect(!after.rows.contains { $0.id == edited.id }, "the filter keeps only what is still to do")
        #expect(after.rows.count == before.rows.count - 1)
        #expect(after.allRows.first { $0.id == edited.id }?.item.title == "Renamed")
    }

    @Test func aChangedOptionOrLibraryMakesNewContent() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: tasks)
        let before = browser.tableContent(in: library)
        browser.tableOptions[tasks, default: .init()].sort = [ItemTableComparator(column: .title, order: .reverse)]
        let sorted = browser.tableContent(in: library)
        #expect(sorted !== before)
        #expect(sorted.rows.map(\.item.title) == before.allRows.map(\.item.title).sorted { $0.localizedStandardCompare($1) == .orderedDescending })

        let (other, _) = try await BigLibrary.loaded()
        let there = browser.tableContent(in: other)
        #expect(there !== sorted, "another library's items are never answered with this one's")
    }

    @Test func aSearchThatAnswersReplacesWhatWasShownWhilePending() async throws {
        let (library, source) = try await BigLibrary.loaded()
        let browser = browser(showing: .allItems)
        let found = Array(library.items(in: tasks).prefix(3).map(\.id))
        source.hits.withLock { $0["sidebar"] = found }
        browser.searchText = "sidebar"
        let pending = browser.tableContent(in: library)
        try #require(await eventually { Set(browser.tableContent(in: library).allRows.map(\.id)) == Set(found) })
        #expect(browser.tableContent(in: library) !== pending)
    }

}
