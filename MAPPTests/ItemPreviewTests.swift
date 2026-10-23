import Foundation
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
        #expect(text(body) == "This has strong and light words, code, a link, and gone. A quoted line a list item a numbered item")
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
        #expect(text("First   line\n\n\n\tsecond\t\tline\r\nthird") == "First line second line third")
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

    @Test func aFileReadsAsItsKindAndSize() {
        let described = ItemPreview.file(.plainText, byteCount: 76)
        #expect(described == (UTType.plainText.localizedDescription ?? "") + ", " + ByteCountFormatter.string(fromByteCount: 76, countStyle: .file))
        #expect(described.hasSuffix("76 bytes"))
    }

    @Test func aFileWithNoKnownSizeReadsAsItsKind() {
        #expect(ItemPreview.file(.pdf, byteCount: 0) == UTType.pdf.localizedDescription)
    }
}

struct TypeSymbolTests {
    @Test(arguments: [
        ("core.note", "doc.text"), ("aic.ticket.task", "checkmark.circle"), ("core.event", "calendar"),
        ("aic.decision", "signpost.right"), ("aic.agent.log", "list.bullet.rectangle"), ("aic.agent.session", "clock"),
        ("aic.epic", "flag"), ("aic.ticket", "ticket"), ("aic.ticket.feature", "sparkles"), ("aic.ticket.spike", "bolt"),
        ("core.bookmark", "bookmark"), ("core.person", "person"), ("core.file", "doc"), ("core.image", "photo"),
        ("aic.project", "folder"),
    ])
    func eachKnownTypeHasItsSymbol(id: String, symbol: String) {
        #expect(TypeSymbol.name(for: TypeID(id)) == symbol)
    }

    @Test func anUnknownTypeTakesItsNearestKnownParent() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("acme.bug"), label: "Bug", fields: [], titleField: nil, bodyField: nil, parent: TypeID("aic.ticket")),
            ItemTypeInfo(id: TypeID("acme.crash"), label: "Crash", fields: [], titleField: nil, bodyField: nil, parent: TypeID("acme.bug")),
        ])
        #expect(TypeSymbol.name(for: TypeID("acme.crash"), in: catalogue) == "ticket")
    }

    @Test func aTypeNothingKnowsIsADocument() {
        #expect(TypeSymbol.name(for: TypeID("acme.widget")) == "doc")
        #expect(TypeSymbol.name(for: TypeID("")) == "doc")
    }

    @Test func aParentCycleEnds() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("a.one"), label: "One", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.two")),
            ItemTypeInfo(id: TypeID("a.two"), label: "Two", fields: [], titleField: nil, bodyField: nil, parent: TypeID("a.one")),
        ])
        #expect(TypeSymbol.name(for: TypeID("a.one"), in: catalogue) == "doc")
    }

    @Test func theLabelComesFromTheCatalogueElseTheLastSegment() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("aic.ticket.spike"), label: "Question", fields: [], titleField: nil, bodyField: nil, parent: nil)
        ])
        #expect(TypeSymbol.label(for: TypeID("aic.ticket.spike"), in: catalogue) == "Question")
        #expect(TypeSymbol.label(for: TypeID("acme.widget"), in: catalogue) == "Widget")
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

    @Test func aMixedListNamesTheTypeAndTheProject() {
        let project = item("Field Research", type: "aic.project")
        let epic = item("Interviews", type: "aic.epic", parent: project)
        let task = item("Book rooms", type: "aic.ticket.task", parent: epic)
        let library = FakeItemLibrary(items: [project, epic, task])
        let meta = ItemMeta.make(for: task, in: library, context: .init(mixesTypes: true))
        #expect(meta.pieces.map(\.label) == ["Task", "Field Research"])
        #expect(meta.pieces.map(\.symbol) == ["checkmark.circle", "folder"])
    }

    @Test func aListOfOneTypeLeavesTheTypeOut() {
        let project = item("Field Research", type: "aic.project")
        let task = item("Book rooms", type: "aic.ticket.task", parent: project)
        let library = FakeItemLibrary(items: [project, task])
        #expect(ItemMeta.make(for: task, in: library, context: .init()).pieces.map(\.label) == ["Field Research"])
    }

    @Test func aProjectsOwnListDoesNotNameTheProject() {
        let project = item("Field Research", type: "aic.project")
        let task = item("Book rooms", type: "aic.ticket.task", parent: project)
        let library = FakeItemLibrary(items: [project, task])
        #expect(ItemMeta.make(for: task, in: library, context: .init(project: project.id)).isEmpty)
    }

    @Test func anItemWithNoProjectAndNothingToSayHasNoLine() {
        let note = item("Loose note")
        let library = FakeItemLibrary(items: [note])
        #expect(ItemMeta.make(for: note, in: library, context: .init(showsPlaces: true, isInbox: false)).isEmpty)
    }

    @Test func aParentThatIsNoProjectIsPassedOver() {
        let epic = item("Interviews", type: "aic.epic")
        let task = item("Book rooms", type: "aic.ticket.task", parent: epic)
        let library = FakeItemLibrary(items: [epic, task])
        #expect(library.project(of: task) == nil)
    }

    @Test func aParentCycleEnds() {
        var one = item("One")
        var two = item("Two", parent: one)
        one.edgesOut = [Edge(id: EdgeID("loop"), type: "child-of", source: one.id, target: .item(two.id), origin: .property("child-of"))]
        two.edgesOut = [Edge(id: EdgeID("loop2"), type: "child-of", source: two.id, target: .item(one.id), origin: .property("child-of"))]
        let library = FakeItemLibrary(items: [one, two])
        #expect(library.project(of: one) == nil)
    }

    @Test func aFeedItemNamesTheInboxAnywhereButTheInbox() {
        let feed = item("Clipped", tier: .feed)
        let library = FakeItemLibrary(items: [feed])
        #expect(ItemMeta.make(for: feed, in: library, context: .init()).pieces.map(\.label) == ["Inbox"])
        #expect(ItemMeta.make(for: feed, in: library, context: .init(isInbox: true)).isEmpty)
    }
}
