import Foundation
import Synchronization
import Testing
@testable import MAPP

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
        browser.tableOptions[tasks] = ItemTableOptions(grouping: .column("field.status"), filters: ["field.status": ["todo"]])
        let before = browser.tableContent(in: library)
        let edited = try #require(before.rows.first)
        #expect(before.groups.map(\.id) == ["not_started"])

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
        let browser = browser(showing: .allNotes)
        let found = Array(library.items(in: tasks).prefix(3).map(\.id))
        source.hits.withLock { $0["sidebar"] = found }
        browser.searchText = "sidebar"
        let pending = browser.tableContent(in: library)
        try #require(await eventually { Set(browser.tableContent(in: library).allRows.map(\.id)) == Set(found) })
        #expect(browser.tableContent(in: library) !== pending)
    }

    /// What a selection follows as items change: the table's rows as shown, then the rows its filters hide, so a
    /// selection hidden by a filter is still held. The gallery follows the list's order.
    @Test func theSelectionFollowsTheTableInTheOrderItShowsThenTheHiddenRows() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: tasks)
        browser.tableOptions[tasks] = ItemTableOptions(
            sort: [ItemTableComparator(column: .title, order: .reverse)], filters: ["field.status": ["todo"]])
        let content = browser.tableContent(in: library)
        let ids = browser.collectionItemIDs(in: library, order: NoteOrder())
        #expect(!content.rows.isEmpty && content.rows.count < content.allRows.count)
        #expect(Array(ids.prefix(content.rows.count)) == content.rows.map(\.id))
        #expect(ids.count == content.allRows.count)
        #expect(Set(ids) == Set(content.allRows.map(\.id)))

        browser.viewMode = .gallery
        #expect(browser.collectionItemIDs(in: library, order: NoteOrder())
            == browser.sections(in: library, order: NoteOrder(), now: library.now()).flatMap { $0.items.map(\.id) })
        browser.viewMode = .list
        #expect(browser.collectionItemIDs(in: library, order: NoteOrder()).isEmpty)
    }

    /// A place with statuses is grouped by status, so the selection follows the rows group by group, as they show.
    @Test func theSelectionFollowsAGroupedTableGroupByGroup() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: tasks)
        browser.tableOptions[tasks] = ItemTableOptions(sort: [ItemTableComparator(column: .title, order: .forward)])
        let content = browser.tableContent(in: library)
        try #require(content.grouping != nil && content.groups.count > 1)
        let grouped = content.groups.flatMap(\.rows).map(\.id)
        #expect(grouped != content.rows.map(\.id), "the sort's order across groups differs from the order shown")
        #expect(Array(browser.collectionItemIDs(in: library, order: NoteOrder()).prefix(grouped.count)) == grouped)
    }

    @Test func aPlaceWithNoItemsHasEmptyContent() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: .itemType("aic.nothing"))
        let content = browser.tableContent(in: library)
        #expect(content.allRows.isEmpty && content.rows.isEmpty && content.groups.isEmpty)
    }

    @Test func aCollectionKeepsItsOwnOrder() async throws {
        let album = LibraryFixture.item(ItemID("album"), LibraryFixture.album, "Album", age: 1, properties: [Property(key: "title", value: .string("Album"))])
        let members = ["Zed", "Alpha", "Mid"].enumerated().map { index, title in
            LibraryFixture.item(
                ItemID("m\(index)"), LibraryFixture.note, title, age: 10 + index, properties: [Property(key: "title", value: .string(title))])
        }
        .map { member in
            var member = member
            member.edgesOut = [Edge(id: EdgeID("\(member.id.rawValue)#in"), type: "in-collection", source: member.id, target: .item(album.id), origin: .property("in-collection"))]
            return member
        }
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: [album] + members, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        let browser = browser(showing: .collection(album.id))
        #expect(browser.keepsPlaceOrder)
        #expect(browser.tableContent(in: library).rows.map(\.id) == library.items(in: .collection(album.id)).map(\.id))
    }

    /// The sort the table used before it read each row's values once: the comparators in turn, then the title.
    private func comparisonSort(_ rows: [ItemTableRow], by sort: [ItemTableComparator]) -> [ItemTableRow] {
        rows.sorted { a, b in
            for comparator in sort {
                switch comparator.compare(a, b) {
                case .orderedAscending: return true
                case .orderedDescending: return false
                case .orderedSame: continue
                }
            }
            return a.item.title.localizedStandardCompare(b.item.title) == .orderedAscending
        }
    }

    @Test func sortingByEachColumnGivesTheOrderComparingRowsGave() async throws {
        let (library, _) = try await BigLibrary.loaded()
        let browser = browser(showing: .allNotes)
        let rows = browser.tableContent(in: library).allRows
        let columns = browser.tableContent(in: library).columns
        // Types that lack a field leave its cells empty, which sort last whichever way the column runs.
        #expect(rows.contains { ItemTableValue.string($0, key: "priority") == nil })
        for column in columns {
            for order in [SortOrder.forward, .reverse] {
                let sort = [ItemTableComparator(column: column, order: order)]
                #expect(ItemTableLayout.sorted(rows, by: sort).map(\.id) == comparisonSort(rows, by: sort).map(\.id), "\(column.id) \(order)")
            }
        }
        let two = columns.filter { ["field.status", "field.priority"].contains($0.id) }.map { ItemTableComparator(column: $0, order: .reverse) }
        #expect(ItemTableLayout.sorted(rows, by: two).map(\.id) == comparisonSort(rows, by: two).map(\.id))
    }
}
