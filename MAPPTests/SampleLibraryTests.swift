import Foundation
import Testing
@testable import MAPP

/// The sample library the UI tests and screenshots use, over the package's fake working copy, which answers every
/// write as soon as it is queued.
@MainActor
@Suite struct SampleLibraryTests {
    private static func loaded() async throws -> (MarfaLibrary, MarfaSource) {
        let source = SampleLibrary.open(SampleLibrary.connection)
        let library = MarfaLibrary(source: source, notices: Notices())
        source.refresh()
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// Text typed into a note the page opened before its create was answered, saved after each answer as the page
    /// saves while the person types, is kept: each save follows the version the answers before it moved the note to.
    @Test func textTypedOnANoteJustMadeIsKeptSaveAfterSave() async throws {
        let (library, source) = try await Self.loaded()
        let id = try #require(library.createItem(
            typeID: "core.note", title: "Call the plumber", body: "Ask about the leak under the sink.", parentID: nil,
            in: .allNotes, undoManager: nil))
        let read = ItemBody(id: id, text: "Ask about the leak under the sink.", version: ItemVersion(0))
        try #require(await eventually {
            library.body(of: id)?.version == ItemVersion(1) && library.syncReport.waiting == 0
        })
        var text = read.text
        for typed in [" T", "omorrow", "."] {
            text += typed
            library.saveText(text, of: id, readAt: read.version, failing: "Call the plumber")
            await source.flush()
            try #require(await eventually { library.syncReport.waiting == 0 })
        }
        #expect(library.notices.waiting.isEmpty)
        #expect(library.syncReport.problems.isEmpty)
        #expect(library.body(of: id)?.text == "Ask about the leak under the sink. Tomorrow.")
    }

    /// The same holds for a note the sample started with.
    @Test func textTypedOnANoteItHeldIsKeptSaveAfterSave() async throws {
        let (library, source) = try await Self.loaded()
        let id = ItemID("weekly-review")
        let read = try #require(library.body(of: id))
        var text = read.text
        for typed in [" A", " B", " C"] {
            text += typed
            library.saveText(text, of: id, readAt: read.version, failing: "Weekly review")
            await source.flush()
            try #require(await eventually { library.syncReport.waiting == 0 })
        }
        #expect(library.notices.waiting.isEmpty)
        #expect(library.syncReport.problems.isEmpty)
        #expect(library.body(of: id)?.text == read.text + " A B C")
    }
}
