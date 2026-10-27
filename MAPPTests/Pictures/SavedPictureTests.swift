import Foundation
import Testing
@testable import MAPP

/// Which files attached to an item count as the picture at a web address: the match is on the `attached-to` edge and
/// `source_url` alone, never on a type, and an address matches only if it names the same picture.
@MainActor struct SavedPictureTests {
    private let folder: TemporaryFolder
    private let library = FakeItemLibrary()

    init() throws {
        folder = try TemporaryFolder()
    }

    private func picture(named name: String = "pic.png") throws -> URL {
        let directory = folder.url.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appending(path: name)
        try SamplePicture.png().write(to: file)
        return file
    }

    private func newNote() -> ItemID { library.add("A note\n").id }

    private func trash(_ id: ItemID) throws {
        library.items[try #require(library.items.firstIndex { $0.id == id })].state = .trashed
    }

    private func address(_ text: String) -> URL { URL(string: text)! }

    // MARK: The address

    @Test(arguments: [
        ("https://example.com/a.png", "https://example.com/a.png", true),
        ("https://example.com/a.png", "https://EXAMPLE.com/a.png", true),
        ("https://example.com/a.png", "HTTPS://example.com/a.png", true),
        ("https://example.com/a.png", "https://example.com:443/a.png", true),
        ("http://example.com/a.png", "http://example.com:80/a.png", true),
        ("https://example.com/a.png?w=1", "https://example.com/a.png?w=1#top", true),
        ("https://example.com", "https://example.com/", true),
        ("https://example.com/a/", "https://example.com/a", false),
        ("https://example.com/a.png", "https://example.com/a.png?w=1", false),
        ("https://example.com/a.png?w=1", "https://example.com/a.png?w=2", false),
        ("https://example.com/a.png", "https://example.com/a.png.bak", false),
        ("https://example.com/a", "https://example.com/a/b", false),
        ("https://example.com/A.png", "https://example.com/a.png", false),
        ("https://example.com/a.png", "http://example.com/a.png", false),
        ("https://example.com/a.png", "https://example.com:8443/a.png", false),
        ("https://example.com/a.png", "https://www.example.com/a.png", false),
        ("https://example.com/a.png", "https://user@example.com/a.png", false),
        ("https://example.com/a.png", "mailto:someone@example.com", false),
    ])
    func twoAddressesAreTheSamePictureOnlyIfTheyNameTheSameOne(first: String, second: String, same: Bool) {
        #expect(SavedPictures.same(address(first), address(second)) == same)
        #expect(SavedPictures.same(address(second), address(first)) == same, "the match does not depend on which is asked")
    }

    // MARK: The lookup

    @Test func aFileAttachedToTheItemAndSavedFromTheAddressIsItsPicture() throws {
        let note = newNote()
        let file = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")) == [file])
    }

    @Test func aFileAttachedToAnotherItemIsNeverUsed() throws {
        let note = newNote()
        let other = newNote()
        library.attachPicture(try picture(), to: other, from: "https://example.com/a.png")

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")).isEmpty)
        #expect(library.savedPictures(of: other, at: address("https://example.com/a.png")).count == 1)
    }

    @Test func aFileInTheBinIsNotUsedButAnArchivedOneIs() throws {
        let note = newNote()
        let binned = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")
        let archived = library.attachPicture(try picture(), to: note, from: "https://example.com/b.png", state: .archived)

        try trash(binned)

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")).isEmpty)
        #expect(library.savedPictures(of: note, at: address("https://example.com/b.png")) == [archived])
    }

    @Test func aFileWithNoAddressOrAnAddressThatIsNotTextIsNotUsed() throws {
        let note = newNote()
        library.attachPicture(try picture(), to: note)
        let numbered = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")
        library.items[try #require(library.items.firstIndex { $0.id == numbered })].properties = [
            Property(key: SavedPictures.sourceField, value: .number(3))
        ]

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")).isEmpty)
        #expect(library.savedPictureStates(of: note).isEmpty)
    }

    @Test func aLinkOfAnotherTypeIsNoAttachment() throws {
        let note = newNote()
        let file = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")
        let index = try #require(library.items.firstIndex { $0.id == file })
        let edge = library.items[index].edgesOut[0]
        library.items[index].edgesOut = [
            Edge(id: edge.id, type: "references", source: edge.source, target: edge.target, origin: edge.origin)
        ]

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")).isEmpty)
    }

    @Test func nothingNamesATypeSoAnyFileWithTheEdgeAndAddressMatches() throws {
        let note = newNote()
        let file = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")
        library.items[try #require(library.items.firstIndex { $0.id == file })].type = TypeID("rss.picture")

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")) == [file])
    }

    @Test func twoFilesFromOneAddressAreTriedOldestFirstWithTheirIdsBreakingATie() throws {
        let note = newNote()
        let moment = Date(timeIntervalSince1970: 1_000_000)
        let newer = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png", created: moment + 60)
        let older = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png", created: moment)
        let tied = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png", created: moment)
        let tiedOrder = [older, tied].sorted { $0.rawValue < $1.rawValue }

        #expect(library.savedPictures(of: note, at: address("https://example.com/a.png")) == tiedOrder + [newer])
    }

    // MARK: What the page depends on

    @Test func theStatesChangeWhenAFileComesIsBinnedOrChanges() throws {
        let note = newNote()
        #expect(library.savedPictureStates(of: note).isEmpty)

        let file = library.attachPicture(try picture(), to: note, from: "https://example.com/a.png")
        let arrived = library.savedPictureStates(of: note)
        #expect(arrived == [SavedPictureState(file: file, address: "https://example.com/a.png", trashed: false, version: ItemVersion(1))])

        try trash(file)
        let binned = library.savedPictureStates(of: note)
        #expect(binned != arrived)
        #expect(binned.first?.trashed == true, "a binned file is still listed, so the page hears it go")

        let index = try #require(library.items.firstIndex { $0.id == file })
        library.items[index].version = ItemVersion(2)
        #expect(library.savedPictureStates(of: note) != binned)
    }

    @Test func aFileAttachedToAnotherItemChangesNothingForThisOne() throws {
        let note = newNote()
        let before = library.savedPictureStates(of: note)

        library.attachPicture(try picture(), to: newNote(), from: "https://example.com/a.png")

        #expect(library.savedPictureStates(of: note) == before)
    }

    // MARK: The URL

    @Test func aSavedPictureUrlNamesItsItemAndAddressAndAnOrdinaryOneNamesNoItem() throws {
        let item = ItemID.mint()
        let saved = URL(string: "http://example.com/a b.png?x=1&y=2")!
        let url = EmbeddedFiles.pictureURL(for: saved, version: 2, savedIn: item, stamp: "abc")

        let named = try #require(EmbeddedFiles.savedPicture(in: url))
        #expect(named.item == item)
        #expect(named.address == saved)
        #expect(EmbeddedFiles.savedPicture(in: EmbeddedFiles.pictureURL(for: saved, version: 2)) == nil)
        #expect(EmbeddedFiles.savedPicture(in: URL(string: "https://example.com/?item=x&address=https://a.com/b")!) == nil)
        #expect(EmbeddedFiles.pictureAddress(in: EmbeddedFiles.pictureURL(for: URL(string: "https://example.com/a.png")!, version: 1)) != nil)
    }

    @Test func theUrlChangesWhenTheBytesBehindItDo() {
        let item = ItemID.mint()
        let address = URL(string: "https://example.com/a.png")!

        #expect(
            EmbeddedFiles.pictureURL(for: address, version: 1, savedIn: item, stamp: "one")
                != EmbeddedFiles.pictureURL(for: address, version: 1, savedIn: item, stamp: "two"))
    }
}
