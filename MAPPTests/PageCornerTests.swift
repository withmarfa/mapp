import SwiftUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// The corner of an item's page: which buttons each kind of page gets, and how Focus and the formats card follow the
/// item they were chosen on.
@MainActor
struct PageCornerTests {
    // MARK: Which buttons

    @Test func aNoteHasFormatsThenFocus() {
        #expect(PageCorner.buttons(layout: .text, hasReader: false) == [.formats, .focus])
    }

    @Test func aWebPageWithAReaderViewHasTheSwitchThenFocus() {
        let layout = ItemPageLayout.webPage(document: .mint(), runsScripts: false)
        #expect(PageCorner.buttons(layout: layout, hasReader: true) == [.look, .focus])
    }

    @Test func aWebPageWithoutAReaderViewHasFocusAlone() {
        let layout = ItemPageLayout.webPage(document: .mint(), runsScripts: true)
        #expect(PageCorner.buttons(layout: layout, hasReader: false) == [.focus])
    }

    @Test func aFileHasFocusAloneWhateverTheReaderSays() {
        #expect(PageCorner.buttons(layout: .file, hasReader: false) == [.focus])
        #expect(PageCorner.buttons(layout: .file, hasReader: true) == [.focus])
    }

    @Test func theCardKeepsInsideANarrowColumnButNeverShrinksPastUse() {
        #expect(PageCorner.cardWidth(forContentWidth: 900, inset: 16) == PageCorner.cardWidth)
        #expect(PageCorner.cardWidth(forContentWidth: 300, inset: 16) == 268)
        #expect(PageCorner.cardWidth(forContentWidth: 100, inset: 16) == PageCorner.narrowestCard)
    }

    // MARK: Focus

