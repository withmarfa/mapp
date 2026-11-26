import Foundation
import Testing
@testable import MarfaMac

/// The choice follows the sub-items the table and the list draw (`ItemNesting`): a chosen sub-item opens its parents,
/// closing a parent takes its hidden sub-items out of the choice, and the first item and the arrows walk the rows drawn.
@MainActor
struct SubItemSelectionTests {
    private static let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let parent = ItemID("parent")
    private static let child = ItemID("child")
    private static let other = ItemID("other")

    /// A parent, its child, edited last so it leads the place's order, and one more item.
    private func library() -> FakeItemLibrary {
        var child = FakeItemLibrary.note("Child", modified: Self.now, id: Self.child)
        child.edgesOut = [Edge(id: EdgeID("child-of-child"), type: "child-of", from: Self.child, to: .item(Self.parent), origin: .property("child-of"))]
        return FakeItemLibrary(
            items: [
                FakeItemLibrary.note("Parent", modified: Self.now.addingTimeInterval(-200), id: Self.parent),
                child,
                FakeItemLibrary.note("Other", modified: Self.now.addingTimeInterval(-100), id: Self.other),
            ],
            now: Self.now)
    }

    private func browser(_ library: FakeItemLibrary, mode: ItemViewMode) -> Browser {
        let browser = Browser()
        browser.defaults = ThrowawayDefaults.make("SubItemSelectionTests")
        browser.adopt(library)
        browser.showing = .library
        browser.viewMode = mode
        browser.tableOptions[.library] = ItemTableOptions(grouping: .none)
        return browser
    }

    private func drawn(_ browser: Browser, in library: FakeItemLibrary) -> [ItemID] {
        browser.orderBehind(in: library, order: ItemOrder())
    }

    @Test(arguments: [ItemViewMode.table, .list])
    func theFirstItemAndTheArrowsWalkTheRowsDrawn(mode: ItemViewMode) {
        let library = library()
        let browser = browser(library, mode: mode)
        browser.selectFirstItem(in: library, order: ItemOrder())
        #expect(browser.selection.count == 1)
        #expect(browser.selection != [Self.child], "a sub-item under a closed parent is not the first item drawn")
        #expect(!drawn(browser, in: library).contains(Self.child))
        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        let open = drawn(browser, in: library)
        let at = try? #require(open.firstIndex(of: Self.parent))
        #expect(at.map { open[$0 + 1] } == Self.child, "next after an open parent is its sub-item")
    }

    @Test(arguments: [ItemViewMode.table, .list])
    func closingAParentTakesItsHiddenSubItemsOutOfTheChoice(mode: ItemViewMode) {
        let library = library()
        let browser = browser(library, mode: mode)
        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        browser.selection = [Self.child]
        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        #expect(browser.selection == [Self.parent], "the choice moves to the parent")

        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        browser.selection = [Self.child, Self.other]
        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        #expect(browser.selection == [Self.other], "what stays drawn stays chosen")
    }

    @Test func aSubItemChosenInTheListOpensItsParentsAndStaysChosen() {
        let library = library()
        let browser = browser(library, mode: .list)
        let before = browser.arrangement(in: library, order: ItemOrder(), now: Self.now)
        #expect(!before.shownIDs.contains(Self.child))
        // Back or a link chooses the sub-item while its parent is closed, and the list's items then change.
        browser.selection = [Self.child]
        browser.keepSelection(from: before.shownIDs, to: before.shownIDs.filter { $0 != Self.other }, holds: before.holds)
        #expect(browser.selection == [Self.child], "the list holds the sub-item, so the choice does not jump")
        browser.openParents(of: browser.selection, in: before.nestings)
        #expect(browser.expandedHere == [Self.parent])
        let after = browser.arrangement(in: library, order: ItemOrder(), now: Self.now)
        #expect(after.shownIDs.contains(Self.child))
        #expect(after.nesting[Self.child]?.depth == 1)
    }

    @Test func openingAParentInTheListOrdersNothingAgain() {
        let library = library()
        let browser = browser(library, mode: .list)
        browser.tableOptions[.library] = nil
        _ = browser.arrangement(in: library, order: ItemOrder(), now: Self.now)
        let counts = browser.placeWorkCounts
        browser.toggleSubItems(of: Self.parent, in: library, order: ItemOrder())
        #expect(browser.arrangement(in: library, order: ItemOrder(), now: Self.now).shownIDs.contains(Self.child))
        browser.viewMode = .gallery
        #expect(browser.arrangement(in: library, order: ItemOrder(), now: Self.now).ids.contains(Self.child), "the gallery does not nest")
        #expect(browser.placeWorkCounts == counts)
    }

    @Test func aPlaceWhoseTypesHoldNoSubItemsIsNotNested() {
        let library = library()
        var catalogue = library.catalogue
        let parentOf = try? #require(catalogue.edgeTypes[MarfaMapping.parentEdge])
        catalogue.edgeTypes[MarfaMapping.parentEdge] = parentOf.map {
            EdgeTypeInfo(
                id: $0.id, label: $0.label, reverseLabel: $0.reverseLabel, reverseName: $0.reverseName, cardinality: $0.cardinality,
                writtenFrom: .to, fromTypes: [TypeID("test.project")], toTypes: [])
        }
        library.catalogue = catalogue
        let table = browser(library, mode: .table)
        #expect(table.tableContent(in: library).nesting.isFlat)
        let list = browser(library, mode: .list)
        #expect(list.arrangement(in: library, order: ItemOrder(), now: Self.now).nestings.isEmpty)
    }

    @Test func aGroupedTableNestsByGroupAndNotAsAWhole() {
        let library = library()
        let browser = browser(library, mode: .table)
        browser.tableOptions[.library] = ItemTableOptions(grouping: .column(ItemTableColumn.type.id))
        let content = browser.tableContent(in: library)
        #expect(content.nesting.isFlat)
        #expect(content.groupNestings.values.contains { !$0.isFlat })
    }
}

/// Share and Copy Links take the chosen items in the order the table draws them (`Browser.inListOrder`).
@MainActor
struct ChosenItemOrderTests {
    @Test func aGroupedTableGivesTheChosenItemsGroupByGroupNotInTheSortsOrder() {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
        func task(_ title: String, _ status: String) -> Item {
            var item = FakeItemLibrary.note(title, modified: now)
            item.type = TypeID("core.task")
            item.properties = [Property(key: "status", value: .string(status))]
            return item
        }
        let first = task("A first", "todo")
        let second = task("B second", "done")
        let third = task("C third", "todo")
        let library = FakeItemLibrary(items: [second, first, third], now: now)
        let browser = Browser()
        browser.defaults = ThrowawayDefaults.make("ChosenItemOrderTests")
        browser.adopt(library)
        browser.showing = .type(TypeID("core.task"))
        browser.viewMode = .table
        browser.tableOptions[browser.shown] = ItemTableOptions(
            grouping: .column("field.status"), sort: [ItemTableComparator(column: .title, order: .forward)])
        // The window draws the table before anything is shared.
        let drawn = browser.tableContent(in: library).drawnIDs(expanded: [])
        #expect(drawn != [first.id, second.id, third.id], "the groups, not the sort, decide where the second item stands")
        #expect(browser.inListOrder([third.id, second.id, first.id], in: library) == drawn)
    }
}
