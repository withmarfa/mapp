import AppKit
import Foundation
import Synchronization
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor
@Suite(.serialized, .hangLimit)
struct CommandPaletteTests {
    // MARK: Sections

    private typealias Pick = PaletteMatch.Pick

    /// `count` commands that all sit under File.
    private static func files(_ count: Int) -> [PaletteSections.CommandGroup] { Array(repeating: .file, count: count) }

    @Test func beforeTypingItListsTheRecentItemsThenEveryCommandAndNoPlace() {
        let sections = PaletteSections.forCommands(picks: [], typed: false, groups: Self.files(3), recentCount: 8)
        #expect(sections.map(\.kind) == [.recent, .group(.file)])
        #expect(sections[0].rows == (0..<PaletteSections.recentLimit).map(Pick.item))
        #expect(sections[1].rows == [.fixed(0), .fixed(1), .fixed(2)])
    }

    @Test func beforeTypingTheCommandsSitInTheirMenusInTheMenuBarsOrderAndEmptyGroupsAreDropped() {
        // Go, View, Settings, Looks, File, Edit, File: given out of order, listed in the menu bar's order, which opens
        // with the app menu and holds Layouts in the File menu.
        let groups: [PaletteSections.CommandGroup] = [.go, .view, .settings, .looks, .file, .edit, .file, .sortAndGroup]
        let sections = PaletteSections.forCommands(picks: [], typed: false, groups: groups, recentCount: 0)
        #expect(sections.map(\.kind) == [.group(.settings), .group(.file), .group(.looks), .group(.edit), .group(.view), .group(.sortAndGroup), .group(.go)])
        #expect(sections[1].rows == [.fixed(4), .fixed(6)], "a group keeps its commands in the order given")
        #expect(sections.map(\.kind.title) == ["Settings", "File", "Layouts", "Edit", "View", "Sort and Group", "Go"])
    }

    @Test func theGroupsFollowTheMenuBarFromTheAppMenuToDebug() {
        let titles = PaletteSections.CommandGroup.allCases.map(\.title)
        #expect(titles.prefix(9) == ["Settings", "File", "Layouts", "Edit", "Format", "View", "Sort and Group", "Text Size", "Go"])
        #if DEBUG
        #expect(titles.last == "Debug", "Debug comes last")
        #endif
    }

    @Test func beforeTypingACommandOnlyTypingFindsIsNotListedAndOnceTypedItIsStillRanked() {
        // Fixed 1 is a "New Task" row: in no menu group, so only a typed query lists it.
        let groups: [PaletteSections.CommandGroup?] = [.file, nil, .file]
        let untyped = PaletteSections.forCommands(picks: [], typed: false, groups: groups, recentCount: 0)
        #expect(untyped.map(\.kind) == [.group(.file)])
        #expect(untyped[0].rows == [.fixed(0), .fixed(2)])
        let typed = PaletteSections.forCommands(picks: [.fixed(1), .fixed(0)], scores: [0, 1], typed: true, groups: groups, recentCount: 0)
        #expect(typed.map(\.kind) == [.commands])
        #expect(typed[0].rows == [.fixed(1), .fixed(0)])
    }

    @Test func typingKeepsOneRankedCommandsSectionWhateverTheGroups() {
        let groups: [PaletteSections.CommandGroup] = [.view, .file, .go]
        let sections = PaletteSections.forCommands(picks: [.fixed(2), .fixed(0), .fixed(1)], scores: [0, 1, 2], typed: true, groups: groups, recentCount: 0)
        #expect(sections.map(\.kind) == [.commands])
        #expect(sections[0].rows == [.fixed(2), .fixed(0), .fixed(1)], "in score order, so Return runs the best match")
    }

    @Test func beforeTypingAnEmptyLibraryLeavesOnlyTheCommands() {
        let sections = PaletteSections.forCommands(picks: [], typed: false, groups: Self.files(2), recentCount: 0)
        #expect(sections.map(\.kind) == [.group(.file)])
    }

    @Test func typingSplitsTheRankedRowsIntoItemsPlacesAndCommandsKeepingTheirOrder() {
        // Commands are fixed 0 and 1, places are fixed 2 and 3.
        let picks: [Pick] = [.fixed(3), .item(4), .fixed(1), .item(0), .fixed(2), .fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, groups: Self.files(2), recentCount: 9)
        #expect(sections.map(\.kind) == [.items, .places, .commands])
        #expect(sections[0].rows == [.item(4), .item(0)])
        #expect(sections[1].rows == [.fixed(3), .fixed(2)])
        #expect(sections[2].rows == [.fixed(1), .fixed(0)])
        #expect(PaletteSections.resultCount(sections) == 6)
    }

