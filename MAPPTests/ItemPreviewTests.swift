import Foundation
import struct Marfa.ItemType
import MarfaIcons
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct ItemPreviewTests {
    func text(_ body: String, title: String = "Title") -> String { ItemPreview.text(of: body, title: title) }

    @Test func markdownMarksAreStripped() {
        let body = """
        This has **strong** and *light* words, `code`, a [link](https://example.com), and ~~gone~~.
        > A quoted line
        - a list item
        1. a numbered item
        """
        #expect(text(body) == "This has strong and light words, code, a link, and gone. A quoted line. A list item. A numbered item")
    }

    @Test func eachLineEndsAsASentenceSoItemsReadApart() {
        #expect(text("- own type\n- Share the log\n- Done!\n- see notes:\n- (aside)") == "own type. Share the log. Done! See notes: (aside)")
        #expect(text("One line with no stop") == "One line with no stop")
        #expect(text("Steps\n- iPhone first\n- macOS next", title: "none") == "Steps. iPhone first. macOS next")
    }

    @Test func headingLinesAreSkipped() {
        let body = "## Why\n\n- **Two names are in use.**\n- Pick one.\n\n### Next\n\nDo it."
        #expect(text(body) == "Two names are in use. Pick one. Do it.")
    }

    @Test func aBodyThatIsOnlyHeadingsHasNoPreview() {
        #expect(text("# One\n\n## Two\n") == "")
    }

    @Test func wikiLinksReadAsTheirNames() {
        #expect(text("See [[Field notes]] and [[Plan|the plan]] and ![[Dusk.png]].") == "See Field notes and the plan and Dusk.png.")
    }

    @Test func imagesAreTheirDescriptions() {
        #expect(text("![A diagram](image.png) shows it") == "A diagram shows it")
    }

    @Test func htmlCommentsAreRemovedWhateverTheirLength() {
        #expect(text("<!-- hidden -->Shown <!-- also\nhidden --> text") == "Shown text")
        #expect(text("Kept <!-- never closed\nand long") == "Kept")
    }

    @Test func whitespaceCollapsesToSingleSpaces() {
        #expect(text("First   line\n\n\n\tsecond\t\tline\r\nthird") == "First line. Second line. Third")
    }

    @Test func aFirstLineThatRepeatsTheTitleIsDropped() {
        #expect(text("Groceries\n\nMilk and eggs", title: "groceries") == "Milk and eggs")
    }

    @Test func theLimitCapsAVeryLongBody() {
        let body = "Title\n" + String(repeating: "word ", count: 5_000)
        #expect(text(body).count == ItemPreview.limit)
    }

    @Test func aLongBodyIsOnlyReadAsFarAsAPreviewNeeds() {
        let body = String(repeating: "Line of words in a long note.\n", count: 100_000)
        #expect(text(body).count == ItemPreview.limit)
    }

    @Test func theFallbackStandsInForAnEmptyBody() {
        #expect(ItemPreview.text(of: "", title: "Task", fallback: "A **short** description") == "A short description")
        #expect(ItemPreview.text(of: "Body", title: "Task", fallback: "Description") == "Body")
    }

    @Test func aFileReadsAsItsKindAndSize() throws {
        let described = ItemPreview.file(.plainText, byteCount: 76)
        let kind = try #require(UTType.plainText.localizedDescription)
        #expect(described == kind.prefix(1).uppercased() + kind.dropFirst() + ", " + ByteCountFormatter.string(fromByteCount: 76, countStyle: .file))
        #expect(described.first?.isUppercase == true)
        #expect(described.hasSuffix("76 bytes"))
    }

    @Test func aFileWithNoKnownSizeReadsAsItsKind() {
        #expect(ItemPreview.file(.pdf, byteCount: 0) == UTType.pdf.localizedDescription)
    }
}

struct TypeIconTests {
    private func info(_ id: String, icon: String?, parent: String? = nil) -> ItemTypeInfo {
        ItemTypeInfo(id: TypeID(id), label: id, fields: [], titleField: nil, bodyField: nil, parent: parent.map { TypeID($0) }, icon: icon)
    }

    @Test func aTypeAnswersTheIconTheServerResolvedForIt() {
        let catalogue = Catalogue(itemTypes: [info("core.note", icon: "file-text"), info("acme.bug", icon: "bug", parent: "core.note")])
        #expect(catalogue.icon(for: TypeID("core.note")) == "file-text")
        #expect(catalogue.icon(for: TypeID("acme.bug")) == "bug")
    }

