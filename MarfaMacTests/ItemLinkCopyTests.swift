import AppKit
import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// A server that answers each item's link as a test sets it; an item it has none for throws, as a refused read does.
nonisolated final class FakeItemLinks: ItemLinkSource {
    struct Refused: Error {}

    let answers = Mutex<[ItemID: URL]>([:])
    let asked = Mutex<[ItemID]>([])

    func webLink(of id: ItemID) async throws -> URL {
        asked.withLock { $0.append(id) }
        guard let url = answers.withLock({ $0[id] }) else { throw Refused() }
        return url
    }
}

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

    private func openLibrary(links: FakeItemLinks?) async throws -> (MarfaLibrary, MarfaMac.Item) {
        let source = FakeItemSource()
        source.heldInstanceID.withLock { $0 = instance }
        let library = MarfaLibrary(source: source, notices: Notices(), links: links)
        let note = FakeItemLibrary.note("A note\n", modified: Date(timeIntervalSinceReferenceDate: 800_000_000))
        source.send(.loaded(SourceSnapshot(items: [note], catalogue: FakeItemLibrary.testCatalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, note)
    }

    @Test func aMarfaLibraryCopiesTheHttpsLinkTheServerGives() async throws {
        let links = FakeItemLinks()
        let (library, note) = try await openLibrary(links: links)
        let web = try #require(URL(string: "https://marfa.example/i/\(note.id.rawValue)"))
        links.answers.withLock { $0[note.id] = web }
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyLink(of: note.id, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == web.absoluteString)
        #expect(pasteboard.string(forType: .URL) == web.absoluteString)
        #expect(library.notices.told == 0)
        #expect(links.asked.withLock { $0 } == [note.id])
    }

    @Test func aMarfaLibraryCopiesTheAppLinkWhereTheServerRefusesTheRead() async throws {
        let links = FakeItemLinks()
        let (library, note) = try await openLibrary(links: links)
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyLink(of: note.id, to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "marfa://\(instance)/\(note.id.rawValue)")
        #expect(pasteboard.string(forType: .URL) == "marfa://\(instance)/\(note.id.rawValue)")
        #expect(library.notices.told == 0)
        #expect(links.asked.withLock { $0 } == [note.id])
    }

    @Test func aLibraryWithNoServerToAskCopiesTheAppLink() async throws {
        let (library, note) = try await openLibrary(links: nil)
        let link = try #require(await library.itemLink(note.id))
        #expect(link.text == "marfa://\(instance)/\(note.id.rawValue)")
    }
}
