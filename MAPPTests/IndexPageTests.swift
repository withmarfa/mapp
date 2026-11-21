import Foundation
import Testing
@testable import MAPP

/// The Items page's New row (which types it holds, in what order) and what an index page shows of its tools and filters.
@MainActor
@Suite(.hangLimit) struct IndexPageTests {
    private func types(_ ids: String...) -> [ItemTypeOption] {
        ids.map { ItemTypeOption(id: TypeID($0), label: $0, icon: nil) }
    }

    private var offered: [ItemTypeOption] {
        types("core.note", "core.task", "core.bookmark", "core.event", "core.person", "core.table")
    }

    // MARK: New row

    @Test func theRowStartsWithTheStartingTypesTheLibraryHas() {
        // The row is in the starting order, whatever order the library lists its types in, and holds no person.
        let shown = NewRowTypes.shown(offered, kept: nil)
        #expect(shown.map(\.id.rawValue) == ["core.note", "core.table", "core.task", "core.bookmark", "core.event"])
        #expect(NewRowTypes.shown(types("core.task"), kept: nil).map(\.id.rawValue) == ["core.task"])
    }

    @Test func aKeptListIsShownInItsOrderAndAnEmptyOneStaysEmpty() {
        #expect(NewRowTypes.shown(offered, kept: "core.event,core.note").map(\.id.rawValue) == ["core.event", "core.note"])
        #expect(NewRowTypes.shown(offered, kept: "").isEmpty)
        // A type the library no longer has, and a repeat, are skipped.
        #expect(NewRowTypes.shown(offered, kept: "gone.type,core.note,core.note").map(\.id.rawValue) == ["core.note"])
    }

    @Test func theEditListHoldsTheRowFirstThenTheOthers() {
        let listed = NewRowTypes.listed(offered, kept: "core.event,core.note")
        #expect(listed.inRow.map(\.id.rawValue) == ["core.event", "core.note"])
        #expect(listed.others.map(\.id.rawValue) == ["core.task", "core.bookmark", "core.person", "core.table"])
    }

    @Test func tickingAddsAtTheEndAndUntickingRemoves() {
        let row = NewRowTypes.shown(offered, kept: "core.note,core.task")
        #expect(NewRowTypes.toggled("core.event", row: row) == "core.note,core.task,core.event")
        #expect(NewRowTypes.toggled("core.note", row: row) == "core.task")
    }

    @Test func aFirstChangeKeepsTheStartingFiveLessWhatItRemoves() {
        let row = NewRowTypes.shown(offered, kept: nil)
        #expect(NewRowTypes.toggled("core.task", row: row) == "core.note,core.table,core.bookmark,core.event")
    }

    @Test func draggingMovesTheEntryToTheDropPlace() {
        let row = NewRowTypes.shown(offered, kept: "core.note,core.task,core.event")
        #expect(NewRowTypes.moved(row, from: IndexSet(integer: 0), to: 3) == "core.task,core.event,core.note")
        #expect(NewRowTypes.moved(row, from: IndexSet(integer: 2), to: 0) == "core.event,core.note,core.task")
    }

    // MARK: Tools and filters

    @Test func theItemsPageHasTheNewRowUntilAFilterTakesItsPlace() {
        let browser = Browser()
        browser.sidebarItem = .allItems
        #expect(browser.showsNewRow)
        browser.filterRowChoice[.allItems] = true
        #expect(browser.showsFilterRow)
        #expect(!browser.showsNewRow)
        browser.filterRowChoice[.allItems] = false
        #expect(browser.showsNewRow)
    }

    @Test func onlySourcesHasNoTools() {
        let browser = Browser()
        browser.sidebarItem = .sources
        #expect(!browser.indexPlaceHasTools)
        browser.sidebarItem = .collections
        #expect(browser.indexPlaceHasTools)
        #expect(!browser.showsNewRow)
    }

    @Test func theToolbarTakesOverOnlyOnceTheHeaderHasScrolledAway() {
        let browser = Browser()
        browser.sidebarItem = .collections
        #expect(!browser.showsIndexTools)
        browser.isIndexHeaderAway = true
        #expect(browser.showsIndexTools)
    }

    @Test func aCollectionsSourceFilterShowsTheRowAndTurningFilterOffClearsIt() {
        let browser = Browser()
        browser.sidebarItem = .collections
        #expect(!browser.showsFilterRow)
        browser.toggleCollectionSource("rss")
        #expect(browser.showsFilterRow)
        #expect(browser.indexIsFiltered)
        browser.toggleIndexFilter()
        #expect(!browser.showsFilterRow)
        #expect(!browser.indexIsFiltered)
    }
}
