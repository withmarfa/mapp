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

    @Test func aNoteOnThePageEnablesThePageCommands() {
        let note = library.add("A note\n")
        #expect(enabled(context([note.id], page: note.id)) == [.openInNewWindow, .addAttachment, .toggleSource, .print, .exportPDF])
    }

    @Test func aSelectedNoteNotOnThePageEnablesOnlyOpeningInAWindow() {
        let note = library.add("A note\n")
        #expect(enabled(context([note.id])) == [.openInNewWindow])
        #expect(enabled(context([note.id], page: .mint())) == [.openInNewWindow])
    }

    @Test func settingsShowingLeavesNoPageForTheCommandsToAct() {
        let note = library.add("A note\n")
        let browser = Browser()
        browser.showSettings()
        let page = ItemCommandContext.pageItem(showsPage: browser.showsPage, editorHasNote: true, noteID: note.id)
        #expect(page == nil)
        #expect(enabled(context([note.id], page: page)) == [.openInNewWindow])

        browser.leaveSettings()
        let back = ItemCommandContext.pageItem(showsPage: browser.showsPage, editorHasNote: true, noteID: note.id)
        #expect(back == note.id)
    }

    @Test func aPageThatIsNotReadyIsNotThere() {
        #expect(ItemCommandContext.pageItem(showsPage: true, editorHasNote: false, noteID: .mint()) == nil)
    }

    @Test func aFileHasNoPageCommands() {
        let id = ItemID.mint()
        library.items.append(Item(
            id: id, type: TypeID("core.file"), title: "Report.pdf", titleRule: .property("title"), content: .file(.pdf, byteCount: 10),
            version: ItemVersion(1), created: .now, modified: .now))
        #expect(enabled(context([id], page: id)) == [.openInNewWindow])
    }

    @Test func severalNotesHaveNoSinglePage() {
        let one = library.add("One\n")
        let two = library.add("Two\n")
        #expect(enabled(context([one.id, two.id], page: one.id)) == [.openInNewWindow])
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
        let shortcuts = ItemCommand.allCases.compactMap(\.shortcut).map { "\($0.key.character)\($0.modifiers.rawValue)" }
        #expect(Set(shortcuts).count == shortcuts.count)
    }
}
