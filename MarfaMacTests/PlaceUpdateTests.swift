import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// A change of items updates what a window last worked out for a place (`Browser.tableContent(in:)`,
/// `Browser.sections(in:order:now:)`, `MarfaLibrary`'s listings) rather than working it out again. These check that an
/// update shows exactly what a window that never saw the earlier items shows, for every way a change can move an item, in
/// a place small enough to be worked out in place and one large enough to be worked out off the main actor; and that a
/// change no row of a place holds leaves what was worked out as it was.
@MainActor
@Suite(.hangLimit) struct PlaceUpdateTests {
    private static let tasks = PlaceView.type(BigLibrary.task)
    private static let now = Date(timeIntervalSince1970: 1_790_000_000)

    private func browser(_ library: any ItemLibrary, showing place: PlaceView = .library, options: ItemTableOptions? = nil) -> Browser {
        let browser = Browser()
        browser.adopt(library)
        browser.showing = place
        browser.viewMode = .table
        browser.tableOptions[place] = options
        return browser
    }

    /// A window that never saw the earlier items, with the same choices.
    private func fresh(like browser: Browser, in library: any ItemLibrary) -> Browser {
        let fresh = self.browser(library, showing: browser.shown, options: browser.tableOptions[browser.shown])
        fresh.viewMode = browser.viewMode
        fresh.searchText = browser.searchText
        return fresh
    }

