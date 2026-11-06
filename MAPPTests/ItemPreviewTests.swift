import Foundation
import struct Marfa.ItemType
import MarfaIcons
import Testing
import UniformTypeIdentifiers
@testable import MAPP

struct ItemPreviewTests {
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
        #expect(TypeIconArtwork(id: catalogue.icon(for: TypeID("acme.thing"))) == .fallback)
    }

    @Test func theAppReadsNoMeaningIntoATypesName() {
        // A type named like a built-in has no icon of the built-in's; only the catalogue gives one.
        #expect(Catalogue().icon(for: TypeID("core.note")) == nil)
    }

    @Test func aBareOrUnknownNameIsDrawnAsTheFallbackAndAFullIDIsNot() {
        #expect(TypeIconArtwork(id: "lucide:no-such-lucide-icon") == .fallback)
        #expect(TypeIconArtwork(id: "scale") == .fallback, "a bare name is not an ID")
        #expect(TypeIconArtwork(id: "file-text") == .fallback)
        #expect(TypeIconArtwork(id: "lucide:scale") != .fallback)
        #expect(TypeIconArtwork(id: "lucide:file-text") != .fallback)
    }

    @Test func theEditorPageFindsATypesIconByItsKey() throws {
        let item = LinkedItem(item: ItemID("a"), title: "A", icon: "file-text", type: "Note", date: "Today")
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: String]
        #expect(json?["symbol"] == TypeIconKey.value(for: "file-text"))
        #expect(TypeIconKey.value(for: "link") != "link")
    }

    @Test func theLabelComesFromTheCatalogueElseTheIdentifier() {
        let catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("aic.ticket.spike"), label: "Question", fields: [], titleField: nil, bodyField: nil, parent: nil)
        ])
        #expect(catalogue.label(for: TypeID("aic.ticket.spike")) == "Question")
        #expect(catalogue.label(for: TypeID("acme.widget")) == "acme.widget")
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
        #expect(meta.pieces.map(\.icon) == [.type("lucide:list-checks")])
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

    @Test func aFeedItemNamesNoTierOutsideTheInbox() {
        let feed = item("Clipped", tier: .feed)
        let library = FakeItemLibrary(items: [feed])
        #expect(ItemMeta.make(for: feed, in: library, context: .init()).isEmpty)
        #expect(ItemMeta.make(for: feed, in: library, context: .init(mixesTypes: true)).pieces.map(\.label) == ["Note"])
    }

    /// Reads the context as the note list does, from the items the place shows.
    private func mixesTypes(in place: SidebarItem, of library: FakeItemLibrary) -> Bool {
        let browser = Browser()
        browser.show(place, in: library, order: NoteOrder())
        let items = browser.sections(in: library, order: NoteOrder(), now: library.now()).flatMap(\.items)
        return browser.metaContext(for: items).mixesTypes
    }

    @Test func aListNamesTheTypeOnlyWhereItsItemsMixTypes() {
        let note = FakeItemLibrary.note("Note", modified: date)
        let clipped = FakeItemLibrary.note("Clipped", modified: date, tier: .feed)
        var task = item("Book rooms", type: "core.task")
        task.tier = .feed
        let library = FakeItemLibrary(items: [note, clipped, task], now: date)
        #expect(mixesTypes(in: .allNotes, of: library))
        #expect(mixesTypes(in: .inbox, of: library))
        #expect(!mixesTypes(in: .itemType("core.note"), of: FakeItemLibrary(items: [note, clipped], now: date)))
        #expect(!mixesTypes(in: .inbox, of: FakeItemLibrary(items: [note, clipped], now: date)))
    }
}
