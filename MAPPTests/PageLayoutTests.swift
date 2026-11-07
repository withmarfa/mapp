import Foundation
import Testing
@testable import MAPP

/// Customize Layout's three groups: what is pinned, what is on the page and what is hidden, and what a change stores.
struct PageLayoutTests {
    private static let type = TypeID("aic.ticket")
    private static let catalogue = Catalogue()

    private nonisolated static func row(_ id: String) -> PageLayout.Row { PageLayout.Row(id: id, label: id, symbol: "text.alignleft") }
    /// A type with no fields of its own: the built-in rows and Linked From.
    private static let builtIn = ["#type", "#updated", "#tags", "#linked"].map(row)
    private static let rows = ["#type", "#updated", "a", "b", "c", "#linked"].map(row)

    private static func layout(_ rows: [PageLayout.Row] = rows, _ placements: PagePlacements = PagePlacements()) -> PageLayout {
        PageLayout(rows: rows, placement: placements.placement(of: type, in: catalogue))
    }

    private static func ids(_ rows: [PageLayout.Row]) -> [String] { rows.map(\.id) }

    @Test func aTypeWithNoFieldsListsItsBuiltInRows() {
        let layout = Self.layout(Self.builtIn)
        #expect(Self.ids(layout.pinned) == ["#type", "#updated"], "the default pins that this type has")
        #expect(Self.ids(layout.page) == ["#tags"])
        #expect(Self.ids(layout.hidden) == ["#linked"], "Linked From is in the inspector by default")
    }

    @Test func aRowDraggedOnThePageKeepsTheOrderTheCopyShowedApartFromTheMovedRow() throws {
        // The page drew c, a, b, which is not this layout's own order (a, b, c); a dropped last must leave c first.
        let layout = Self.layout()
        #expect(Self.ids(layout.page) == ["a", "b", "c"])
        let moved = try #require(layout.listing(["c", "b", "a"], moving: "a"))
        #expect(Self.ids(moved.page) == ["c", "b", "a"], "the shown order, not the default with a moved")
        var placements = PagePlacements()
        placements.apply(moved, of: Self.type, in: Self.catalogue)
        #expect(placements.choices["aic.ticket"]?.rowOrder?.prefix(3) == ["c", "b", "a"])
    }

    @Test func aRowThePageDidNotDrawKeepsItsPlace() throws {
        let moved = try #require(Self.layout().listing(["c", "a"], moving: "c"))
        #expect(Self.ids(moved.page) == ["c", "b", "a"])
    }

    @Test func aListedOrderIgnoresWhatIsNotAPageRowAndKeepsWhatItDoesNotName() throws {
        let layout = Self.layout()
        let moved = try #require(layout.listing(["#type", "b", "gone", "b", "a"], moving: "a"))
        #expect(Self.ids(moved.page) == ["b", "a", "c"], "a pin, an unknown id and a repeat are ignored; c keeps its place after")
        #expect(Self.ids(moved.pinned) == Self.ids(layout.pinned))
        #expect(Self.ids(moved.hidden) == Self.ids(layout.hidden))
        #expect(layout.listing(["a", "b", "c"], moving: "#type") == nil, "a pin is not a page row")
        #expect(layout.listing(["a", "b", "c"], moving: "#linked") == nil, "a hidden row is not a page row")
        #expect(layout.listing(["a", "b", "c"], moving: "z") == nil)
    }

    @Test func aRowMovedBetweenGroupsIsOnOrOffThePageAccordingly() {
        var placements = PagePlacements()
        var layout = Self.layout(Self.rows, placements)
        layout = layout.moving("a", to: .hidden)!
        placements.apply(layout, of: Self.type, in: Self.catalogue)
        #expect(!placements.placement(of: Self.type, in: Self.catalogue).showsOnPage("a"))
        #expect(Self.ids(Self.layout(Self.rows, placements).hidden) == ["#linked", "a"])

        layout = layout.moving("a", to: .page, at: 0)!
        placements.apply(layout, of: Self.type, in: Self.catalogue)
        #expect(placements.placement(of: Self.type, in: Self.catalogue).showsOnPage("a"))
        #expect(Self.ids(Self.layout(Self.rows, placements).page).first == "a")
    }

