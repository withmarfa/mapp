import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Which page an item opens to: HTML never reaches Quick Look, and an item with an HTML document attached opens to it.
@MainActor struct ItemPageLayoutTests {
    private let library = FakeItemLibrary()

    @discardableResult
    private func file(
        _ title: String, type: UTType?, kind: String? = nil, attachedTo host: ItemID? = nil, state: ItemState = .active,
        typeID: String = "core.file", created: Date = .now
    ) -> Item {
        let id = ItemID.mint()
        let item = Item(
            id: id, type: TypeID(typeID), title: title, titleRule: .property("title"),
            properties: kind.map { [Property(key: ItemPageLayout.resourceKindField, value: .string($0))] } ?? [],
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

    @Test func anItemWithAnHTMLDocumentAttachedOpensToIt() {
        let article = library.add("An article\n")
        file("cover.png", type: .png, kind: "image", attachedTo: article.id)
        let older = file("article.html", type: .html, kind: "html", attachedTo: article.id, created: .now - 60)
        file("again.html", type: .html, kind: "html", attachedTo: article.id)

        #expect(library.pageLayout(of: article) == .webPage(document: older.id, runsScripts: false))
    }

    @Test func anItemWithoutOneOpensToItsText() {
        let plain = library.add("A note\n")
        let binned = library.add("Binned document\n")
        file("article.html", type: .html, kind: "html", attachedTo: binned.id, state: .trashed)
        let unmarked = library.add("Unmarked document\n")
        file("article.html", type: .html, attachedTo: unmarked.id)

        #expect(library.pageLayout(of: plain) == .text)
        #expect(library.pageLayout(of: binned) == .text, "a document in the bin does not count")
        #expect(library.pageLayout(of: unmarked) == .text, "only a resource kind of html counts")
    }
}
