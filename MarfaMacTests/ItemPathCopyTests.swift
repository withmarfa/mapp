import AppKit
import Foundation
import Testing
@testable import MarfaMac

/// Copy File Path (⌥⌘C in the menu bar, the More menu, the row menu and the palette) calls
/// `ItemLibrary.copyFilePaths(of:)`, so what this copies is what each of them copies.
@Suite(.hangLimit) @MainActor
struct ItemPathCopyTests {
    private func privatePasteboard() -> NSPasteboard {
        NSPasteboard(name: NSPasteboard.Name("ItemPathCopyTests-\(UUID().uuidString)"))
    }

    private let picture = URL(fileURLWithPath: "/tmp/kept/Celadon.png")
    private let second = URL(fileURLWithPath: "/tmp/kept/Shino.png")

    @Test func aFileItemCopiesItsFilesPath() async {
        let library = FakeItemLibrary()
        let host = library.add("A note\n")
        let file = library.attachPicture(picture, to: host.id)
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyFilePaths(of: [file], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "/tmp/kept/Celadon.png")
        #expect(library.notices.told == 0)
    }

    @Test func severalFilesCopyOnePerLineInTheOrderGiven() async {
        let library = FakeItemLibrary()
        let host = library.add("A note\n")
        let first = library.attachPicture(picture, to: host.id)
        let next = library.attachPicture(second, to: host.id)
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyFilePaths(of: [next, first], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "/tmp/kept/Shino.png\n/tmp/kept/Celadon.png")
    }

    @Test func anItemWithNoFileIsLeftOutAndTold() async {
        let library = FakeItemLibrary()
        let note = library.add("A note\n")
        let file = library.attachPicture(picture, to: note.id)
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        await library.copyFilePaths(of: [note.id, file], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "/tmp/kept/Celadon.png")
        #expect(library.notices.waiting.map(\.title) == ["Some Paths Not Copied"])
    }

    @Test func onlyItemsWithNoFileLeaveThePasteboardAloneAndTell() async {
        let library = FakeItemLibrary()
        let note = library.add("A note\n")
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("kept", forType: .string)
        await library.copyFilePaths(of: [note.id], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "kept")
        #expect(library.notices.waiting.map(\.title) == ["Can’t Copy File Path"])
    }

    @Test func aFileThatCannotBeFetchedLeavesThePasteboardAloneAndSaysWhy() async {
        let library = FakeItemLibrary()
        let host = library.add("A note\n")
        let file = library.attachPicture(picture, to: host.id)
        library.fetchFails = true
        let pasteboard = privatePasteboard()
        defer { pasteboard.releaseGlobally() }
        pasteboard.setString("kept", forType: .string)
        await library.copyFilePaths(of: [file], to: pasteboard)
        #expect(pasteboard.string(forType: .string) == "kept")
        #expect(library.notices.waiting.first?.message == "The server can’t be reached.")
    }

    @Test func theCommandAppliesOnlyWhereAChosenItemIsAFile() {
        let library = FakeItemLibrary()
        let note = library.add("A note\n")
        let file = library.attachPicture(picture, to: note.id)
        func applies(_ ids: Set<ItemID>) -> Bool {
            ItemCommand.copyFilePath.isEnabled(in: ItemCommandContext(library: library, ids: ids, hasBrowser: true, pageItem: nil))
        }
        #expect(applies([file]))
        #expect(applies([note.id, file]))
        #expect(!applies([note.id]))
        #expect(!applies([]))
        #expect(RowMenuEntry.entries(opening: .modal, inBin: false).contains(.copyFilePath))
        #expect(library.holdsFile(among: [file]) && !library.holdsFile(among: [note.id]))
    }
}
