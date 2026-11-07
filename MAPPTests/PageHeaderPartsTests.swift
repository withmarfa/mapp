import Foundation
import Marfa
import Testing
@testable import MAPP

struct PageHeaderPartsTests {
    /// A saved web page draws the header of a page for reading in either look, so the switch between the looks never
    /// moves the pins: it once drew the header of any other kind in Original, which pins other rows.
    @MainActor @Test func aSavedPageKeepsTheHeaderOfAPageForReadingInEitherLook() {
        let library = FakeItemLibrary()
        library.catalogue = Catalogue(itemTypes: [
            ItemTypeInfo(id: TypeID("core.bookmark"), label: "Bookmark", fields: [], titleField: "title", bodyField: "body", parent: nil),
        ])
        var item = Item(
            id: ItemID("10000000-0000-0000-0000-000000000001"), type: TypeID("core.bookmark"), title: "Title", titleRule: .property("title"),
            version: ItemVersion(1), created: .distantPast, modified: .distantPast)
        item.tags = ["read"]
        library.items = [item]
        var placements = PagePlacements()
        placements.setPins([PagePlacement.tags], of: TypeID("core.bookmark"))
        let parts = PageHeaderParts(of: item, in: library, placements: placements, dateFormat: .automatic)
        #expect(parts.kind == .reading)
        #expect(!parts.pins.pins.isEmpty, "the pins are the item's, whichever look the page is in")
    }
}
