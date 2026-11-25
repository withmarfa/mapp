import Foundation
import Testing
@testable import MarfaMac

/// Customize Layout's three groups: what is pinned, what is on the page and what is hidden, and what a change stores.
struct PageLayoutTests {
    private static let type = TypeID("aic.ticket")
    private static let catalogue = Catalogue()

    private nonisolated static func row(_ id: String) -> PageLayout.Row { PageLayout.Row(id: id, label: id, symbol: "text.alignleft") }
    private static let rows = ["a", "b", "c", "d", "e", "#linked"].map(row)

    private static func layout(_ rows: [PageLayout.Row] = rows, _ placements: PagePlacements = PagePlacements()) -> PageLayout {
        PageLayout(rows: rows, placement: placements.placement(of: type, in: catalogue))
    }

    private static func ids(_ rows: [PageLayout.Row]) -> [String] { rows.map(\.id) }

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
        #expect(Self.ids(moved.page) == ["c", "a", "b", "d", "e"])
        placements.apply(moved, of: Self.type, in: Self.catalogue)
        #expect(Self.ids(Self.layout(Self.rows, placements).page) == ["c", "a", "b", "d", "e"])
        let candidates = ["a", "b", "c"].map { PropertyRow(id: $0, label: $0, value: .text($0)) }
        #expect(placements.placement(of: Self.type, in: Self.catalogue).ordered(candidates, id: \.id).map(\.id) == ["c", "a", "b"])

        placements.apply(moved.moved("c", by: 2)!, of: Self.type, in: Self.catalogue)
        #expect(placements.choices["aic.ticket"]?.rowOrder == nil, "back in its default order")
        #expect(layout.moved("a", by: -1) == nil, "the first of its group cannot go up")
    }

    @Test func aFifthPinIsRefusedAndTheLayoutIsLeftAlone() {
        var layout = Self.layout(Self.rows)
        #expect(Self.ids(layout.pinned).isEmpty)
        layout = layout.moving("d", to: .pinned)!.moving("e", to: .pinned)!.moving("a", to: .pinned)!.moving("b", to: .pinned)!
        #expect(layout.pinned.count == PagePlacement.pinLimit && !layout.canPin)
        #expect(layout.moving("c", to: .pinned) == nil)
        #expect(layout.moving("#linked", to: .pinned) == nil)
        #expect(layout.moving("a", to: .pinned, at: 0) != nil, "a pinned row can still be moved among the pins")
    }

    @Test func aPinTheItemHasNoRowForStaysInStorageBehindTheShownPins() {
        var placements = PagePlacements()
        placements.setPins(["gone", "e"], of: Self.type)
        let layout = Self.layout(Self.rows, placements)
        #expect(Self.ids(layout.pinned) == ["e"])
        placements.apply(layout.moving("a", to: .pinned)!, of: Self.type, in: Self.catalogue)
        #expect(placements.pins(of: Self.type, in: Self.catalogue) == ["e", "a", "gone"])
    }
}
