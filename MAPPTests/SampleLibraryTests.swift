import Foundation
import Marfa
import SwiftUI
import Testing
@testable import MAPP

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

    @Test func aPreviewLeavesOutTheLineTheNameCameFromAndJoinsTheRestWithSpaces() {
        func display(_ properties: JSONObject) -> ItemDisplay {
            SampleLibrary.display(ItemDisplayInput(type: "core.note", properties: properties))
        }
        let untitled = display(["body": .string("Morning walk\n\nSun on the hill.\nBirds everywhere.")])
        #expect(untitled.name == "Morning walk")
        #expect(untitled.preview == "Sun on the hill. Birds everywhere.")
        let titled = display(["title": .string("Walk"), "body": .string("Morning walk\nSun on the hill.")])
        #expect(titled.name == "Walk")
        #expect(titled.preview == "Morning walk Sun on the hill.")
        let oneLine = display(["body": .string("Only a line")])
        #expect(oneLine.name == "Only a line" && oneLine.preview == nil)
        let long = display(["title": .string("T"), "body": .string(String(repeating: "word ", count: 100))])
        #expect(long.preview?.count == 240 && long.preview?.hasSuffix("\u{2026}") == true)
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

    /// The sample's views are held by the fake copy and read through it, as a real copy's are, so one made here lists
    /// its items when opened.
    @Test func aViewMadeOnTheSampleListsItsItems() async throws {
        let (library, _) = try await Self.loaded()
        #expect(library.views.map(\.title).sorted() == ["Recent Notes", "Tasks by Priority"])
        let notes = Set(library.items(in: .allItems).filter { $0.type == TypeID("core.note") }.map(\.id))
        let made = try #require(await library.createView(LibraryViewSettings(
            title: "Only Notes",
            query: LibraryViewQuery(types: [TypeID("core.note")], states: [.active]),
            sort: [LibraryViewSort(field: "updated_at", ascending: false)])))
        #expect(await eventually { Set(library.items(in: .view(made.id)).map(\.id)) == notes })
        #expect(!notes.isEmpty)
        #expect(await eventually { !library.items(in: .view(ItemID("view-recent-notes"))).isEmpty })
    }

    /// A sample launch starts as a first launch does: a table's columns and a saved view's layout that an earlier run
    /// chose, which the defaults keep between runs, never decide which columns the table opens with.
    @Test func aSampleLaunchForgetsTheColumnsAndDefaultViewsAnEarlierRunChose() throws {
        let suite = "MAPP.SampleLibraryTests.columns"
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
