import AppKit
import Testing
@testable import MarfaMac

/// Every Copy Link (the row menus, the More menu, the menu bar and the palette) calls `ItemLibrary.copyLink(of:)`, so
/// what this copies is what each of them copies.
@Suite(.hangLimit) @MainActor
struct ItemLinkCopyTests {
    private let instance = "3f2504e0-4f89-41d3-9a0c-0305e82c3301"

    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ItemLinkCopyTests-\(UUID().uuidString)"))
    }

    @Test func copyLinkPutsTheItemsLinkOnThePasteboardAsAStringAndAURL() async throws {
        let library = FakeItemLibrary()
        library.heldInstanceID = instance
        let note = library.add("A note\n")
        let link = try #require(await library.itemLink(note.id))
        #expect(link.text == "marfa://\(instance)/\(note.id.rawValue)")
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyLink(of: note.id, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == link.text)
        #expect(pasteboard.string(forType: .URL) == link.text)
        #expect(library.notices.told == 0)
    }

    @Test func aCopyThatDoesNotKnowItsInstanceYetTellsThePersonAndLeavesThePasteboardAlone() async {
        let library = FakeItemLibrary()
        let note = library.add("A note\n")
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("kept", forType: .string)
        await library.copyLink(of: note.id, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "kept")
        #expect(library.notices.waiting.map(\.title) == ["Can’t Copy Link"])
    }
}
