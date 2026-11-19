import Foundation
import Testing
@testable import MAPP

/// The Items index: what each tab lists and counts, how the table's header orders it, and what the window does with the
/// chosen item as the library changes under it or an older window comes back.
@MainActor
@Suite(.hangLimit) struct ItemIndexTests {
    private let base = Date(timeIntervalSinceReferenceDate: 800_000_000)

    private func note(_ title: String, tier: Tier = .library, source: String? = nil, minutes: Double = 0, type: String = "core.note") -> Item {
        var item = FakeItemLibrary.note(title, modified: base + minutes * 60, tier: tier)
        item.type = TypeID(type)
        item.source = source
        return item
    }

    private func tabs(_ items: [Item], sort: IndexSort = IndexPlace.items.defaultSort) -> ItemIndexTabs {
        ItemIndexRows.tabs(of: items, catalogue: FakeItemLibrary.testCatalogue, directory: SourceDirectory(), sort: sort)
    }

    // MARK: Tabs

    @Test func yoursIsTheLibraryTierAndFromAppsTheFeedTier() {
        let items = [note("a"), note("b", tier: .feed), note("c"), note("d", tier: .feed), note("e", tier: .feed)]
        let result = tabs(items)
        #expect(result.all.count == 5)
        #expect(Set(result.yours.map(\.title)) == ["a", "c"])
        #expect(Set(result.fromApps.map(\.title)) == ["b", "d", "e"])
        #expect(result.count(for: .all) == 5 && result.count(for: .yours) == 2 && result.count(for: .fromApps) == 3)
        #expect(result.count(for: .yours) + result.count(for: .fromApps) == result.count(for: .all))
    }

    @Test func aTabThePageLacksListsNothing() {
        let result = tabs([note("a")])
        #expect(result.rows(for: .apps).isEmpty && result.rows(for: .keys).isEmpty)
    }

    @Test func aRowCarriesTheTypesLabelIconAndTheSourcesName() throws {
        let directory = SourceDirectory()
        let rows = ItemIndexRows.rows(
            of: [note("a", source: "rss", type: "core.task"), note("b")], catalogue: FakeItemLibrary.testCatalogue, directory: directory)
        let first = try #require(rows.first)
        #expect(first.typeLabel == "Task")
        #expect(first.icon == FakeItemLibrary.testCatalogue.icon(for: TypeID("core.task")))
        #expect(first.sourceName == directory.name("rss"))
        #expect(rows[1].sourceName.isEmpty, "an item no source made has none")
    }

    @Test func aTabListsEveryItemOfItsTierWhateverThePageSize() {
        let items = (0..<5_000).map { note("n\($0)", tier: $0 % 3 == 0 ? .feed : .library, minutes: Double($0)) }
        let result = tabs(items)
        #expect(result.count(for: .all) == 5_000)
        #expect(result.count(for: .fromApps) == items.filter { $0.tier == .feed }.count)
    }

    // MARK: Sorting

    @Test func theDefaultOrderIsTheLatestChangeFirst() {
        let result = tabs([note("old", minutes: 1), note("new", minutes: 9), note("mid", minutes: 5)])
        #expect(result.all.map(\.title) == ["new", "mid", "old"])
    }

    @Test func eachHeaderOrdersItsColumnBothWays() {
        let items = [note("b", minutes: 2, type: "core.task"), note("a", minutes: 3), note("c", minutes: 1, type: "test.project")]
        #expect(tabs(items, sort: IndexSort(column: .name, ascending: true)).all.map(\.title) == ["a", "b", "c"])
        #expect(tabs(items, sort: IndexSort(column: .name, ascending: false)).all.map(\.title) == ["c", "b", "a"])
        #expect(tabs(items, sort: IndexSort(column: .types, ascending: true)).all.map(\.typeLabel) == ["Note", "Project", "Task"])
        #expect(tabs(items, sort: IndexSort(column: .latest, ascending: true)).all.map(\.title) == ["c", "b", "a"])
    }

    @Test func equalRowsKeepOneOrderWhateverTheyArriveIn() {
        let items = (0..<20).map { _ in note("same", minutes: 1) }
        #expect(tabs(items).all.map(\.id) == tabs(items.reversed()).all.map(\.id))
    }

    @Test func aHeadersComparatorsBecomeTheKeptSortAndBack() throws {
        for column in IndexPlace.items.columns {
            for ascending in [true, false] {
                let sort = IndexSort(column: column, ascending: ascending)
                let comparators: [KeyPathComparator<ItemIndexRow>] = sort.itemComparators
                #expect(IndexSort(comparators: comparators) == sort)
            }
        }
        #expect(IndexSort(comparators: [KeyPathComparator<ItemIndexRow>]()) == nil)
    }

