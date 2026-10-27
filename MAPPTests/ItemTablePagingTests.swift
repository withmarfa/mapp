import Foundation
import Testing
@testable import MAPP

struct ItemTablePagingTests {
    private static func rows(_ count: Int, prefix: String = "r") -> [ItemTableRow] {
        (0..<count).map { index in
            let title = "\(prefix)\(index)"
            let item = Item(
                id: ItemID(title), type: TypeID("core.note"), title: title, titleRule: .property("title"),
                properties: [Property(key: "title", value: .string(title))],
                version: ItemVersion(1), created: .now, modified: .now)
            return ItemTableRow(item: item, typeLabel: "Note", typeIcon: nil, parent: nil)
        }
    }

    private static func group(_ id: String, _ count: Int) -> ItemTableGroup {
        ItemTableGroup(id: id, title: id, rows: rows(count, prefix: id))
    }

    @Test func aPageSizeIsOneOfFourAndStartsAtFifty() {
        #expect(TablePageSize.allCases.map(\.rawValue) == [25, 50, 100, 200])
        #expect(TablePageSize.standard.rawValue == 50)
        #expect(TablePageSize(rawValue: 75) == nil)
    }

    @Test func theFirstPageShowsPageSizeRowsAndCountsWhatIsLeft() {
        let paging = TablePaging()
        let slice = paging.slice(Self.rows(120), size: .fifty)
        #expect(slice.rows.count == 50)
        #expect(slice.remaining == 70)
        #expect(slice.rows.first?.id == ItemID("r0"))
        let short = Self.rows(10)
        #expect(paging.slice(short, size: .fifty) == .init(rows: short, remaining: 0))
    }

    @Test func loadMoreAddsOnePageAndStopsAtTheEnd() {
        var paging = TablePaging()
        let rows = Self.rows(120)
        paging.loadMore()
        #expect(paging.slice(rows, size: .fifty).rows.count == 100)
        paging.loadMore()
        #expect(paging.slice(rows, size: .fifty) == .init(rows: rows, remaining: 0))
    }

    @Test func eachGroupPagesOnItsOwn() {
        var paging = TablePaging()
        let (first, second) = (Self.group("a", 60), Self.group("b", 60))
        paging.loadMore(group: "a")
        #expect(paging.slice(first.rows, size: .fifty, group: "a").remaining == 0)
        #expect(paging.slice(second.rows, size: .fifty, group: "b").remaining == 10)
    }

    @Test func revealingASelectedRowLoadsEnoughPages() {
        var paging = TablePaging()
        let rows = Self.rows(300)
        paging.reveal([ItemID("r120")], rows: rows, groups: nil, collapsed: [], size: .fifty)
        #expect(paging.pages == 3)
        paging.reveal([ItemID("r3")], rows: rows, groups: nil, collapsed: [], size: .fifty)
        #expect(paging.pages == 3, "a row already shown loads nothing")
        paging.reveal([ItemID("nowhere")], rows: rows, groups: nil, collapsed: [], size: .fifty)
        #expect(paging.pages == 3, "a row the table does not hold loads nothing")
    }

    @Test func revealingInGroupsLoadsOnlyTheGroupHoldingItAndSkipsFoldedOnes() {
        var paging = TablePaging()
        let groups = [Self.group("a", 120), Self.group("b", 120)]
        paging.reveal([ItemID("a110"), ItemID("b110")], rows: [], groups: groups, collapsed: ["b"], size: .fifty)
        #expect(paging.pages(of: "a") == 3)
        #expect(paging.pages(of: "b") == 1)
    }

    // MARK: When the count starts again

    private static func key(
        place: SidebarItem = .allNotes, search: String = "", configure: (inout ItemTableOptions) -> Void = { _ in }
    ) -> TablePagingKey {
        var options = ItemTableOptions()
        configure(&options)
        return TablePagingKey(place: place, search: search, byRelevance: false, options: options)
    }

    @Test func theCountStartsAgainWhenWhatIsShownChanges() {
        let base = Self.key()
        #expect(base != Self.key(place: .recents))
        #expect(base != Self.key(search: "x"))
        #expect(base != Self.key { $0.pageSize = .twoHundred })
        #expect(base != Self.key { $0.grouping = .none })
        #expect(base != Self.key { $0.filters = ["status": ["done"]] })
        #expect(base != Self.key { $0.sort = [ItemTableComparator(column: .title, order: .reverse)] })
    }

    @Test func aFoldedGroupDoesNotStartTheCountAgain() {
        #expect(Self.key() == Self.key { $0.collapsed = ["done"] })
    }

    @Test func theBrowserKeepsPagesUntilTheKeyChanges() {
        let browser = Browser()
        browser.loadMoreTableRows()
        #expect(browser.tablePaging.pages == 2)
        browser.tableOptions[browser.item, default: .init()].collapsed = ["x"]
        #expect(browser.tablePaging.pages == 2)
        browser.tableOptions[browser.item, default: .init()].pageSize = .twentyFive
        #expect(browser.tablePaging.pages == 1)
        browser.loadMoreTableRows()
        browser.searchText = "plan"
        #expect(browser.tablePaging.pages == 1)
    }
}
