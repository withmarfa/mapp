import CoreGraphics
import Foundation
import Testing
@testable import MAPP

/// How an embed in a note becomes the file Marfa's core bound it to, for the page and the gallery alike.
@Suite struct EmbedResolutionTests {
    let folder: TemporaryFolder
    let library = FakeItemLibrary()
    let note: ItemID

    init() throws {
        folder = try TemporaryFolder()
        note = library.add("A note\n").id
    }

    func file(_ name: String, _ data: Data) throws -> URL {
        let url = folder.url.appending(path: name)
        try data.write(to: url)
        return url
    }

    func reason(_ resolution: EmbedResolution) -> String? {
        if case .unavailable(let reason) = resolution { reason } else { nil }
    }

    func open(_ text: String, waiting: Duration = .zero) async -> EmbedResolution {
        await library.openEmbeddedFile(EmbedReference(text: text), in: note, waiting: waiting)
    }

    @Test func anEmbedShowsTheFileBoundToItsTextAsWritten() async throws {
        library.bindEmbed(#"![](a\_b.png)"#, in: note, file: try file("kept", Data("png".utf8)))
        library.bindEmbed("![[Gone.png]]", in: note)

        #expect(await open(#"![](a\_b.png)"#).file?.length == 3)
        #expect(await open("![](a_b.png)").file == nil, "another embed of a similar name is not this one")
        #expect(await open("![[a\\_b.png]]").file == nil, "an embed of another kind is not this one")
        #expect(await open("![[Gone.png]]").file == nil)
        #expect(reason(await open("![[Gone.png]]")) == nil, "an embed bound to nothing is missing")
    }

    @Test func anEmbedIsWaitedOnOnlyWhileItsTextIsNotYetRead() async throws {
        let url = try file("kept", Data("png".utf8))
        let opening = Task { await open("![[Pasted.png]]", waiting: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(200))
        library.bindEmbed("![[Pasted.png]]", in: note, file: url)
        #expect(await opening.value.file?.length == 3, "an embed not yet in the text the copy read is waited on")

        library.bindEmbed("![[Gone.png]]", in: note, bound: false)
        library.unreadSaves = [note]
        let saving = Task { await open("![[Gone.png]]", waiting: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(200))
        library.bindEmbed("![[Gone.png]]", in: note, file: url)
        #expect(await saving.value.file?.length == 3, "a save the copy has not read yet is waited on")
        library.unreadSaves = []

        library.bindEmbed("![[Dr. Smith]]", in: note, bound: false)
        let started = ContinuousClock.now
        #expect(await open("![[Dr. Smith]]", waiting: .seconds(5)).file == nil)
        #expect(ContinuousClock.now - started < .seconds(1), "an embed the read text holds but Marfa did not bind is no file")
    }

    @Test func aFileThatCanNotBeShownSaysWhy() async throws {
        library.bindEmbed("![[Photo.png]]", in: note, file: try file("kept", Data("png".utf8)))
        library.bindEmbed("![[Twin.png]]", in: note, resolution: .ambiguous([]))
        library.bindEmbed("![[Later.png]]", in: note, resolution: .pending)
        library.fetchFails = true

        #expect(reason(await open("![[Photo.png]]")) == "The server can’t be reached.")
        #expect(reason(await open("![[Twin.png]]")) == "More than one file has this name.")
        #expect(reason(await open("![[Later.png]]")) != nil)
    }

    @Test func aNotesPictureIsItsFirstEmbeddedImageReadThroughTheResolver() async throws {
        library.bindEmbed("![[Budget.csv]]", in: note, file: try file("Budget.csv", Data("a,b\n".utf8)))
        library.bindEmbed("![[Photo.png]]", in: note, file: try file("Photo.png", EmbedFixtures.png(width: 5, height: 2)))
        let item = try #require(library.item(note))

        func picture() async -> String {
            switch await GalleryPreview.image(for: item, in: library) {
            case .image(let image): "\(image.width)"
            case .none: "none"
            case .failed: "failed"
            }
        }
        #expect(await picture() == "5")

        library.fetchFails = true
        #expect(await picture() == "failed", "a picture that could not be had now is not taken for none")
    }

    @Test func aPictureThatFailedIsTriedAgain() async throws {
        library.bindEmbed("![[Photo.png]]", in: note, file: try file("Photo.png", EmbedFixtures.png(width: 5, height: 2)))
        let item = try #require(library.item(note))
        library.fetchFails = true
        #expect(await GalleryArtworkCache.artwork(for: item, width: 200, scale: 2, in: library) == nil)

        library.fetchFails = false
        #expect(await GalleryArtworkCache.artwork(for: item, width: 200, scale: 2, in: library)?.image.width == 5)
    }
}