    /// The table once no arrangement is under way, which for a large place lands off the main actor.
    private func settled(_ browser: Browser, in library: any ItemLibrary) async throws -> ItemTableContent {
        try #require(await eventually(within: .seconds(30)) {
            _ = browser.tableContent(in: library)
            return browser.arranging == nil
        })
        return browser.tableContent(in: library)
    }

    private func settledSections(_ browser: Browser, in library: any ItemLibrary, order: ItemOrder) async throws -> [ItemSection] {
        try #require(await eventually(within: .seconds(30)) {
            _ = browser.sections(in: library, order: order, now: Self.now)
            return browser.sectionsWork.runningKey == nil
        })
        return browser.sections(in: library, order: order, now: Self.now)
    }

    /// Expects `browser`'s table to be the table a fresh window makes for the same choices.
    private func expectSameTable(_ browser: Browser, in library: any ItemLibrary, _ comment: Comment) async throws {
        let content = try await settled(browser, in: library)
        let fresh = fresh(like: browser, in: library)
        if browser.isSearching {
            let found = browser.searchResults(in: library)?.items.map(\.id)
            try #require(await eventually { fresh.searchResults(in: library)?.items.map(\.id) == found })
        }
        let made = fresh.tableContent(in: library)
        #expect(content.allRows == made.allRows, comment)
        #expect(content.kept == made.kept, comment)
        #expect(content.rows == made.rows, comment)
        #expect(content.allGroups == made.allGroups, comment)
        #expect(content.columns == made.columns, comment)
    }

    private static func with(_ item: Item, step: Int, _ change: (inout Item) -> Void) -> Item {
        var item = item
        change(&item)
        item.version = ItemVersion(Int64(10 + step))
        item.modified = Date(timeIntervalSince1970: 2_000_000 + Double(step))
        return item
    }

    private static func status(_ word: String) -> (inout Item) -> Void {
        { item in item.properties = item.properties.filter { $0.key != "status" } + [Property(key: "status", value: .string(word))] }
    }

    private static func title(_ title: String) -> (inout Item) -> Void {
        { item in
            item.title = title
            item.name = title
        }
    }

    /// Sends `items` and waits until the library holds the last of them.
    private func send(_ items: [Item], to source: FakeItemSource, of library: MarfaLibrary) async throws {
        let revision = library.contentRevision
        source.send(.upserted(items))
        try #require(await eventually { library.contentRevision != revision })
    }

    // MARK: Reuse

    @Test func aChangeNoRowHoldsKeepsTheTableAndTheList() async throws {
        let (library, source) = try await BigLibrary.loaded()
        let table = browser(library, showing: Self.tasks, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)]))
        let before = table.tableContent(in: library)
        let list = browser(library, showing: Self.tasks)
        list.viewMode = .list
        let sections = list.sections(in: library, order: ItemOrder(), now: Self.now)
        let (tables, lists) = (table.placeWorkCounts, list.placeWorkCounts)

        let note = try #require(library.items(in: .type(BigLibrary.note)).first)
        try await send([Self.with(note, step: 1, Self.title("Elsewhere"))], to: source, of: library)
        #expect(table.tableContent(in: library) === before, "a note is no row of the tasks' table")
        #expect(table.placeWorkCounts == tables)
        #expect(list.sections(in: library, order: ItemOrder(), now: Self.now) == sections)
        #expect(list.placeWorkCounts == lists, "nor of their list")
    }

    @Test func aChangeThatCannotMoveARowUpdatesOnlyThatRow() async throws {
        let (library, source) = try await BigLibrary.loaded()
        let table = browser(library, showing: Self.tasks, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)]))
        let before = table.tableContent(in: library)
        let counts = table.placeWorkCounts
        let task = try #require(before.rows.dropFirst(5).first?.item)
        // Who a task is for is neither sorted nor grouped by here.
        let edited = Self.with(task, step: 1) { $0.properties.append(Property(key: "assignee", value: .string("someone"))) }
        try await send([edited], to: source, of: library)

        let after = table.tableContent(in: library)
        #expect(after !== before)
        #expect(after.rows.map(\.id) == before.rows.map(\.id), "no row moved")
        #expect(after.rows.first { $0.id == task.id }?.item == edited)
        #expect(table.placeWorkCounts.tablesMade == counts.tablesMade, "the table was not made again")
        #expect(table.placeWorkCounts.tablesUpdated == counts.tablesUpdated + 1)
        try await expectSameTable(table, in: library, "an update shows what a fresh table does")
    }

    // MARK: Every move

    /// The ways a change moves an item in a place: in the sort, between groups, out of a filter, out of the place by its
    /// state or tier, into it as a new item, and out of the library.
    @Test(arguments: [1, 4])
    func eachMoveShowsWhatAFreshTableShows(scale: Int) async throws {
        let (library, source) = try await BigLibrary.loaded(scale: scale)
        #expect((library.items(in: .library).count > Browser.arrangesAlongsideAbove) == (scale > 1))
        let choices: [(String, ItemTableOptions)] = [
            ("sorted by name", ItemTableOptions(sort: [ItemTableComparator(column: .title)])),
            ("grouped by status", ItemTableOptions(grouping: .column("field.status"))),
            ("filtered to work not done", ItemTableOptions(filter: FilterState(is: ["field.status": ["backlog", "todo", "in_progress"]]))),
        ]
        let browsers = choices.map { browser(library, options: $0.1) }
        for browser in browsers { _ = browser.tableContent(in: library) }
        let tasks = library.items(in: Self.tasks.place)
        let moves: [(String, [Item])] = [
            ("renamed to the front of a sort by name", [Self.with(tasks[3], step: 1, Self.title("Aardvark first"))]),
            ("into another status", [Self.with(tasks[4], step: 2, Self.status("done"))]),
            ("out of the filter", [Self.with(tasks[5], step: 3, Self.status("canceled"))]),
            ("archived", [Self.with(tasks[6], step: 4) { $0.state = .archived }]),
            ("moved to the Feed", [Self.with(tasks[7], step: 5) { $0.tier = .feed }]),
            ("new", [LibraryFixture.item(ItemID("new-task"), BigLibrary.task, "Brand new", age: 1, properties: [
                Property(key: "title", value: .string("Brand new")), Property(key: "status", value: .string("todo")),
            ])]),
        ]
        for (move, items) in moves {
            try await send(items, to: source, of: library)
            for (browser, choice) in zip(browsers, choices) {
                try await expectSameTable(browser, in: library, "\(move), \(choice.0)")
            }
        }
        let revision = library.contentRevision
        source.send(.removed([tasks[8].id]))
        try #require(await eventually { library.contentRevision != revision })
        for (browser, choice) in zip(browsers, choices) { try await expectSameTable(browser, in: library, "removed, \(choice.0)") }
        if scale > 1 { #expect(browsers.allSatisfy { $0.placeWorkCounts.tablesUpdated > 0 }, "a large place updated its table") }
    }

    @Test(arguments: [1, 4])
    func eachMoveShowsWhatAFreshListShows(scale: Int) async throws {
        let (library, source) = try await BigLibrary.loaded(scale: scale)
        let orders = [ItemOrder(sort: .title), ItemOrder(sort: .dateEdited), ItemOrder(sort: .dateCreated, groupsByDate: false)]
        // A window lists in one order, as Settings has it.
        let lists = orders.map { _ in browser(library) }
        for (list, order) in zip(lists, orders) {
            list.viewMode = .list
            _ = try await settledSections(list, in: library, order: order)
        }
        let tasks = library.items(in: Self.tasks.place)
        let moves: [[Item]] = [
            [Self.with(tasks[3], step: 1, Self.title("Aardvark first"))],
            [Self.with(tasks[4], step: 2) { $0.tags.insert(ItemTag.favorite) }],
            [Self.with(tasks[5], step: 3) { $0.state = .archived }],
            (0..<30).map { Self.with(tasks[10 + $0], step: 4 + $0, Self.title("Batch \($0)")) },
            [LibraryFixture.item(ItemID("new-task"), BigLibrary.task, "Brand new", age: 1, properties: [Property(key: "title", value: .string("Brand new"))])],
        ]
        for (step, items) in moves.enumerated() {
            try await send(items, to: source, of: library)
            for (list, order) in zip(lists, orders) {
                let sections = try await settledSections(list, in: library, order: order)
                let made = fresh(like: list, in: library).sections(in: library, order: order, now: Self.now)
                #expect(sections == made, "step \(step), \(order.sort)")
            }
        }
        #expect(lists.allSatisfy { $0.placeWorkCounts.listsUpdated > 0 && $0.placeWorkCounts.listsSorted == 1 }, "each list was sorted once, then updated")
    }

    // MARK: Runs of changes

    @Test func aChangeDuringAnArrangementIsNeverShownWithoutTheNext() async throws {
        let (library, source) = try await BigLibrary.loaded(scale: 4)
        let table = browser(library, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)]))
        let first = table.tableContent(in: library)
        let landed = table.tableArrangements
        let rows = first.rows.map(\.item)
        try await send([Self.with(rows[0], step: 1, Self.title("Zz first change"))], to: source, of: library)
        #expect(table.tableContent(in: library) === first, "the last table shows while the next is arranged")
        // The second arrives while the first is still let settle, off the main actor.
        try await send([Self.with(rows[1], step: 2, Self.title("Aa second change"))], to: source, of: library)
        #expect(table.tableContent(in: library) === first)
        try await expectSameTable(table, in: library, "both changes show")
        #expect(table.tableArrangements == landed + 1, "the arrangement for the first change alone never landed")
    }

    @Test func aSyncOfTwoThousandItemsAndAWholeReadShowWhatAFreshTableShows() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let table = browser(library, options: ItemTableOptions(grouping: .column("field.status"), sort: [ItemTableComparator(column: .title)]))
        // The first fill, which a window open on the place sees arrive whole.
        #expect(table.tableContent(in: library).allRows.isEmpty)
        var items = BigLibrary.items(scale: 4)
        source.send(.loaded(SourceSnapshot(items: items, catalogue: BigLibrary.catalogue)))
        try #require(await eventually { library.isLoaded })
        try await expectSameTable(table, in: library, "the first fill")

        let words = ["backlog", "todo", "in_progress", "done"]
        let synced = items.prefix(2_000).enumerated().map { index, item in
            Self.with(item, step: index) { item in
                Self.title("Synced \(2_000 - index)")(&item)
                if item.type == BigLibrary.task { Self.status(words[index % words.count])(&item) }
            }
        }
        try await send(synced, to: source, of: library)
        try await expectSameTable(table, in: library, "two thousand items at once")

        // The copy read whole again, with an item archived and one gone.
        items = library.items(in: .library)
        items[0].state = .archived
        items.removeLast()
        source.send(.loaded(SourceSnapshot(items: items, catalogue: BigLibrary.catalogue)))
        try #require(await eventually { library.items(in: .library).count == items.count - 1 })
        try await expectSameTable(table, in: library, "the copy read whole again")
    }

    @Test func aSearchKeepsItsOwnTableThroughAChange() async throws {
        let (library, source) = try await BigLibrary.loaded(scale: 4)
        let table = browser(library, options: ItemTableOptions(sort: [ItemTableComparator(column: .title)]))
        _ = try await settled(table, in: library)
        let found = Array(library.items(in: .library).prefix(2_500).map(\.id))
        source.hits.withLock { $0["plan"] = found }
        table.searchText = "plan"
        try #require(await eventually { table.searchResults(in: library)?.items.count == found.count })
        _ = try await settled(table, in: library)

        let edited = Self.with(try #require(library.item(found[10])), step: 1, Self.title("Aa searched"))
        try await send([edited], to: source, of: library)
        try await expectSameTable(table, in: library, "the search's table")
        #expect(table.heldTables[.library] != nil, "the Library's table is held apart from the search's")

        table.searchText = ""
        try await expectSameTable(table, in: library, "the Library's table after the search")
        #expect(try await settled(table, in: library).rows.first?.item.title == "Aa searched")
    }

    @Test func theListsDateGroupsAreWhatEachDateAloneGives() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        // Over three years, a clock change and the turn of a year among them, newest first as a list by date is.
        let dates = (-40...(3 * 365 * 24 / 7)).map { Self.now.addingTimeInterval(Double(-$0) * 7 * 3600) }
        var grouper = ItemGroup.Grouper(now: Self.now, calendar: calendar)
        #expect(dates.map { grouper.group(for: $0) } == dates.map { ItemGroup.group(for: $0, now: Self.now, calendar: calendar) })
    }

    // MARK: The library's listings

    @Test func aListingUpdatedByItsChangesListsWhatAFreshLibraryLists() async throws {
        let (library, source) = try await BigLibrary.loaded()
        let places: [(Place, ListScope, ArchivedItems)] = [
            (.library, .library, .hidden), (.feed, .feed, .hidden), (.archive, .all, .only), (Self.tasks.place, .all, .hidden),
            (Self.tasks.place, .library, .shown), (.type(BigLibrary.note), .all, .hidden),
        ]
        func listings(_ library: MarfaLibrary) -> [[ItemID]] {
            places.map { library.items(in: $0.0, scope: $0.1, archived: $0.2, includingKinds: true).map(\.id) }
                + [library.favoriteItems(in: .all, archived: .hidden).map(\.id)]
        }
        _ = listings(library)
        let tasks = library.items(in: Self.tasks.place)
        let note = try #require(library.items(in: .type(BigLibrary.note)).first)
        var file = LibraryFixture.item(
            ItemID("attached"), BigLibrary.note, "Photo.png", age: 1, properties: [Property(key: "title", value: .string("Photo.png"))],
            content: .file(.png, byteCount: 10))
        file.edgesOut = [Edge(
            id: EdgeID("attached#attached-to"), type: MarfaMapping.attachmentEdge, from: file.id, to: .item(note.id),
            origin: .property("attached-to"))]
        let steps: [[Item]] = [
            [Self.with(tasks[0], step: 1, Self.title("Renamed"))],
            [Self.with(tasks[1], step: 2) { $0.state = .archived }],
            [Self.with(tasks[2], step: 3) { $0.tier = .feed }],
            [Self.with(tasks[3], step: 4) { $0.tags.insert(ItemTag.favorite) }],
            [Self.with(tasks[4], step: 5) { $0.type = BigLibrary.note }],
            [file],
            [Self.with(tasks[1], step: 6) { $0.state = .active }],
        ]
        for (index, items) in steps.enumerated() {
            try await send(items, to: source, of: library)
            let (made, _) = try await Self.copy(of: library)
            #expect(listings(library) == listings(made), "step \(index)")
        }
        let revision = library.contentRevision
        source.send(.removed([note.id]))
        try #require(await eventually { library.contentRevision != revision })
        let (made, _) = try await Self.copy(of: library)
        #expect(listings(library) == listings(made), "an item gone, and the file it held listed again")
    }

    /// A library loaded from what `library` holds now.
    private static func copy(of library: MarfaLibrary) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let made = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: library.records.values.map(\.item), catalogue: BigLibrary.catalogue)))
        try #require(await eventually { made.isLoaded })
        return (made, source)
    }
}
