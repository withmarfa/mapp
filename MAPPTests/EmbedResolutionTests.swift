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

    @Test func anEmbedShowsTheFileItWasBoundToByTheNameMarfaReads() async throws {
        library.bindEmbed("Photo 1.png", in: note, file: try file("kept", Data("png".utf8)))
        library.bindEmbed("Gone.png", in: note)

        let byPath = await library.openEmbeddedFile(.path("Photo%201.png?size=2#top"), in: note).file
        #expect(byPath?.length == 3)
        #expect(await library.openEmbeddedFile(.name(" Photo 1.png |300"), in: note).file?.length == 3)
        #expect(await library.openEmbeddedFile(.name("Gone.png"), in: note).file == nil)
        #expect(reason(await library.openEmbeddedFile(.name("Gone.png"), in: note)) == nil, "a name bound to nothing is missing")
        #expect(EmbedReference.path("a%2x%41").name == "a%2xA", "an escape that is not one stays as typed")
    }

    @Test func anEmbedNotYetBoundIsWaitedOnThenShown() async throws {
        let url = try file("kept", Data("png".utf8))
        let opening = Task { await library.openEmbeddedFile(.name("Pasted.png"), in: note, waiting: .seconds(5)) }
        try await Task.sleep(for: .milliseconds(200))
        library.bindEmbed("Pasted.png", in: note, file: url)
        #expect(await opening.value.file?.length == 3)

        library.bindEmbed("Later.png", in: note, resolution: .pending)
        #expect(reason(await library.openEmbeddedFile(.name("Later.png"), in: note, waiting: .milliseconds(200))) != nil)
    }

    @Test func aFileThatCanNotBeShownSaysWhy() async throws {
        library.bindEmbed("Photo.png", in: note, file: try file("kept", Data("png".utf8)))
        library.bindEmbed("Twin.png", in: note, resolution: .ambiguous([]))
        library.fetchFails = true

        #expect(reason(await library.openEmbeddedFile(.name("Photo.png"), in: note)) == "The server can’t be reached.")
        #expect(reason(await library.openEmbeddedFile(.name("Twin.png"), in: note)) == "More than one file has this name.")
    }

    @Test func aNotesPictureIsItsFirstEmbeddedImage() async throws {
        library.bindEmbed("Budget.csv", in: note, file: try file("Budget.csv", Data("a,b\n".utf8)))
        library.bindEmbed("Photo.png", in: note, file: try file("Photo.png", EmbedFixtures.png(width: 5, height: 2)))
        let item = try #require(library.item(note))

        #expect(await GalleryPreview.image(for: item, in: library)?.width == 5)
    }
}
