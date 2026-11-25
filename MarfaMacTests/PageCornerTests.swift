import SwiftUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// The corner of an item's page: which buttons each kind of page gets, and how Focus and the formats bar follow the
/// item they were chosen on.
@MainActor
struct PageCornerTests {
    // MARK: Which buttons

    @Test func aPageThatCannotBeWrittenHasNoFormats() {
        #expect(PageCorner.buttons(PageCornerKind(layout: .text, canWrite: false)) == [.textSize, .focus])
    }

    @Test func theCornerChoicesAreMacSettings() {
        for key in [PageKey.cornerShowsFormats, PageKey.cornerShowsTextSize, PageKey.cornerShowsFocus] {
            #expect(MacSettings.keys.contains(key))
        }
    }

    // MARK: Commands

    private let library = FakeItemLibrary()

    private func context(_ item: Item, details: DetailsPresentation?, editable: Bool = true) -> ItemCommandContext {
        ItemCommandContext(
            library: library, ids: [item.id], hasBrowser: true, pageItem: item.id, pageIsEditable: editable, details: details)
    }

    @Test func formatsAreOfferedOnlyWhereThePageCanBeWritten() {
        let note = library.add("A note\n")
        #expect(ItemCommand.toggleFormats.isEnabled(in: context(note, details: DetailsPresentation(), editable: true)))
        #expect(!ItemCommand.toggleFormats.isEnabled(in: context(note, details: DetailsPresentation(), editable: false)))
    }
}