    /// The sections ⌘K lists for a typed title, ranked as the palette ranks them. Commands are the first fixed titles.
    private func sections(fixed: [String], commandCount: Int, items: [String], typing query: String) -> [PaletteSections.Section<Pick>] {
        let scored = PaletteMatch.Titles().scoredPicks(fixed: fixed, items: items, query)
        return PaletteSections.forCommands(picks: scored.map(\.pick), scores: scored.map(\.score), typed: true, groups: Self.files(commandCount), recentCount: items.count)
    }

    @Test func theSectionHoldingTheBestMatchComesFirstSoReturnRunsTheCommandTyped() {
        let sections = sections(fixed: ["New Item", "New Task", "Inbox"], commandCount: 2, items: ["Test the new item flow", "Garden ideas"], typing: "new item")
        #expect(sections.map(\.kind) == [.commands, .items])
        #expect(sections[0].rows.first == .fixed(0), "New Item is the first row")
        #expect(sections[1].rows == [.item(0)])
    }

    @Test func anItemTypedByItsExactTitleLeadsTheCommandsThatHoldTheWords() {
        let sections = sections(fixed: ["New Item", "Show New Items"], commandCount: 2, items: ["new item"], typing: "new item")
        #expect(sections.map(\.kind) == [.items, .commands])
    }

    @Test func sectionsWhoseBestMatchesTieKeepItemsFirst() {
        let sections = sections(fixed: ["Rename Item", "Inbox"], commandCount: 1, items: ["Rename the shed", "Rename Garden"], typing: "ren")
        #expect(sections.first?.kind == .items)
        let tied = PaletteSections.forCommands(picks: [.fixed(0), .item(0)], scores: [1, 1], typed: true, groups: Self.files(1), recentCount: 1)
        #expect(tied.map(\.kind) == [.items, .commands])
    }

    @Test func aPlaceLeadsWhenItHoldsTheBestMatch() {
        let sections = sections(fixed: ["New Item", "Inbox"], commandCount: 1, items: ["Move to the inbox"], typing: "inbox")
        #expect(sections.map(\.kind) == [.places, .items])
    }

    @Test func itemsAreCutToEightWithALastRowThatSearchesTheItems() {
        let picks: [Pick] = (0..<52).map(Pick.item) + [.fixed(1), .fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, groups: Self.files(1), recentCount: 60)
        #expect(sections.map(\.kind) == [.items, .places, .commands])
        #expect(sections[0].rows == (0..<PaletteSections.itemLimit).map(Pick.item) + [.searchItems])
        #expect(sections[1].rows == [.fixed(1)])
        #expect(sections[2].rows == [.fixed(0)])
    }

    @Test func eightItemsOrFewerNeedNoRowToSearchTheItems() {
        let picks: [Pick] = (0..<PaletteSections.itemLimit).map(Pick.item)
        let sections = PaletteSections.forCommands(picks: picks, typed: true, groups: Self.files(0), recentCount: 20)
        #expect(sections[0].rows == picks)
    }

    @Test func theCountLeavesOutTheRowThatSearchesTheItems() {
        let picks: [Pick] = (0..<52).map(Pick.item) + [.fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, groups: Self.files(1), recentCount: 60)
        #expect(PaletteSections.resultCount(sections) == PaletteSections.itemLimit + 2)
        #expect(PaletteSections.resultCount(sections) { $0 != .searchItems } == PaletteSections.itemLimit + 1)
    }

    @Test func repeatedIdsAreMadeDistinctAndKeepTheirOrder() {
        let ids = ["command:Remove from “Trips”", "command:Delete", "command:Remove from “Trips”", "command:Remove from “Trips”"]
        let distinct = PaletteSections.distinct(ids)
        #expect(Set(distinct).count == ids.count)
        #expect(distinct[0] == ids[0] && distinct[1] == ids[1])
        #expect(PaletteSections.distinct(ids) == distinct, "the same list gives the same ids")
    }

    @Test func aSectionWithNoRowsIsDropped() {
        let sections = PaletteSections.forCommands(picks: [.fixed(0), .item(1)], typed: true, groups: Self.files(1), recentCount: 2)
        #expect(sections.map(\.kind) == [.items, .commands])
        let none = PaletteSections.forCommands(picks: [], typed: true, groups: Self.files(4), recentCount: 2)
        #expect(none.isEmpty)
        #expect(PaletteSections.resultCount(none) == 0)
    }

    @Test func searchListsTitlesThenTheTextAndDropsAnEmptySection() {
        let rows = ["oak top", "kitchen", "oak table", "garden"]
        let sections = PaletteSections.forSearch(rows: rows, typed: true) { $0.contains("oak") && $0 != "kitchen" }
        #expect(sections.map(\.kind) == [.titles, .inTheText])
        #expect(sections[0].rows == ["oak top", "oak table"])
        #expect(sections[1].rows == ["kitchen", "garden"])
        let onlyText = PaletteSections.forSearch(rows: rows, typed: true) { _ in false }
        #expect(onlyText.map(\.kind) == [.inTheText])
        #expect(PaletteSections.forSearch(rows: [String](), typed: true) { _ in true }.isEmpty)
    }

