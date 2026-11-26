import Foundation
import Testing
@testable import MarfaMac

struct DigestLayoutTests {
    @Test func pilesKeepTheirIdentityWhenTheNewestItemGoesAway() throws {
        let first = item("earliest", day: 1, edge: "in-thread", target: "thread", source: "mail")
        let second = item("reply", day: 2, edge: "in-thread", target: "thread", source: "folder")
        let third = item("latest", day: 3, edge: "in-thread", target: "thread", source: "mail")
        let highlight = item("highlight", day: 4, edge: "excerpt-of", target: "missing-book", source: "reader")
        let quote = item("quote", day: 5, edge: "excerpt-of", target: "missing-book", source: "reader")
        let thread = item("thread", day: 0, source: "mail")
        let items = [first, second, quote, third, highlight, thread]

        let piles = try #require(DigestLayout.sections([ItemSection(items: items)], stacking: true).first?.piles)
        #expect(piles.map(\.newest.id) == [quote.id, third.id, thread.id])
        #expect(piles.map { $0.earlier.map(\.id) } == [[highlight.id], [second.id, first.id], []])

        let remaining = items.filter { $0.id != third.id }
        let afterSync = try #require(DigestLayout.sections([ItemSection(items: remaining)], stacking: true).first?.piles)
        #expect(afterSync.first(where: { $0.id == piles[1].id })?.newest.id == second.id)
        #expect(DigestLayout.sections([ItemSection(items: items)], stacking: false).first?.piles.map(\.newest.id) == items.map(\.id))
    }

    @MainActor
    @Test func choosingAnEarlierItemOpensItsPile() throws {
        let earlier = item("earlier", day: 1, edge: "in-thread", target: "thread", source: "mail")
        let newest = item("newest", day: 2, edge: "in-thread", target: "thread", source: "mail")
        let sections = DigestLayout.sections([ItemSection(items: [newest, earlier])], stacking: true)
        let pile = try #require(sections.first?.piles.first)
        let browser = Browser()
        browser.selection = [earlier.id]
        browser.viewMode = .digest
        browser.digestDisplay = DigestLayout.Display(place: browser.shown, sections: sections)

        #expect(browser.selection == [earlier.id])
        #expect(browser.expandedDigestPiles == [pile.id])
        #expect(browser.digestOrder == [newest.id, earlier.id])

        browser.toggleDigestPile(pile)
        #expect(browser.selection == [newest.id])
        #expect(browser.digestOrder == [newest.id])

        browser.selection = [earlier.id]
        #expect(browser.digestOrder == [newest.id, earlier.id])
    }

    private func item(_ name: String, day: Int, edge: String? = nil, target: String = "", source: String) -> Item {
        let id = ItemID(name)
        let date = Date(timeIntervalSince1970: TimeInterval(day * 86_400))
        let edges = edge.map { [Edge(id: EdgeID(name), type: $0, from: id, to: .item(ItemID(target)), origin: .property($0))] } ?? []
        return Item(
            id: id, type: TypeID("test.item"), title: name, titleRule: .property("title"), version: ItemVersion(1),
            created: date, modified: date, edgesOut: edges, source: source)
    }
}
