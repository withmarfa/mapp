import AppKit
import Foundation
import Synchronization
import SwiftUI
import Testing
@testable import MarfaMac

@MainActor
@Suite(.serialized, .hangLimit)
struct CommandPaletteTests {
    // MARK: Actions

    @Test func anItemOffersOpenNewWindowBothLinksFavoritesVersionHistoryAndDelete() {
        let actions = PaletteAction.forItem(isFile: false, isFavorite: false, isActive: true)
        #expect(actions.map(\.kind) == [.open, .openInNewWindow, .copyLink, .copyWikiLink, .addToFavorites, .versionHistory, .delete])
        #expect(actions.last?.isDestructive == true)
        #expect(actions.first { $0.kind == .delete }?.keys == ["⌘", "⌫"])
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
}
