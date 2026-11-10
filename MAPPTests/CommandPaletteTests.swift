import AppKit
import Foundation
import SwiftUI
import Testing
@testable import MAPP

@MainActor
@Suite(.serialized, .hangLimit)
struct CommandPaletteTests {
    /// What an accessibility element answers to `selector`, whatever class SwiftUI made it.
    private static func answer(_ element: NSObject, _ selector: String) -> Any? {
        let selector = NSSelectorFromString(selector)
        return element.responds(to: selector) ? element.perform(selector)?.takeUnretainedValue() : nil
    }

    /// Every label the palette's rows give the accessibility tree.
    private func labels(of view: NSView) -> [String] {
        var found: [String] = []
        func walk(_ element: Any?, _ depth: Int = 0) {
            guard depth < 12, let element = element as? NSObject else { return }
            if let label = Self.answer(element, "accessibilityLabel") as? String, !label.isEmpty { found.append(label) }
            for child in Self.answer(element, "accessibilityChildren") as? [Any] ?? [] { walk(child, depth + 1) }
        }
        walk(view)
        return found
    }

    @Test func theCommandsFollowTheEditorBecomingReadyWhileTheQueryStaysTheSame() async throws {
        let page = try await EditorTests.Page()
        let note = page.library.add("Body")
        let browser = Browser()
        browser.show(.allNotes, in: page.library, order: NoteOrder())
        browser.selection = [note.id]
        browser.palette = .commands

        // SwiftUI builds its accessibility elements only once an assistive client is attached.
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXManualAccessibility"))
        NSApplication.shared.accessibilitySetValue(true, forAttribute: NSAccessibility.Attribute(rawValue: "AXEnhancedUserInterface"))
        let window = TestWindow(contentRect: NSRect(x: 100, y: 100, width: 700, height: 600), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: CommandPalette(browser: browser, editor: page.editor, mode: .commands).environment(\.library, page.library))
        window.contentView = host
        window.orderFrontRegardless()
        defer { window.orderOut(nil); window.contentView = nil; window.close() }

        #expect(try await eventuallyAsking {
            host.layoutSubtreeIfNeeded()
            return labels(of: host).contains { $0.contains("Settings") }
        }, "the palette lists its commands: \(labels(of: host))")
        #expect(!labels(of: host).contains { $0.hasPrefix("Bold") }, "no note is on the page yet")
        #expect(labels(of: host).contains { $0.hasPrefix("New Window") }, "New Window is a command of the palette")

        try await page.show(note.id)
        #expect(try await eventuallyAsking {
            host.layoutSubtreeIfNeeded()
            return labels(of: host).contains { $0.hasPrefix("Bold") }
        }, "the formatting commands arrive once the page holds the note")
        // The list builds only the rows in view, so each editor-only command is asked for by its own query, which
        // narrows the list to it.
        for title in ["Heading 4", "Heading 5", "Heading 6", "Highlight", "Link"] {
            browser.paletteSeed = title
            let seeded = NSHostingView(rootView: CommandPalette(browser: browser, editor: page.editor, mode: .commands).environment(\.library, page.library))
            window.contentView = seeded
            #expect(try await eventuallyAsking {
                seeded.layoutSubtreeIfNeeded()
                return labels(of: seeded).contains { $0.hasPrefix(title) }
            }, "\(title) is offered with the other formats: \(labels(of: seeded))")
        }
    }

    // MARK: Sections

    private typealias Pick = PaletteMatch.Pick

    @Test func beforeTypingItListsTheRecentItemsThenEveryCommandAndNoPlace() {
        let sections = PaletteSections.forCommands(picks: [], typed: false, commandCount: 3, recentCount: 8)
        #expect(sections.map(\.kind) == [.recent, .commands])
        #expect(sections[0].rows == (0..<PaletteSections.recentLimit).map(Pick.item))
        #expect(sections[1].rows == [.fixed(0), .fixed(1), .fixed(2)])
    }

    @Test func beforeTypingAnEmptyLibraryLeavesOnlyTheCommands() {
        let sections = PaletteSections.forCommands(picks: [], typed: false, commandCount: 2, recentCount: 0)
        #expect(sections.map(\.kind) == [.commands])
    }

    @Test func typingSplitsTheRankedRowsIntoItemsPlacesAndCommandsKeepingTheirOrder() {
        // Commands are fixed 0 and 1, places are fixed 2 and 3.
        let picks: [Pick] = [.fixed(3), .item(4), .fixed(1), .item(0), .fixed(2), .fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, commandCount: 2, recentCount: 9)
        #expect(sections.map(\.kind) == [.items, .places, .commands])
        #expect(sections[0].rows == [.item(4), .item(0)])
        #expect(sections[1].rows == [.fixed(3), .fixed(2)])
        #expect(sections[2].rows == [.fixed(1), .fixed(0)])
        #expect(PaletteSections.resultCount(sections) == 6)
    }

    /// The sections ⌘K lists for a typed title, ranked as the palette ranks them. Commands are the first fixed titles.
    private func sections(fixed: [String], commandCount: Int, items: [String], typing query: String) -> [PaletteSections.Section<Pick>] {
        let scored = PaletteMatch.Titles().scoredPicks(fixed: fixed, items: items, query)
        return PaletteSections.forCommands(picks: scored.map(\.pick), scores: scored.map(\.score), typed: true, commandCount: commandCount, recentCount: items.count)
    }

    @Test func theSectionHoldingTheBestMatchComesFirstSoReturnRunsTheCommandTyped() {
        let sections = sections(fixed: ["New Item", "New Note", "Inbox"], commandCount: 2, items: ["Test the new item flow", "Garden ideas"], typing: "new item")
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
        let tied = PaletteSections.forCommands(picks: [.fixed(0), .item(0)], scores: [1, 1], typed: true, commandCount: 1, recentCount: 1)
        #expect(tied.map(\.kind) == [.items, .commands])
    }

    @Test func aPlaceLeadsWhenItHoldsTheBestMatch() {
        let sections = sections(fixed: ["New Note", "Inbox"], commandCount: 1, items: ["Move to the inbox"], typing: "inbox")
        #expect(sections.map(\.kind) == [.places, .items])
    }

    @Test func itemsAreCutToEightWithALastRowThatSearchesTheNotes() {
        let picks: [Pick] = (0..<52).map(Pick.item) + [.fixed(1), .fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, commandCount: 1, recentCount: 60)
        #expect(sections.map(\.kind) == [.items, .places, .commands])
        #expect(sections[0].rows == (0..<PaletteSections.itemLimit).map(Pick.item) + [.searchNotes])
        #expect(sections[1].rows == [.fixed(1)])
        #expect(sections[2].rows == [.fixed(0)])
    }

    @Test func eightItemsOrFewerNeedNoRowToSearchTheNotes() {
        let picks: [Pick] = (0..<PaletteSections.itemLimit).map(Pick.item)
        let sections = PaletteSections.forCommands(picks: picks, typed: true, commandCount: 0, recentCount: 20)
        #expect(sections[0].rows == picks)
    }

    @Test func theCountLeavesOutTheRowThatSearchesTheNotes() {
        let picks: [Pick] = (0..<52).map(Pick.item) + [.fixed(0)]
        let sections = PaletteSections.forCommands(picks: picks, typed: true, commandCount: 1, recentCount: 60)
        #expect(PaletteSections.resultCount(sections) == PaletteSections.itemLimit + 2)
        #expect(PaletteSections.resultCount(sections) { $0 != .searchNotes } == PaletteSections.itemLimit + 1)
    }

    @Test func repeatedIdsAreMadeDistinctAndKeepTheirOrder() {
        let ids = ["command:Remove from “Trips”", "command:Delete", "command:Remove from “Trips”", "command:Remove from “Trips”"]
        let distinct = PaletteSections.distinct(ids)
        #expect(Set(distinct).count == ids.count)
        #expect(distinct[0] == ids[0] && distinct[1] == ids[1])
        #expect(PaletteSections.distinct(ids) == distinct, "the same list gives the same ids")
    }

    @Test func aSectionWithNoRowsIsDropped() {
        let sections = PaletteSections.forCommands(picks: [.fixed(0), .item(1)], typed: true, commandCount: 1, recentCount: 2)
        #expect(sections.map(\.kind) == [.items, .commands])
        let none = PaletteSections.forCommands(picks: [], typed: true, commandCount: 4, recentCount: 2)
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

    @Test func searchWithNothingTypedListsTheRecentNotes() {
        let sections = PaletteSections.forSearch(rows: ["a", "b"], typed: false) { _ in true }
        #expect(sections.map(\.kind) == [.recent])
    }

    // MARK: Actions

    @Test func anItemOffersOpenNewWindowCopyLinkFavoritesVersionHistoryAndDelete() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(actions.map(\.kind) == [.open, .openInNewWindow, .copyLink, .addToFavorites, .versionHistory, .delete])
        #expect(actions.last?.isDestructive == true)
        #expect(actions.first { $0.kind == .delete }?.keys == ["⌘", "⌫"])
    }

    @Test func aFavoriteOffersRemoveFromFavoritesInstead() {
        let kinds = PaletteAction.forItem(isFile: false, isFavorite: true, isActive: true).map(\.kind)
        #expect(kinds.contains(.removeFromFavorites))
        #expect(!kinds.contains(.addToFavorites))
    }

    @Test func aFileHasNoLinkOrVersionHistoryAndAnItemInTheBinCannotBeDeletedOrFavored() {
        let file = PaletteAction.forItem(isFile: true, isFavorite: false, isActive: true).map(\.kind)
        #expect(file == [.open, .openInNewWindow, .addToFavorites, .delete])
        let binned = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: false).map(\.kind)
        #expect(binned == [.open, .openInNewWindow, .copyLink, .versionHistory])
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
        #expect(PaletteAction.reachable(.copyLink, among: file, filteredBy: "") == nil, "a file has no Copy Link")
        #expect(PaletteActionsPanel.shortcutKinds.allSatisfy { PaletteActionsPanel.shortcut(of: $0) != nil })
    }

    @Test func inSearchTheFirstActionReadsOpenAtMatch() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true, openTitle: "Open at Match")
        #expect(actions.first?.title == "Open at Match")
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
}
