import Foundation
import Testing
@testable import MarfaMac

/// Which groups of the panel's Links take a new link and a removal: a group whose one field the item may change, and no
/// other, so a person never sees a plus or Remove that the library would refuse.
@MainActor
struct PanelLinksTests {
    private func world(editability: RelationField.Editability) -> (library: FakeItemLibrary, item: Item) {
        let item = FakeItemLibrary.note("Page", modified: .now)
        let reading = FakeItemLibrary.collection("Reading")
        let library = FakeItemLibrary(items: [item, reading])
        library.catalogue = FakeItemLibrary.testCatalogue
        library.addToCollection([item.id], reading.id, undoManager: nil)
        library.relationFieldsByItem[item.id] = [
            RelationField(
                field: MarfaMapping.collectionEdge, label: "In Collection", cardinality: .many, allowedTypes: [], targets: [],
                editability: editability)
        ]
        return (library, library.item(item.id) ?? item)
    }

    private func groups(_ world: (library: FakeItemLibrary, item: Item)) -> [PanelLinkGroup] {
        PanelLinks.groups(of: world.item, in: world.library, relationships: [], mentions: [], format: .standard)
    }

    @Test func aGroupTakesChangesOnlyWhereItsFieldIsEditable() {
        let editable = groups(world(editability: .editable))
        #expect(editable.map(\.kind) == [.inCollection])
        #expect(editable.first?.editableField == MarfaMapping.collectionEdge)

        let locked = groups(world(editability: .readOnly("Read only.")))
        #expect(locked.map(\.kind) == [.inCollection])
        #expect(locked.first?.editableField == nil)
    }
}
