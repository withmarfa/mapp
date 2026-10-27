import Foundation
import Testing
@testable import MAPP

@MainActor
@Suite struct SearchOrderTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let ranked = NoteOrder(sort: .dateEdited, groupsByDate: true)

    /// A strong match edited long ago, then a weak one edited just now, in the order the fake ranks them (its list order).
    private func makeLibrary() -> (FakeItemLibrary, strongOld: Item, weakNew: Item) {
        let strongOld = FakeItemLibrary.note("Search ranking", modified: start - 90 * 86_400)
        let weakNew = FakeItemLibrary.note("Shopping", modified: start - 60)
        return (FakeItemLibrary(items: [strongOld, weakNew], bodies: [weakNew.id: "a search aside"], now: start), strongOld, weakNew)
    }

    private func listed(_ browser: Browser, _ library: FakeItemLibrary) -> [ItemID] {
        browser.sections(in: library, order: ranked, now: start).flatMap { $0.items.map(\.id) }
    }

    @Test func theListRanksASearchAndClearingItGivesBackTheChosenSort() {
        let (library, strongOld, weakNew) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: ranked)
        #expect(listed(browser, library) == [weakNew.id, strongOld.id])

        browser.searchText = "search"
        #expect(browser.ordersByRelevance)
        let sections = browser.sections(in: library, order: ranked, now: start)
        #expect(sections.count == 1 && sections.first?.group == nil)
        #expect(listed(browser, library) == [strongOld.id, weakNew.id], "a strong old match outranks a weak new one")

        // The person's own sort is a choice of theirs for this search, and does not outlast it.
        browser.orderSearch(byRelevance: false)
        #expect(listed(browser, library) == [weakNew.id, strongOld.id])
        browser.orderSearch(byRelevance: true)
        #expect(listed(browser, library) == [strongOld.id, weakNew.id])

        browser.searchText = ""
        #expect(!browser.ordersByRelevance)
        #expect(listed(browser, library) == [weakNew.id, strongOld.id])
        browser.orderSearch(byRelevance: false)
        #expect(browser.relevanceChoice == nil, "there is no search to pick an order for")
        browser.searchText = "search"
        #expect(browser.ordersByRelevance, "the next search starts on relevance")
    }

    @Test func theGalleryKeepsItsSortUntilRelevanceIsPickedThere() {
        let (library, strongOld, weakNew) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: ranked)
        browser.viewMode = .gallery
        browser.searchText = "search"
        #expect(!browser.ordersByRelevance)
        #expect(listed(browser, library) == [weakNew.id, strongOld.id])
        browser.orderSearch(byRelevance: true)
        #expect(listed(browser, library) == [strongOld.id, weakNew.id])
    }

    @Test func theTableKeepsItsSortUntilRelevanceIsPickedAndColumnSortingStillWorks() {
        let (library, strongOld, weakNew) = makeLibrary()
        let browser = Browser()
        browser.show(.allNotes, in: library, order: ranked)
        browser.viewMode = .table
        browser.searchText = "search"
        func rows() -> [ItemID] { browser.tableContent(in: library).rows.map(\.item.id) }
        #expect(rows() == [weakNew.id, strongOld.id], "the table starts on its own sort, Edited, newest first")

        browser.orderSearch(byRelevance: true)
        #expect(rows() == [strongOld.id, weakNew.id])

        // A column sort the person picks replaces relevance, in either direction.
        browser.orderSearch(byRelevance: false)
        browser.tableOptions[.allNotes, default: .init()].sort = [ItemTableComparator(column: .edited, order: .reverse)]
        #expect(rows() == [weakNew.id, strongOld.id])
        browser.tableOptions[.allNotes, default: .init()].sort = [ItemTableComparator(column: .edited, order: .forward)]
        #expect(rows() == [strongOld.id, weakNew.id])

        // Relevance sets the stored sort aside without erasing it.
        browser.tableOptions[.allNotes, default: .init()].sort = [ItemTableComparator(column: .edited, order: .reverse)]
        browser.orderSearch(byRelevance: true)
        #expect(rows() == [strongOld.id, weakNew.id])
        browser.orderSearch(byRelevance: false)
        #expect(rows() == [weakNew.id, strongOld.id])
    }

    @Test func thePaletteListsInRankOrderSoAStrongOldMatchIsNotCutOff() {
        let (library, strongOld, _) = makeLibrary()
        // Sixty weaker matches, each newer than the strong one, ranked after it.
        let weaker = (0..<60).map { FakeItemLibrary.note("Search \($0)", modified: start - Double($0)) }
        library.items.append(contentsOf: weaker)
        let results = library.search("search", in: .everywhere)
        let listed = CommandPalette.listed(results)
        #expect(listed.count == CommandPalette.searchLimit)
        #expect(listed.first?.id == strongOld.id)
        #expect(listed.map(\.id) == results.items.prefix(CommandPalette.searchLimit).map(\.id))
    }
}
