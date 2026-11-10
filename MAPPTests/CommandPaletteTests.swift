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
        for title in ["Heading 4", "Heading 5", "Heading 6", "Highlight", "Link…"] {
            #expect(labels(of: host).contains { $0.hasPrefix(title) }, "\(title) is offered with the other formats")
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