    @Test func searchWithNothingTypedListsTheRecentItems() {
        let sections = PaletteSections.forSearch(rows: ["a", "b"], typed: false) { _ in true }
        #expect(sections.map(\.kind) == [.recent])
    }

    // MARK: Actions

    @Test func anItemOffersOpenNewWindowBothLinksFavoritesVersionHistoryAndDelete() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(actions.map(\.kind) == [.open, .openInNewWindow, .copyLink, .copyWikiLink, .addToFavorites, .versionHistory, .delete])
        #expect(actions.last?.isDestructive == true)
        #expect(actions.first { $0.kind == .delete }?.keys == ["⌘", "⌫"])
    }

    @Test func aFavoriteOffersRemoveFromFavoritesInstead() {
        let kinds = PaletteAction.forItem(isFile: false, isFavorite: true, isActive: true).map(\.kind)
        #expect(kinds.contains(.removeFromFavorites))
        #expect(!kinds.contains(.addToFavorites))
    }

    @Test func aFileHasNoWikiLinkOrVersionHistoryAndAnItemInTheBinCannotBeDeletedOrFavored() {
        let file = PaletteAction.forItem(isFile: true, isFavorite: false, isActive: true).map(\.kind)
        #expect(file == [.open, .openInNewWindow, .copyLink, .addToFavorites, .delete])
        let binned = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: false).map(\.kind)
        #expect(binned == [.open, .openInNewWindow, .copyLink, .copyWikiLink, .versionHistory])
    }

    @Test func noItemActionDeletesImmediately() {
        for isActive in [true, false] {
            let titles = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: isActive).map(\.title)
            #expect(!titles.contains { $0.contains("Immediately") })
        }
    }

    @Test func aShortcutRunsOnlyAnActionTheRowOffersAndTheFieldShows() {
        let note = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(PaletteAction.reachable(.delete, among: note, filteredBy: "")?.kind == .delete)
        #expect(PaletteAction.reachable(.delete, among: note, filteredBy: "fav") == nil, "the field hides Delete")
        #expect(PaletteAction.reachable(.delete, among: PaletteAction.forCommand, filteredBy: "") == nil, "a command offers only Run")
        let file = PaletteAction.forItem(isFile: true, isFavorite: false, isActive: true)
        #expect(PaletteAction.reachable(.copyLink, among: file, filteredBy: "")?.kind == .copyLink, "a file has a link")
        #expect(PaletteAction.reachable(.copyWikiLink, among: file, filteredBy: "") == nil, "a file has no wiki link")
        #expect(PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true).first { $0.kind == .copyWikiLink }?.keys == [])
        #expect(PaletteActionsPanel.shortcutKinds.allSatisfy { PaletteActionsPanel.shortcut(of: $0) != nil })
    }

    @Test func theFirstActionReadsOpen() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(actions.first?.title == String(localized: "Open"))
    }

    @Test func aCommandOffersOnlyRun() {
        #expect(PaletteAction.forCommand.map(\.kind) == [.run])
    }

    @Test func theActionsFieldFiltersByTitle() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(PaletteAction.filtered(actions, by: "").count == actions.count)
        #expect(PaletteAction.filtered(actions, by: "fav").map(\.kind) == [.addToFavorites])
        #expect(PaletteAction.filtered(actions, by: "zzz").isEmpty)
    }

    @Test func aSearchFromACopyStillFillingNeverSaysNoResults() async throws {
        let source = FakeItemSource()
        source.report.update { $0.fill = LibraryFill(state: .filling, listed: 1, expected: 9) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: LibraryFixture.items, catalogue: LibraryFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        source.searchIncomplete.withLock { $0 = true }

        // The copy answers nothing, and says it may hold more.
        #expect(await eventually {
            let found = library.search("nothing", in: .everywhere)
            return !found.isPending && found.isIncomplete
        })
        let filling = library.search("nothing", in: .everywhere)
        #expect(filling.items.isEmpty)
        #expect(CommandPalette.emptyAnswer(searching: true, results: filling) == .stillLooking)

        // Once whole, the same words answer that nothing matches.
        source.searchIncomplete.withLock { $0 = false }
        source.report.update { $0.fill = LibraryFill(state: .complete, listed: 9, expected: 9) }
        #expect(await eventually {
            let found = library.search("nothing", in: .everywhere)
            return !found.isPending && !found.isIncomplete
        })
        #expect(CommandPalette.emptyAnswer(searching: true, results: library.search("nothing", in: .everywhere)) == .noResults)
    }

    @Test func theCommandsListSaysNoResultsWhateverTheLastSearchWas() {
        var results = SearchResults.none
        results.isIncomplete = true
        #expect(CommandPalette.emptyAnswer(searching: false, results: results) == .noResults)
    }
}
