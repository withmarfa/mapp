import Foundation
import Testing
@testable import MarfaMac

/// A title typed on a page with no editor, as a file's, is saved or handed back as a text page's title is.
@MainActor
@Suite(.hangLimit) struct TitleDraftTests {
    typealias F = LibraryFixture

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in F.texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(F.snapshot))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func flushAll() async -> Bool {
        await withCheckedContinuation { continuation in EditorController.flushAll { continuation.resume(returning: $0) } }
    }

    /// A title typed before another Mac's rename reached this one is sent on the version the person saw, so the server
    /// merges it against that rename rather than writing over it.
    @Test func aTitleTypedBeforeAnotherMacsRenameIsSentOnTheVersionItWasTypedOn() async throws {
        let (library, source) = try await loaded()
        let drafts = DetailsPresentation()
        let typedOn = try #require(library.item(F.n1)?.version)
        drafts.typeTitle("Mine", of: F.n1, in: library)
        var renamed = try #require(library.item(F.n1))
        renamed.title = "Theirs"
        renamed.version = ItemVersion(typedOn.rawValue + 1)
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.n1)?.version == renamed.version })
        #expect(drafts.saveTitle(of: F.n1, in: library, undoManager: nil))
        #expect(source.writes.last == .editProperties(F.n1, ["title": .string("Mine")], base: typedOn))
        // The next title starts from the version the library then holds.
        drafts.typeTitle("Mine again", of: F.n1, in: library)
        #expect(drafts.draft(for: F.n1, key: "title").readAt == renamed.version)
    }

    /// A window with no editor in it still has its titles saved by a flush, as before a change of library. One the
    /// library refuses stops the flush, and one whose item has gone goes back to the person when the window goes.
    @Test func aWindowWithNoEditorHasItsTitlesFlushedOrHandedBack() async throws {
        let (library, source) = try await loaded()
        let drafts = DetailsPresentation()
        let window = WindowTitleDrafts()
        window.keep(drafts, of: nil, in: library) { _ in }
        defer { window.windowWent() }

        let version = try #require(library.item(F.n1)?.version)
        drafts.typeTitle("Before the change", of: F.n1, in: library)
        #expect(await flushAll())
        #expect(source.writes.last == .editProperties(F.n1, ["title": .string("Before the change")], base: version))
        #expect(drafts.unsavedTitles.isEmpty)

        drafts.typeTitle(" ", of: F.n2, in: library)
        #expect(await !flushAll(), "a title the library refuses stops the change rather than being lost")
        #expect(drafts.unsavedTitles == [F.n2])
        #expect(library.notices.waiting.last?.title == "Couldn’t Save Title")

        drafts.typeTitle("Typed as it went", of: F.n2, in: library)
        source.send(.removed([F.n2]))
        #expect(await eventually { library.item(F.n2) == nil })
        window.windowWent()
        #expect(drafts.unsavedTitles.isEmpty)
        #expect(library.notices.waiting.last?.text == "Typed as it went", "the title goes back to the person")
    }
}
