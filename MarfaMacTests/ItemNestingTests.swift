import Foundation
import Testing
@testable import MarfaMac

struct ItemNestingTests {
    private static func id(_ name: String) -> ItemID { ItemID(name) }

    /// Rows in order, each with its parent's name or none.
    private static func nesting(_ rows: [(String, String?)]) -> ItemNesting {
        ItemNesting(rows.map { (id: id($0.0), parent: $0.1.map(id)) })
    }

    private static func drawn(_ nesting: ItemNesting, open: [String] = [], limit: Int = .max) -> [String] {
        nesting.drawn(expanded: Set(open.map(id)), limit: limit).places.map { String(repeating: "-", count: $0.depth) + $0.id.rawValue }
    }

    @Test func aChildStandsUnderItsParentInTheRowsOrder() {
        let nesting = Self.nesting([("b", "p"), ("p", nil), ("a", "p"), ("q", nil)])
        #expect(Self.drawn(nesting) == ["p", "q"], "a parent starts closed")
        #expect(Self.drawn(nesting, open: ["p"]) == ["p", "-b", "-a", "q"])
        let places = nesting.drawn(expanded: [Self.id("p")]).places
        #expect(places.first?.children == 2)
        #expect(places.first?.isExpanded == true)
        #expect(places.map(\.index) == [1, 0, 2, 3], "each place finds its row")
    }

    @Test func aChildWhoseParentIsNotListedStandsAtTheTop() {
        // The filter kept the child and left its parent out.
        let nesting = Self.nesting([("child", "hidden parent"), ("other", nil)])
        #expect(nesting.isFlat)
        #expect(Self.drawn(nesting) == ["child", "other"])
    }

    @Test func anItemStandsOnce() {
        let nesting = Self.nesting([("p", nil), ("c", "p"), ("c", "p"), ("p", nil)])
        #expect(Self.drawn(nesting, open: ["p"]) == ["p", "-c"])
        #expect(nesting.drawnCount(expanded: [Self.id("p")]) == 2)
    }

    @Test func aParentCycleNeverRecurses() {
        // a under c, b under a, c under b: none reaches the top, so the first in order stands there.
        let nesting = Self.nesting([("b", "a"), ("a", "c"), ("c", "b"), ("self", "self")])
        #expect(Self.drawn(nesting, open: ["a", "b", "c"]) == ["b", "-c", "--a", "self"])
        #expect(nesting.ancestors(of: Self.id("a")) == [Self.id("c"), Self.id("b")])
        #expect(nesting.drawnCount(expanded: [Self.id("a"), Self.id("b"), Self.id("c")]) == 4)
    }

    @Test func aSubItemIsDrawnOnlyWhereEveryParentAboveIsOpen() {
        let nesting = Self.nesting([("p", nil), ("c", "p"), ("g", "c")])
        #expect(Self.drawn(nesting, open: ["c"]) == ["p"], "an open child under a closed parent stays hidden")
        #expect(nesting.drawnCount(expanded: [Self.id("c")]) == 1)
        #expect(Self.drawn(nesting, open: ["p", "c"]) == ["p", "-c", "--g"])
        #expect(nesting.position(of: Self.id("g"), expanded: [Self.id("p"), Self.id("c")]) == 2)
        #expect(nesting.position(of: Self.id("g"), expanded: [Self.id("p")]) == nil)
    }

    @Test func drawingStopsAtTheLimitAndStillCountsEveryRow() {
        let rows = [("p", nil)] + (0..<10).map { ("c\($0)", "p") } + [("q", nil)]
        let nesting = Self.nesting(rows)
        let drawn = nesting.drawn(expanded: [Self.id("p")], limit: 4)
        #expect(drawn.places.map(\.id.rawValue) == ["p", "c0", "c1", "c2"])
        #expect(drawn.total == 12)
    }

    // MARK: Paging

    private static func rows(_ specs: [(String, String?)]) -> [ItemTableRow] {
        specs.map { name, parent in
            var item = Item(
                id: ItemID(name), type: TypeID("core.task"), title: name, titleRule: .property("title"),
                properties: [Property(key: "title", value: .string(name))], version: ItemVersion(1), created: .now, modified: .now)
            if let parent {
                item.edgesOut = [Edge(id: EdgeID("e-\(name)"), type: "child-of", from: ItemID(name), to: .item(ItemID(parent)), origin: .property("child-of"))]
            }
            return ItemTableRow(item: item, typeLabel: "Task", typeIcon: nil, parent: nil)
        }
    }

    @Test func aPageCountsTheRowsDrawnSubItemsToo() {
        var specs: [(String, String?)] = []
        for parent in 0..<30 {
            specs.append(("p\(parent)", nil))
            specs.append(("p\(parent)c", "p\(parent)"))
        }
        let rows = Self.rows(specs)
        let nesting = ItemNesting(rows: rows)
        #expect(!nesting.isFlat)
        let paging = TablePaging()
        let closed = paging.slice(rows, nesting: nesting, expanded: [], size: .twentyFive)
        #expect(closed.rows.count == 25)
        #expect(closed.remaining == 5, "a closed parent's sub-items count toward nothing")
        let open = paging.slice(rows, nesting: nesting, expanded: [ItemID("p0"), ItemID("p1")], size: .twentyFive)
        #expect(open.rows.prefix(3).map(\.id.rawValue) == ["p0", "p0c", "p1"])
        #expect(open.places[1].depth == 1)
        #expect(open.remaining == 7)
    }

    @Test func revealingASubItemLoadsThePageItIsDrawnOn() {
        let specs: [(String, String?)] = (0..<60).map { ("r\($0)", nil) } + [("child", "r59")]
        let rows = Self.rows(specs)
        let nesting = ItemNesting(rows: rows)
        var paging = TablePaging()
        paging.reveal([ItemID("child")], rows: rows, nesting: nesting, groups: nil, collapsed: [], expanded: [], size: .fifty)
        #expect(paging.pages == 1, "a sub-item under a closed parent is drawn nowhere")
        paging.reveal([ItemID("child")], rows: rows, nesting: nesting, groups: nil, collapsed: [], expanded: [ItemID("r59")], size: .fifty)
        #expect(paging.pages == 2)
    }

    @Test func theListNestsWithinASectionAndHidesAClosedParentsSubItems() {
        let rows = Self.rows([("p", nil), ("c", "p"), ("q", nil), ("elsewhere", "q")])
        let today = ItemSection(group: .today, items: [rows[0].item, rows[1].item, rows[2].item])
        let earlier = ItemSection(group: .yesterday, items: [rows[3].item])
        let arrangement = ListArrangement(sections: [today, earlier], sorted: nil, content: nil)
        let closed = arrangement.nested(expanded: [])
        #expect(closed.ids.map(\.rawValue) == ["p", "q", "elsewhere"], "a child in another section stands at its top")
        #expect(closed.nesting[ItemID("p")]?.children == 1)
        let open = arrangement.nested(expanded: [ItemID("p")])
        #expect(open.ids.map(\.rawValue) == ["p", "c", "q", "elsewhere"])
        #expect(open.nesting[ItemID("c")]?.depth == 1)
    }
}
