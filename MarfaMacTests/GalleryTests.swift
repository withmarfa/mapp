import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

@Suite(.hangLimit)
struct GalleryTests {
    let a = ItemID.mint(), b = ItemID.mint(), c = ItemID.mint(), d = ItemID.mint()

    private static func attachedFile() -> Item {
        var file = Item(
            id: .mint(), type: TypeID("core.file.image"), title: "Photo.png", titleRule: .firstLine, content: .file(.png, byteCount: 10),
            version: ItemVersion(1), created: .now, modified: .now)
        file.state = .active
        return file
    }

    @Test func attachmentsAreReadOncePerItemAndOnlyWhereAPictureShows() {
        let library = FakeItemLibrary()
        let note = library.add("A note\n").id
        let other = library.add("Another\n").id
        let photo = library.attachPicture(URL(fileURLWithPath: "/tmp/Photo.png"), to: note)
        let items = [library.item(note), library.item(other), library.item(photo)].compactMap { $0 }
        let found = CardAttachments.of(items, in: library, showsPicture: true)
        #expect(found[note]?.map(\.id) == [photo])
        #expect(found[other] == nil && found[photo] == nil, "no attachments, and a file has none")
        #expect(CardAttachments.of(items, in: library, showsPicture: false).isEmpty, "a card with no picture reads none")
    }

    @Test func aCardIsRedrawnForItsOwnItemAndNotForTheSelection() {
        let (library, _, newer, other) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        func content(_ item: Item) -> RowContent {
            RowContent.card(
                for: item, look: .empty, catalogue: library.catalogue, list: RowList(day: .now), shape: CardShape())
        }
        func card(_ item: Item, width: CGFloat = 200, cards: ViewCards = ViewCards(), content said: RowContent? = nil, attached: [Item] = []) -> GalleryCard {
            GalleryCard(item: item, browser: browser, width: width, cards: cards, content: said ?? content(item), attachments: attached)
        }
        let before = card(newer)
        browser.show(.allItems, in: library, order: ItemOrder())
        browser.selection = [newer.id]
        #expect(before == card(newer), "a selection that moves leaves the card alone")
        browser.selection = [other.id]
        #expect(before == card(newer), "so does another card's selection")
        var renamed = newer
        renamed.title = "Renamed"
        #expect(before != card(renamed), "its own item changing redraws it")
        #expect(before != card(newer, width: 240), "so does its width")
        #expect(before != card(newer, cards: ViewCards(preview: .text)), "so does the view's choice of preview")
        var said = content(newer)
        said.secondary = "A new line"
        #expect(before != card(newer, content: said), "so does what the card says")
        #expect(before == card(newer, cards: ViewCards()), "the same inputs leave it alone")
        let file = Self.attachedFile()
        #expect(before != card(newer, attached: [file]), "a file attached to it redraws it")
        #expect(card(newer, attached: [file]) == card(newer, attached: [file]), "another card's link leaves it alone")
    }
}
