import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Which page an item opens to: HTML never reaches Quick Look, and an item with an HTML document attached opens to it.
@MainActor struct ItemPageLayoutTests {
    private let library = FakeItemLibrary()

    @discardableResult
    private func file(
        _ title: String, type: UTType?, attachedTo host: ItemID? = nil, state: ItemState = .active,
        typeID: String = "core.file", created: Date = .now
    ) -> Item {
        let id = ItemID.mint()
        let item = Item(
            id: id, type: TypeID(typeID), title: title, titleRule: .property("title"),
            content: type.map { .file($0, byteCount: 10) } ?? .file(.data, byteCount: 10), state: state,
            version: ItemVersion(1), created: created, modified: created,
            edgesOut: host.map {
                [Edge(id: EdgeID("attached-\(id.rawValue)"), type: MarfaMapping.attachmentEdge, source: id, target: .item($0), origin: .body)]
            } ?? [])
        library.items.append(item)
        return item
    }

    @Test func anHTMLFileOpensInTheWebPageWithNoScripts() {
        let typed = file("Page.html", type: .html)
        let untyped = file("Saved.htm", type: nil)

        #expect(library.pageLayout(of: typed) == .webPage(document: typed.id, runsScripts: false))
        #expect(library.pageLayout(of: untyped) == .webPage(document: untyped.id, runsScripts: false))
    }

    @Test func anyOtherFileOpensInItsPreview() {
        #expect(library.pageLayout(of: file("List.txt", type: .plainText)) == .file)
    }

    @Test func aWebPageRunsItsScripts() {
        library.catalogue.itemTypes[TypeID("core.file.webpage")] = ItemTypeInfo(
            id: TypeID("core.file.webpage"), label: "Web Page", fields: [], titleField: nil, bodyField: nil, parent: .file)
        let page = file("Saved page", type: .html, typeID: "core.file.webpage")

        #expect(library.pageLayout(of: page) == .webPage(document: page.id, runsScripts: true))
    }

    /// An item to read: a type under `core.media`, which the page treats as something to read.
    private func article(_ title: String = "An article") -> Item {
        let media = TypeID("core.media")
        library.catalogue.itemTypes[media] = ItemTypeInfo(id: media, label: "Media", fields: [], titleField: nil, bodyField: nil, parent: nil)
        let id = ItemID.mint()
        let item = Item(
            id: id, type: media, title: title, titleRule: .property("title"), version: ItemVersion(1), created: .now, modified: .now)
        library.items.append(item)
        return item
    }

    @Test func anItemToReadWithAnHTMLDocumentAttachedOpensToIt() {
        let article = article()
        file("cover.png", type: .png, attachedTo: article.id)
        let older = file("article.html", type: .html, attachedTo: article.id, created: .now - 60)
        file("again.html", type: .html, attachedTo: article.id)

        #expect(library.pageLayout(of: article) == .webPage(document: older.id, runsScripts: false))
    }

    @Test func aDocumentIsFoundByItsContentTypeNotByAnyConnectorsField() {
        let article = article()
        let untyped = file("saved.htm", type: nil, attachedTo: article.id)

        #expect(library.pageLayout(of: article) == .webPage(document: untyped.id, runsScripts: false))
    }

    @Test func anyOtherItemKeepsItsTextWhateverIsAttached() {
        let note = library.add("A note\n")
        file("page.html", type: .html, attachedTo: note.id)
        let binned = article("Binned document")
        file("article.html", type: .html, attachedTo: binned.id, state: .trashed)
        let pictured = article("Pictured")
        file("cover.png", type: .png, attachedTo: pictured.id)
        let unknown = article("Unknown file")
        file("blob", type: nil, attachedTo: unknown.id)

        #expect(library.pageLayout(of: note) == .text, "an attachment never hides a note's text")
        #expect(library.pageLayout(of: binned) == .text, "a document in the bin does not count")
        #expect(library.pageLayout(of: pictured) == .text)
        #expect(library.pageLayout(of: unknown) == .text, "a file of unknown type is not taken for HTML")
    }
}
