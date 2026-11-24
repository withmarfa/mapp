import CoreGraphics
import Foundation
import Testing
@testable import MarfaMac

/// How an embed in an item becomes the file Marfa's core bound it to, for the page and the gallery alike.
@Suite(.hangLimit) struct EmbedResolutionTests {
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
        let checked = library.unreadChecks
        let opening = Task { await open("![[Pasted.png]]", waiting: .seconds(5)) }
        // The embed is not in the text yet when the task asks, which is what makes it wait.
        #expect(await eventually { library.unreadChecks > checked })
        library.bindEmbed("![[Pasted.png]]", in: note, file: url)
        #expect(await opening.value.file?.length == 3, "an embed not yet in the text the copy read is waited on")

        library.bindEmbed("![[Gone.png]]", in: note, bound: false)
        library.unreadSaves = [note]
        let asked = library.unreadChecks
        let saving = Task { await open("![[Gone.png]]", waiting: .seconds(5)) }
        #expect(await eventually { library.unreadChecks > asked })
        library.bindEmbed("![[Gone.png]]", in: note, file: url)
        #expect(await saving.value.file?.length == 3, "a save the copy has not read yet is waited on")
        library.unreadSaves = []

        library.bindEmbed("![[Dr. Smith]]", in: note, bound: false)
        // An embed the read text holds but Marfa did not bind is no file and is not waited on. The wait is far longer than
        // a test lasts, so one that waited would hang here and fail at the suite's limit, without a clock to bound.
        #expect(await open("![[Dr. Smith]]", waiting: .seconds(3_600)).file == nil)
    }

    @Test func aBinnedFileIsMissingAndARenamedOneIsStillTheFileTheEmbedIsBoundTo() async throws {
        let id = try #require(library.bindEmbed("![[Photo.png]]", in: note, file: try file("kept", Data("png".utf8))))
        #expect(await open("![[Photo.png]]").file?.length == 3)

        let index = try #require(library.items.firstIndex { $0.id == id })
        library.items[index].title = "Beach.png"
        #expect(await open("![[Photo.png]]").file?.length == 3, "the binding follows the file, not its name")

        library.items[index].state = .trashed
        #expect(await open("![[Photo.png]]").file == nil)
        #expect(reason(await open("![[Photo.png]]")) == nil, "an embed of a binned file is missing, as a link to a binned item is")
    }
}