    @Test func theItemsPageKeepsItsOwnTabAndSort() throws {
        let defaults = try #require(UserDefaults(suiteName: "ItemIndexTests.\(UUID().uuidString)"))
        IndexPreferences.set(.fromApps, for: .items, in: defaults)
        IndexPreferences.set(IndexSort(column: .source, ascending: true), for: .items, in: defaults)
        #expect(IndexPreferences.tab(for: .items, in: defaults) == .fromApps)
        #expect(IndexPreferences.sort(for: .items, in: defaults) == IndexSort(column: .source, ascending: true))
        #expect(IndexPreferences.tab(for: .collections, in: defaults) == .all)
        #expect(IndexPlace.items.columns == [.name, .types, .source, .latest])
        defaults.set("count.desc", forKey: IndexPlace.items.sortKey)
        #expect(IndexPreferences.sort(for: .items, in: defaults) == IndexPlace.items.defaultSort, "a column the page lacks falls back")
    }

    // MARK: The window

    private func browserOnItems(_ library: FakeItemLibrary) -> Browser {
        let browser = Browser()
        browser.defaults = UserDefaults(suiteName: "ItemIndexTests.\(UUID().uuidString)") ?? .standard
        browser.sidebarItem = .allItems
        return browser
    }

    @Test func itemsIsAnIndexWithNoLayoutOfItsOwn() {
        let library = FakeItemLibrary(items: [note("a")], now: base)
        let browser = browserOnItems(library)
        browser.set(layout: .gallery)
        #expect(browser.showsItemsIndex && browser.showsSidebarIndex)
        #expect(!browser.usesCollection, "the layout last chosen elsewhere is not shown on Items")
        browser.show(.inbox, in: library, order: ItemOrder())
        #expect(!browser.showsItemsIndex)
        #expect(browser.usesCollection)
    }

    @Test func anItemOpenedAsAFullPageTakesTheWindowUntilBack() throws {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        #expect(browser.open([item.id], as: .fullPage))
        #expect(!browser.showsItemsIndex && browser.showsPage)
        browser.returnToCollection()
        #expect(browser.showsItemsIndex && !browser.showsPage)
        #expect(browser.selection == [item.id], "the chosen item is still chosen")
    }

    @Test func openingInTheModalShowsThePageOverTheIndex() {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        #expect(browser.open([item.id], as: .modal))
        #expect(browser.showsItemsIndex && browser.showsPage)
    }

    @Test func choosingItemsChoosesNothingUntilThePersonDoes() {
        let library = FakeItemLibrary(items: [note("a"), note("b")], now: base)
        let browser = Browser()
        browser.show(.inbox, in: library, order: ItemOrder())
        browser.selectAutomatically([library.items[0].id])
        browser.show(.allItems, in: library, order: ItemOrder())
        #expect(browser.selection.isEmpty)
    }

    @Test func aChosenItemThatIsDeletedIsNoLongerChosen() {
        let keep = note("keep"), gone = note("gone")
        let library = FakeItemLibrary(items: [keep, gone], now: base)
        let browser = browserOnItems(library)
        browser.selection = [gone.id]
        browser.keepItemChoice(in: library)
        #expect(browser.selection == [gone.id], "an item still there stays chosen")
        library.items.removeAll { $0.id == gone.id }
        browser.keepItemChoice(in: library)
        #expect(browser.selection.isEmpty)
    }

    @Test func aChosenItemMovedToRecentlyDeletedIsNoLongerChosen() throws {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        library.items[0].state = .trashed
        browser.keepItemChoice(in: library)
        #expect(browser.selection.isEmpty)
    }

    @Test func aChosenItemThatMovesTierStaysChosen() {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        library.items[0].tier = .feed
        browser.keepItemChoice(in: library)
        #expect(browser.selection == [item.id])
        #expect(tabs(library.items).count(for: .yours) == 0 && tabs(library.items).count(for: .fromApps) == 1)
    }

    @Test func nothingIsGoneWhileTheLibraryHasNotLoaded() {
        let item = note("a")
        let library = FakeItemLibrary(items: [], now: base)
        library.isLoaded = false
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        browser.keepItemChoice(in: library)
        #expect(browser.selection == [item.id])
    }

    @Test func theModalOverItemsClosesWhenItsItemGoes() {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let browser = browserOnItems(library)
        browser.selection = [item.id]
        browser.open([item.id], as: .modal)
        library.items.removeAll()
        browser.keepItemChoice(in: library)
        #expect(!browser.isModalPresented)
    }

