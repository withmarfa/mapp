import Foundation
import Testing
@testable import MAPP

/// The sample library the UI tests and screenshots use, over the package's fake working copy, which answers the
/// writes it holds when it is flushed.
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
        await source.flush()
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
        let typed = "Ask about the leak under the sink. Tomorrow."
        #expect(try await source.body(of: id).text == typed)
        // The library reads the text again after the last answer, on its own stream, which can come after the report.
        #expect(await eventually { library.body(of: id)?.text == typed }, "\(String(describing: library.body(of: id)))")
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
        let typed = read.text + " A B C"
        #expect(try await source.body(of: id).text == typed)
        #expect(await eventually { library.body(of: id)?.text == typed }, "\(String(describing: library.body(of: id)))")
    }

    /// The sample declares a container type, so it shows collections and offers to make one.
    @Test func theSampleHasCollectionsInTheirOrder() async throws {
        let (library, _) = try await Self.loaded()
        #expect(library.collections.map(\.title) == ["Home", "Reading"])
        // Home orders its members by position; Reading gives none, so it lists them by title.
        #expect(library.items(in: .collection(ItemID("collection-home"))).map(\.title) == ["Boiler", "Bike service", "Moving checklist"])
        let reading = library.items(in: .collection(ItemID("collection-reading"))).map(\.title)
        #expect(reading == reading.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
        #expect(reading.count == 3)
        let collectionTypes = Set(library.catalogue.collectionTypes)
        #expect(QuickAdd.types(in: library).contains { collectionTypes.contains($0.id) })
        let members = library.relationships(for: ItemID("collection-home")).first { $0.field == "inverse:in-collection" }
        #expect(members?.label == "Contents")
    }
}