    @Test func focusTurnsOnAndOffForTheItemItWasChosenOn() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        details.toggleFocus(on: item)
        #expect(details.isFocused(on: item))
        details.toggleFocus(on: item)
        #expect(!details.isFocused(on: item))
    }

    @Test func aNewItemStartsOutOfFocus() {
        let details = DetailsPresentation()
        let first = ItemID.mint()
        let second = ItemID.mint()
        details.pageShows(first)
        details.toggleFocus(on: first)
        details.pageShows(second)
        #expect(!details.isFocused(on: first))
        #expect(!details.isFocused(on: second))
    }

    @Test func showingTheSameItemAgainKeepsFocus() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        details.toggleFocus(on: item)
        details.pageShows(item)
        #expect(details.isFocused(on: item))
    }

    @Test func anItemThatGoesTakesItsFocusButNotTheNextItems() {
        let details = DetailsPresentation()
        let gone = ItemID.mint()
        let next = ItemID.mint()
        details.toggleFocus(on: gone)
        details.pageLeft(gone)
        #expect(!details.isFocused(on: gone))

        details.toggleFocus(on: next)
        details.pageLeft(gone)
        #expect(details.isFocused(on: next), "a page going away is told after the next has arrived")
    }

    @Test func customizingTheLayoutEndsFocusAndRefusesIt() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        details.toggleFocus(on: item)
        details.toggleFormats(on: item)
        details.beginLayout()
        #expect(!details.isFocused(on: item))
        #expect(!details.isFormatsOpen(on: item))
        details.toggleFocus(on: item)
        #expect(!details.isFocused(on: item))
    }

    // MARK: Escape

    @Test func escapeClosesTheCardBeforeLeavingFocus() {
        let details = DetailsPresentation()
        let item = ItemID.mint()
        details.toggleFocus(on: item)
        details.toggleFormats(on: item)

        #expect(details.escapeFromPage())
        #expect(!details.isFormatsOpen(on: item))
        #expect(details.isFocused(on: item), "the first Escape leaves Focus alone")

        #expect(details.escapeFromPage())
        #expect(!details.isFocused(on: item))

        #expect(!details.escapeFromPage(), "with neither showing the key is the caller's")
    }

    @Test func theCardBelongsToOneItem() {
        let details = DetailsPresentation()
        let first = ItemID.mint()
        let second = ItemID.mint()
        details.toggleFormats(on: first)
        #expect(!details.isFormatsOpen(on: second))
        details.pageShows(second)
        #expect(!details.isFormatsOpen(on: first))
    }

    // MARK: Commands

    private let library = FakeItemLibrary()

    private func context(_ item: Item, details: DetailsPresentation?, editable: Bool = true) -> ItemCommandContext {
        ItemCommandContext(
            library: library, ids: [item.id], hasBrowser: true, pageItem: item.id, pageIsEditable: editable, details: details)
    }

    @Test func focusAndFormatsAreCommandsOfThePageShowing() {
        let note = library.add("A note\n")
        let details = DetailsPresentation()
        let command = context(note, details: details)
        #expect(ItemCommand.toggleFocus.isEnabled(in: command))
        #expect(ItemCommand.toggleFormats.isEnabled(in: command))

        ItemCommand.toggleFocus.perform(in: command, editor: nil, openWindow: { _ in })
        #expect(details.isFocused(on: note.id))
        #expect(String(localized: ItemCommand.toggleFocus.title(in: command)) == "Leave Focus")

        ItemCommand.toggleFormats.perform(in: command, editor: nil, openWindow: { _ in })
        #expect(details.isFormatsOpen(on: note.id))
    }

    @Test func noPageMeansNoFocusOrFormats() {
        let note = library.add("A note\n")
        let hidden = ItemCommandContext(
            library: library, ids: [note.id], hasBrowser: true, pageItem: nil, showsPage: false, details: DetailsPresentation())
        #expect(!ItemCommand.toggleFocus.isEnabled(in: hidden))
        #expect(!ItemCommand.toggleFormats.isEnabled(in: hidden))
    }

    @Test func focusIsOfferedForAFileButFormatsAreNot() {
        let id = ItemID.mint()
        library.items.append(Item(
            id: id, type: TypeID("core.file"), title: "Report.pdf", titleRule: .property("title"), content: .file(.pdf, byteCount: 10),
            version: ItemVersion(1), created: .now, modified: .now))
        let file = library.item(id)!
        let command = context(file, details: DetailsPresentation())
        #expect(ItemCommand.toggleFocus.isEnabled(in: command))
        #expect(!ItemCommand.toggleFormats.isEnabled(in: command))
    }

    @Test func focusWaitsWhileTheLayoutIsBeingArranged() {
        let note = library.add("A note\n")
        let details = DetailsPresentation()
        details.beginLayout()
        #expect(!ItemCommand.toggleFocus.isEnabled(in: context(note, details: details)))
    }

    // MARK: The page

    @Test func focusHidesOnlyTheTitleAndPropertiesOfTheHeaderTheEditorShows() throws {
        let note = library.add("A note\n")
        let details = DetailsPresentation()
        let plain = try #require(ItemPageHeader.header(of: note.id, in: library, drafts: details))
        #expect(!plain.focused)
        details.toggleFocus(on: note.id)
        let focused = try #require(ItemPageHeader.header(of: note.id, in: library, drafts: details))
        #expect(focused.focused)
        #expect(!focused.hidden, "the footer and the kind are the deleted item's switch, not Focus's")
        #expect(focused.kind == plain.kind)
    }

    @Test func focusNamesTheTitleInTheToolbarFromTheStart() {
        let note = library.add("A note\n")
        let details = DetailsPresentation()
        let tools = { ItemToolbarActions(library: self.library, browser: nil, items: [note], editor: nil, details: details) }
        #expect(!tools().isFocused)
        #expect(tools().scrolledTitle.isEmpty)
        details.toggleFocus(on: note.id)
        #expect(tools().isFocused)
        #expect(tools().hasHeaderAway)
        #expect(tools().scrolledTitle == note.title)
    }

    @Test func focusPutsTheTypeUnderTheTitleInTheToolbar() {
        let note = library.add("A note\n")
        let details = DetailsPresentation()
        let tools = { ItemToolbarActions(library: self.library, browser: nil, items: [note], editor: nil, details: details) }
        #expect(tools().scrolledSubtitle == nil)
        details.toggleFocus(on: note.id)
        #expect(tools().scrolledSubtitle == library.catalogue.label(for: note.type))
    }

    @Test func aPdfInFocusNamesItsPagesOnceTheyAreCounted() {
        let id = ItemID.mint()
        library.items.append(Item(
            id: id, type: TypeID("core.file"), title: "Quote.pdf", titleRule: .property("title"), content: .file(.pdf, byteCount: 10),
            version: ItemVersion(1), created: .now, modified: .now))
        let file = library.item(id)!
        let details = DetailsPresentation()
        let tools = { ItemToolbarActions(library: self.library, browser: nil, items: [file], editor: nil, details: details) }
        details.toggleFocus(on: id)
        #expect(tools().scrolledSubtitle == library.catalogue.label(for: file.type), "until the preview has read the file")
        details.filePages(4, of: id)
        #expect(tools().scrolledSubtitle == "PDF, 4 pages")
        details.filePages(1, of: id)
        #expect(tools().scrolledSubtitle == "PDF, 1 page")
        details.pageShows(ItemID.mint())
        #expect(details.pages(of: id) == nil, "another item's page never inherits the count")
    }
}
