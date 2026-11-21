import SwiftUI
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

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

    @Test func nothingSelectedEnablesNothing() {
        #expect(enabled(context([])).isEmpty)
    }

    @Test func anItemOnThePageEnablesThePageCommands() {
        let note = library.add("A note\n")
        #expect(enabled(context([note.id], page: note.id)) == [.open, .openAsModal, .openAsFullPage, .quickLook, .openInNewWindow, .addAttachment, .toggleSource, .print, .exportPDF])
    }

    @Test func aSelectedItemNotOnThePageEnablesOnlyOpeningInAWindow() {
        let note = library.add("A note\n")
        #expect(enabled(context([note.id])) == [.open, .openAsModal, .openAsFullPage, .quickLook, .openInNewWindow])
        #expect(enabled(context([note.id], page: .mint())) == [.open, .openAsModal, .openAsFullPage, .quickLook, .openInNewWindow])
    }

    @Test func aPageThatIsNotReadyIsNotThere() {
        #expect(ItemCommandContext.pageItem(showsPage: true, editorHasItem: false, pageItemID: .mint()) == nil)
    }

    @Test func aFileHasNoPageCommands() {
        let id = ItemID.mint()
        library.items.append(Item(
            id: id, type: TypeID("core.file"), title: "Report.pdf", titleRule: .property("title"), content: .file(.pdf, byteCount: 10),
            version: ItemVersion(1), created: .now, modified: .now))
        #expect(enabled(context([id], page: id)) == [.open, .openAsModal, .openAsFullPage, .quickLook, .openInNewWindow])
    }

    @Test func severalItemsHaveNoSinglePage() {
        let one = library.add("One\n")
        let two = library.add("Two\n")
        #expect(enabled(context([one.id, two.id], page: one.id)) == [.quickLook, .openInNewWindow])
    }

    @Test func aReadOnlyPageCannotTakeAnAttachment() {
        let note = library.add("A note\n")
        let enabled = enabled(context([note.id], page: note.id, editable: false))
        #expect(!enabled.contains(.addAttachment))
        #expect(enabled.contains(.print))
    }

    @Test func anItemWindowOpensNoMoreWindows() {
        let note = library.add("A note\n")
        #expect(!ItemCommand.openInNewWindow.isEnabled(in: context([note.id], page: note.id, hasBrowser: false)))
    }

    @Test func noLibraryEnablesNothing() {
        let note = ItemID.mint()
        let none = ItemCommandContext(library: nil, ids: [note], hasBrowser: true, pageItem: note)
        #expect(enabled(none).isEmpty)
    }

    @Test func eachShortcutBelongsToOneCommand() {
        let shortcuts = ItemCommand.allCases.compactMap { $0.shortcutCommand.defaultShortcut }
        #expect(Set(shortcuts).count == shortcuts.count)
    }

    /// A page's switch is what the command acts on, and a page going away takes only its own.
    @Test func theReaderCommandFollowsThePagesSwitch() {
        let (first, second) = (ItemID.mint(), ItemID.mint())
        let details = DetailsPresentation()
        var chosen: SourceViewMode?
        details.offerPageLook(PageLookSwitch(item: second, mode: .reader) { chosen = $0 }, for: second)
        details.offerPageLook(nil, for: first)
        let context = ItemCommandContext(library: nil, ids: [second], browser: nil, editor: nil, details: details)
        #expect(context.pageLook?.item == second)

        let reading = ItemCommandContext(library: library, ids: [second], hasBrowser: true, pageItem: nil, pageLook: details.pageLook)
        ItemCommand.toggleReader.perform(in: reading, editor: nil, openWindow: { _ in })
        #expect(chosen == .original)

        details.offerPageLook(nil, for: second)
        let none = ItemCommandContext(library: library, ids: [second], browser: nil, editor: nil, details: details)
        #expect(!ItemCommand.toggleReader.isEnabled(in: none))
    }
}