    @Test func theModalsArrowsFollowTheRowsOfTheTab() {
        let items = [note("a", minutes: 3), note("b", tier: .feed, minutes: 2), note("c", minutes: 1)]
        let library = FakeItemLibrary(items: items, now: base)
        let browser = browserOnItems(library)
        browser.itemIndex.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(browser.itemIndexRows(in: library).map(\.title) == ["a", "b", "c"])
        #expect(browser.orderBehind(in: library, order: ItemOrder()) == items.map(\.id))
    }

    // MARK: Coming back

    @Test(arguments: [ItemViewMode.list, .gallery, .table, .board, .timeline, .calendar], [true, false])
    func aWindowRestoredOnItemsShowsTheIndexWhateverLayoutItKept(layout: ItemViewMode, opensItem: Bool) {
        let item = note("a")
        let library = FakeItemLibrary(items: [item], now: base)
        let snapshot = Browser.Snapshot(place: .allItems, selection: [item.id], viewMode: layout, opensItem: opensItem)
        let browser = Browser()
        browser.restore(snapshot, in: library, order: ItemOrder())
        #expect(browser.showsItemsIndex)
        #expect(browser.selection == [item.id], "the chosen item comes back")
        #expect(!browser.isCollectionItemPresented)
        #expect(!browser.usesCollection)
    }

    @Test func aWindowRestoredOnItemsWithNothingChosenChoosesNothing() {
        let library = FakeItemLibrary(items: [note("a")], now: base)
        let browser = Browser()
        browser.restore(Browser.Snapshot(place: .allItems, selection: []), in: library, order: ItemOrder())
        #expect(browser.showsItemsIndex && browser.selection.isEmpty)
    }

    @Test func theRowsArrangedByTheModelMatchTheLibraryAndFollowIt() {
        let library = FakeItemLibrary(items: [note("a", minutes: 1), note("b", tier: .feed, minutes: 2)], now: base)
        let model = ItemIndexModel()
        #expect(model.tabs == nil)
        model.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(model.tabs?.all.map(\.title) == ["b", "a"])
        model.follow(library, sort: IndexSort(column: .name, ascending: true))
        #expect(model.tabs?.all.map(\.title) == ["a", "b"])
        model.stop()
        model.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(model.tabs?.count(for: .fromApps) == 1)
    }

    // MARK: Chosen rows, full pages and search

    @Test func severalChosenRowsKeepThoseThatRemain() {
        let (a, b, c) = (note("a"), note("b"), note("c"))
        let library = FakeItemLibrary(items: [a, b, c], now: base)
        let browser = browserOnItems(library)
        browser.selection = [a.id, b.id, c.id]
        library.items[1].state = .trashed
        browser.keepItemChoice(in: library)
        #expect(browser.selection == [a.id, c.id], "only the item that went leaves the choice")
    }

    @Test func anItemDeletedWhileOpenAsAFullPageFromItemsGivesWayToTheNextRow() async throws {
        let items = [note("a", minutes: 3), note("b", minutes: 2), note("c", minutes: 1)]
        let library = FakeItemLibrary(items: items, now: base)
        let browser = browserOnItems(library)
        browser.itemIndex.follow(library, sort: IndexPlace.items.defaultSort)
        browser.selection = [items[1].id]
        #expect(browser.open([items[1].id], as: .fullPage))
        let before = browser.collectionItemIDs(in: library, order: ItemOrder())
        #expect(before == items.map(\.id), "Items follows the rows of its table, not another place's list")
        library.items[1].state = .trashed
        #expect(await eventually { browser.itemIndex.tabs?.all.count == 2 })
        browser.collectionItemsChanged(from: before, to: browser.collectionItemIDs(in: library, order: ItemOrder()))
        #expect(browser.selection == [items[2].id])
        #expect(browser.isCollectionItemPresented)
    }

    @Test func aFullPageFromItemsKeepsAnItemThatMovesToTheOtherTier() {
        let items = [note("a", minutes: 2), note("b", minutes: 1)]
        let library = FakeItemLibrary(items: items, now: base)
        let browser = browserOnItems(library)
        IndexPreferences.set(.yours, for: .items, in: browser.defaults)
        browser.itemIndex.follow(library, sort: IndexPlace.items.defaultSort)
        browser.selection = [items[0].id]
        browser.open([items[0].id], as: .fullPage)
        let before = browser.collectionItemIDs(in: library, order: ItemOrder())
        library.items[0].tier = .feed
        browser.collectionItemsChanged(from: before, to: browser.collectionItemIDs(in: library, order: ItemOrder()))
        #expect(browser.selection == [items[0].id])
    }

