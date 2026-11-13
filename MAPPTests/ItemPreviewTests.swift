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
