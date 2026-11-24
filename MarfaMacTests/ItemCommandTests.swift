import SwiftUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// The toolbar's More menu and the menu bar build their buttons from `ItemCommand`, so the same context gives the same
/// answer in both. These cover when each command applies.
@MainActor
struct ItemCommandTests {
    private let library = FakeItemLibrary()

    private func context(
        _ ids: Set<ItemID>, page: ItemID? = nil, hasBrowser: Bool = true, editable: Bool = true
    ) -> ItemCommandContext {
        ItemCommandContext(library: library, ids: ids, hasBrowser: hasBrowser, pageItem: page, pageIsEditable: editable)
    }

    private func enabled(_ context: ItemCommandContext) -> Set<ItemCommand> {
        Set(ItemCommand.allCases.filter { $0.isEnabled(in: context) })
    }

    @Test func aPageThatIsNotReadyIsNotThere() {
        #expect(ItemCommandContext.pageItem(showsPage: true, editorHasItem: false, pageItemID: .mint()) == nil)
    }

    @Test func aReadOnlyPageCannotTakeAnAttachment() {
        let note = library.add("A note\n")
        let enabled = enabled(context([note.id], page: note.id, editable: false))
        #expect(!enabled.contains(.addAttachment))
        #expect(enabled.contains(.print))
    }

    @Test func noLibraryEnablesNothing() {
        let note = ItemID.mint()
        let none = ItemCommandContext(library: nil, ids: [note], hasBrowser: true, pageItem: note)
        #expect(enabled(none).isEmpty)
    }
}