    @Test func aSearchOnItemsKeepsTheLibrarysOrderUntilAColumnIsChosen() {
        let (strongOld, weakNew) = (note("Search ranking", minutes: -9_000), note("A search aside", minutes: -1))
        let library = FakeItemLibrary(items: [strongOld, weakNew], now: base)
        let browser = browserOnItems(library)
        browser.searchText = "search"
        #expect(browser.ordersByRelevance)
        #expect(browser.itemIndexRows(in: library).map(\.id) == [strongOld.id, weakNew.id], "the library's own order")
        browser.orderSearch(byRelevance: false)
        #expect(browser.itemIndexRows(in: library).map(\.id) == [weakNew.id, strongOld.id], "the page's sort, the latest first")
        browser.orderSearch(byRelevance: true)
        #expect(browser.itemIndexRows(in: library).map(\.id) == [strongOld.id, weakNew.id])
    }

    @Test func revealingAnItemUnderTheOtherTabSwitchesToAllAndAsksForTheRow() {
        let mine = note("mine"), theirs = note("theirs", tier: .feed)
        let library = FakeItemLibrary(items: [mine, theirs], now: base)
        let browser = browserOnItems(library)
        IndexPreferences.set(.yours, for: .items, in: browser.defaults)
        browser.reveal(theirs, in: library, order: ItemOrder())
        #expect(IndexPreferences.tab(for: .items, in: browser.defaults) == .all)
        #expect(browser.selection == [theirs.id] && browser.itemToScrollTo == theirs.id)
        #expect(browser.showsItemsIndex, "a reveal on Items shows the row, not a page")
        IndexPreferences.set(.fromApps, for: .items, in: browser.defaults)
        browser.reveal(theirs, in: library, order: ItemOrder())
        #expect(IndexPreferences.tab(for: .items, in: browser.defaults) == .fromApps, "a tab that lists it stays")
    }

    // MARK: Keeping the rows

    @Test func aDeletedItemLeavesTheRowsAtOnceNotWhenTheyAreWorkedOutAgain() async {
        let items = (0..<(ItemIndexModel.inlineLimit + 1)).map { note("n\($0)", minutes: Double($0)) }
        let library = FakeItemLibrary(items: items, now: base)
        let model = ItemIndexModel(settling: .seconds(60))
        model.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(await eventually { model.tabs?.all.count == items.count })
        library.items[5].state = .trashed
        #expect(await eventually(within: .seconds(10)) { model.tabs?.all.count == items.count - 1 })
        #expect(model.tabs?.all.contains { $0.id == items[5].id } == false)
        #expect(model.tabs?.yours.count == items.count - 1)
    }

    @Test func leavingItemsKeepsTheRowsAndComingBackShowsThemLessWhatWentMeanwhile() async {
        let items = [note("a", minutes: 3), note("b", minutes: 2), note("c", minutes: 1)]
        let library = FakeItemLibrary(items: items, now: base)
        let model = ItemIndexModel()
        model.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(model.tabs?.all.count == 3)
        model.stop()
        #expect(model.tabs?.all.count == 3, "the rows stay while the page is away")
        library.items[1].state = .trashed
        model.follow(library, sort: IndexPlace.items.defaultSort)
        #expect(model.tabs?.all.map(\.title) == ["a", "c"], "shown at once, without the item deleted meanwhile")
        let other = FakeItemLibrary(items: [note("x")], now: base)
        model.reset()
        model.follow(other, sort: IndexPlace.items.defaultSort)
        #expect(model.tabs?.all.map(\.title) == ["x"], "another library never shows these rows")
    }

    @Test func theChosenRowKeepsItsPlaceWhileItIsEditedUntilAnotherIsChosen() async {
        let items = [note("a", minutes: 3), note("b", minutes: 2), note("c", minutes: 1)]
        let library = FakeItemLibrary(items: items, now: base)
        let model = ItemIndexModel()
        model.follow(library, sort: IndexPlace.items.defaultSort)
        model.pin(items[2].id)
        library.items[2].modified = base + 3_600
        #expect(await eventually { model.tabs?.all.first { $0.id == items[2].id }?.modified == base + 3_600 })
        #expect(model.tabs?.all.map(\.title) == ["a", "b", "c"], "the row edited stays last under a sort by the latest change")
        model.pin(items[0].id)
        library.items[0].modified = base + 100
        #expect(await eventually { model.tabs?.all.first { $0.id == items[0].id }?.modified == base + 100 })
        #expect(model.tabs?.all.map(\.title) == ["a", "c", "b"], "the row left behind goes to its place at the next change")
    }
}