    @Test func reorderingStoresTheOrderTheBlockFollowsAndTheDefaultOrderStoresNothing() {
        var placements = PagePlacements()
        let layout = Self.layout(Self.rows, placements)
        let moved = layout.moved("c", by: -2)!
        #expect(Self.ids(moved.page) == ["c", "a", "b"])
        placements.apply(moved, of: Self.type, in: Self.catalogue)
        #expect(Self.ids(Self.layout(Self.rows, placements).page) == ["c", "a", "b"])
        let candidates = ["a", "b", "c"].map { PropertyRow(id: $0, label: $0, value: .text($0)) }
        #expect(PropertyRow.block(candidates, placement: placements.placement(of: Self.type, in: Self.catalogue)).map(\.id) == ["c", "a", "b"])

        placements.apply(moved.moved("c", by: 2)!, of: Self.type, in: Self.catalogue)
        #expect(placements.choices["aic.ticket"]?.rowOrder == nil, "back in its default order")
        #expect(layout.moved("a", by: -1) == nil, "the first of its group cannot go up")
    }

    @Test func aFifthPinIsRefusedAndTheLayoutIsLeftAlone() {
        var layout = Self.layout(Self.rows)
        #expect(Self.ids(layout.pinned) == ["#type", "#updated"])
        layout = layout.moving("a", to: .pinned)!.moving("b", to: .pinned)!
        #expect(layout.pinned.count == PagePlacement.pinLimit && !layout.canPin)
        #expect(layout.moving("c", to: .pinned) == nil)
        #expect(layout.moving("#linked", to: .pinned) == nil)
        #expect(layout.moving("a", to: .pinned, at: 0) != nil, "a pinned row can still be moved among the pins")
    }

    @Test func pinningAHiddenRowShowsItAndUnpinningLeavesItOnThePage() {
        var placements = PagePlacements()
        placements.setShown(false, row: "a", of: Self.type)
        var layout = Self.layout(Self.rows, placements)
        #expect(Self.ids(layout.hidden) == ["a", "#linked"])
        layout = layout.moving("a", to: .pinned)!
        placements.apply(layout, of: Self.type, in: Self.catalogue)
        #expect(placements.pins(of: Self.type, in: Self.catalogue) == ["#type", "#updated", "a", "child-of"], "the default parent pin has no row here and stays")
        let unpinned = Self.layout(Self.rows, placements).moving("a", to: .page)!
        placements.apply(unpinned, of: Self.type, in: Self.catalogue)
        #expect(Self.ids(Self.layout(Self.rows, placements).page).contains("a"))
    }

    @Test func aPinTheItemHasNoRowForStaysInStorageBehindTheShownPins() {
        var placements = PagePlacements()
        placements.setPins(["gone", "#type"], of: Self.type)
        let layout = Self.layout(Self.rows, placements)
        #expect(Self.ids(layout.pinned) == ["#type"])
        placements.apply(layout.moving("a", to: .pinned)!, of: Self.type, in: Self.catalogue)
        #expect(placements.pins(of: Self.type, in: Self.catalogue) == ["#type", "a", "gone"])
    }

    @Test func linkedFromOnThePageIsOnItAndHidingItMovesItBack() {
        var placements = PagePlacements()
        placements.apply(Self.layout(Self.rows).moving("#linked", to: .page)!, of: Self.type, in: Self.catalogue)
        #expect(placements.placement(of: Self.type, in: Self.catalogue).linkedFromPlace == .page)
        placements.apply(Self.layout(Self.rows, placements).moving("#linked", to: .hidden)!, of: Self.type, in: Self.catalogue)
        #expect(placements.placement(of: Self.type, in: Self.catalogue).linkedFromPlace == .inspector)
    }
}