    @Test func theOwnersChoiceReachesTheCatalogueThroughTheMapping() {
        let type = MarfaMapping.itemType(ItemType(id: "user.decision", label: "Decision", icon: "scale"))
        #expect(type.icon == "scale")
        #expect(Catalogue(itemTypes: [type]).icon(for: TypeID("user.decision")) == "scale")
    }

    @Test func aTypeWithNoIconAnywhereAnswersNilAndIsDrawnAsTheFallback() {
        let catalogue = Catalogue(itemTypes: [info("acme.thing", icon: nil)])
        #expect(catalogue.icon(for: TypeID("acme.thing")) == nil)
        #expect(catalogue.icon(for: TypeID("not.in.the.catalogue")) == nil)
        #expect(TypeIconArtwork(name: catalogue.icon(for: TypeID("acme.thing"))) == .fallback)
    }

    @Test func theAppReadsNoMeaningIntoATypesName() {
        // A type named like a built-in has no icon of the built-in's; only the catalogue gives one.
        #expect(Catalogue().icon(for: TypeID("core.note")) == nil)
    }

    @Test func anUnknownNameIsDrawnAsTheFallbackAndAKnownOneIsNot() {
        #expect(TypeIconArtwork(name: "no-such-lucide-icon") == .fallback)
        #expect(TypeIconArtwork(name: "scale") != .fallback)
        #expect(TypeIconArtwork(name: "file-text") != .fallback)
    }

    @Test func theEditorPageFindsATypesIconByItsKey() throws {
        let item = LinkedItem(item: ItemID("a"), title: "A", icon: "file-text", type: "Note", date: "Today")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: String]
        #expect(json?["symbol"] == TypeIconKey.value(for: "file-text"))
        #expect(TypeIconKey.value(for: "link") != "link")
    }

    @Test func theLabelComesFromTheCatalogueElseTheLastSegment() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("aic.ticket.spike"), label: "Question", fields: [], titleField: nil, bodyField: nil, parent: nil)
        ])
        #expect(catalogue.label(for: TypeID("aic.ticket.spike")) == "Question")
        #expect(catalogue.label(for: TypeID("acme.widget")) == "Widget")
    }
}

@MainActor
struct ItemMetaTests {
    let date = Date(timeIntervalSince1970: 1_700_000_000)

    func item(_ title: String, type: String = "core.note", parent: Item? = nil, tier: Tier = .library) -> Item {
        var item = Item(
            id: .mint(), type: TypeID(type), title: title, titleRule: .firstLine, tier: tier,
            version: ItemVersion(1), created: date, modified: date)
        if let parent {
            item.edgesOut = [Edge(id: EdgeID(title), type: "child-of", source: item.id, target: .item(parent.id), origin: .property("child-of"))]
        }
        return item
    }

    @Test func aMixedListNamesTheTypeAndNotWhereTheItemIsFiled() {
        let project = item("Field Research", type: "test.project")
        let notes = item("Interviews", parent: project)
        let task = item("Book rooms", type: "core.task", parent: notes)
        let library = FakeItemLibrary(items: [project, notes, task])
        let meta = ItemMeta.make(for: task, in: library, context: .init(mixesTypes: true))
        #expect(meta.pieces.map(\.label) == ["Task"])
        #expect(meta.pieces.map(\.icon) == [.type("list-checks")])
    }

    @Test func aListOfOneTypeLeavesTheTypeOut() {
        let project = item("Field Research", type: "aic.project")
        let task = item("Book rooms", type: "aic.ticket.task", parent: project)
        let library = FakeItemLibrary(items: [project, task])
        #expect(ItemMeta.make(for: task, in: library, context: .init()).isEmpty)
    }

    @Test func anItemWithNoProjectAndNothingToSayHasNoLine() {
        let note = item("Loose note")
        let library = FakeItemLibrary(items: [note])
        #expect(ItemMeta.make(for: note, in: library, context: .init()).isEmpty)
    }

    @Test func aFeedItemNamesTheInboxAnywhereButTheInbox() {
        let feed = item("Clipped", tier: .feed)
        let library = FakeItemLibrary(items: [feed])
        #expect(ItemMeta.make(for: feed, in: library, context: .init()).pieces.map(\.label) == ["Inbox"])
        #expect(ItemMeta.make(for: feed, in: library, context: .init(isInbox: true)).isEmpty)
    }
}
