import Foundation
import Testing
@testable import MarfaMac

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

    // MARK: Sorting

    @Test func theItemsPageKeepsItsOwnTabAndSort() throws {
        let defaults = ThrowawayDefaults.make("ItemIndexTests")
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
        browser.defaults = ThrowawayDefaults.make("ItemIndexTests")
        browser.sidebarItem = .allItems
        return browser
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
