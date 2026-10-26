import Foundation
import Marfa
import MarfaTesting
import struct MarfaCore.Item
import Testing
import WebKit
@testable import MAPP

/// A note with no text yet, as quick add makes from a title alone, holds no text property at all. The page shows it
/// empty, and what is typed there is saved to it and to no other note.
extension EditorTests {
    private static let stamp = "2026-10-26T00:00:00Z"

    private static func row(_ id: String, title: String, body: String?) -> Marfa.Item {
        var properties: JSONObject = ["title": .string(title)]
        if let body { properties["body"] = .string(body) }
        return Marfa.Item(
            id: id, type: "core.note", properties: properties, state: .active, tier: .library, version: 1, schemaVersion: 1,
            source: "test", sourceId: nil, occurredAt: stamp, createdAt: stamp, updatedAt: stamp, tags: [])
    }

    @Test func aNoteWithNoTextShowsAnEmptyPageAndSavesTypingToItself() async throws {
        let itemTypes = [
            ItemType(
                id: "core.note", label: "Note",
                fields: [
                    TypeField(name: "title", type: "string", declaredBy: "core.note"),
                    TypeField(name: "body", type: "string", declaredBy: "core.note"),
                ], titleField: "title", bodyField: "body"),
        ]
        let fake = WorkingCopy.fake(
            items: [Self.row("kitchen", title: "Kitchen quotes", body: kitchen), Self.row("empty", title: "Plain check", body: nil)],
            itemTypes: itemTypes)
        let source = MarfaSource(
            copy: fake.copy, connection: SampleLibrary.connection, reading: MarfaRead(copy: fake.copy), refreshing: Whole(copy: fake.copy))
        source.events.yield(.paint)
        let library = MarfaLibrary(source: source, notices: Notices())
        let kitchenID = ItemID("kitchen"), emptyID = ItemID("empty")
        try #require(await eventually { library.isLoaded && library.item(emptyID) != nil })
        #expect(library.body(of: emptyID)?.text == "", "a note without a text property has empty text")

        let page = try await Harness(library: library)
        var saved: [ItemID] = []
        page.editor.onChange = { id, markdown, read in
            saved.append(id)
            library.updateBody(of: id, to: markdown, readAt: read)
        }
        try await page.show(kitchenID)
        #expect(try await eventuallyAsking {
            (try await page.editor.webView.evaluateJavaScript("document.querySelector('.ProseMirror').textContent") as? String)?
                .hasPrefix("Kitchen quotes") == true
        })

        try await page.show(emptyID)
        #expect(try await page.shownText(until: "") == "")
        #expect(page.editor.isEditable)

        try await page.run("document.querySelector('.ProseMirror').focus(); document.execCommand('insertText', false, 'X')")
        page.editor.flush()
        try await page.wait { !saved.isEmpty }
        #expect(Set(saved) == [emptyID])
        #expect(await eventually { library.body(of: emptyID)?.text.contains("X") == true })
        #expect(library.body(of: kitchenID)?.text == kitchen)
        await source.close()
    }
}
