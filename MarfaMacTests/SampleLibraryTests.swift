import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MarfaMac

/// The sample library the UI tests and screenshots use, over the package's fake working copy, which answers the
/// writes it holds when it is flushed.
@MainActor
@Suite(.hangLimit) struct SampleLibraryTests {
    private static func loaded() async throws -> (MarfaLibrary, MarfaSource) {
        let source = SampleLibrary.open(SampleLibrary.connection)
        let library = MarfaLibrary(source: source, notices: Notices())
        source.refresh()
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    /// Text typed into an item the page opened before its create was answered, saved after each answer as the page
    /// saves while the person types, is kept: each save follows the version the answers before it moved the item to.
    @Test func textTypedOnAnItemJustMadeIsKeptSaveAfterSave() async throws {
        let (library, source) = try await Self.loaded()
        let id = try #require(library.createItem(
            typeID: "core.note", title: "Call the plumber", body: "Ask about the leak under the sink.", parentID: nil,
            in: .allItems, undoManager: nil))
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

    /// The same holds for an item the sample started with.
    @Test func textTypedOnAnItemItHeldIsKeptSaveAfterSave() async throws {
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

    /// A sample launch starts as a first launch does: a table's columns and a saved view's layout that an earlier run
    /// chose, which the defaults keep between runs, never decide which columns the table opens with.
    @Test func aSampleLaunchForgetsTheColumnsAndDefaultViewsAnEarlierRunChose() throws {
        let suite = "MarfaMac.SampleLibraryTests.columns"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var layout = TableColumnCustomization<ItemTableRow>()
        layout[visibility: "field.status"] = .hidden
        let place = SidebarItem.itemType("core.task")
        defaults.set(ItemTableColumnLayouts.storing(layout, for: place, in: Data()), forKey: ItemTableColumnLayouts.key)
        defaults.set(Data("{}".utf8), forKey: ViewLayouts.key)
        defaults.set(Data("{}".utf8), forKey: PlaceDefaults.key)

        SampleLibrary.forgetStoredChoices(in: defaults)

        #expect(defaults.object(forKey: ItemTableColumnLayouts.key) == nil)
        #expect(defaults.object(forKey: ViewLayouts.key) == nil)
        #expect(defaults.object(forKey: PlaceDefaults.key) == nil)
    }
}
