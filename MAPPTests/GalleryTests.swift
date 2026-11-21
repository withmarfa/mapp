import CoreGraphics
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

@Suite(.hangLimit)
struct GalleryTests {
    let a = ItemID.mint(), b = ItemID.mint(), c = ItemID.mint(), d = ItemID.mint()

    @Test func clickingAndModifierSelectionUseVisibleOrder() {
        let ids = [a, b, c, d]
        #expect(GallerySelection.selecting(c, among: ids, current: [a], anchor: a, extending: false, toggling: false) == [c])
        #expect(GallerySelection.selecting(c, among: ids, current: [a], anchor: a, extending: false, toggling: true) == [a, c])
        #expect(GallerySelection.selecting(a, among: ids, current: [a, c], anchor: a, extending: false, toggling: true) == [c])
        #expect(GallerySelection.selecting(d, among: ids, current: [b], anchor: b, extending: true, toggling: false) == [b, c, d])
        #expect(GallerySelection.selecting(a, among: ids, current: [c], anchor: c, extending: true, toggling: false) == [a, b, c])
        #expect(GallerySelection.selecting(d, among: ids, current: [], anchor: .mint(), extending: true, toggling: false) == [d])
    }

    @Test func keyboardNavigationStopsAtTheCollectionEdges() {
        #expect(GallerySelection.moving(from: b, among: [a, b, c, d], by: 2) == d)
        #expect(GallerySelection.moving(from: d, among: [a, b, c, d], by: 2) == d)
        #expect(GallerySelection.moving(from: a, among: [a, b], by: -1) == a)
        #expect(GallerySelection.moving(from: .mint(), among: [a, b], by: 1) == a)
        #expect(GallerySelection.moving(from: a, among: [], by: 1) == nil)
        #expect(GallerySelection.movingVertically(from: a, sections: [[a, b], [c, d]], columns: 3, down: true) == c)
        #expect(GallerySelection.movingVertically(from: d, sections: [[a, b], [c, d]], columns: 3, down: false) == b)
        #expect(GallerySelection.movingVertically(from: b, sections: [[a, b], [c]], columns: 3, down: true) == c)
        #expect(GallerySelection.movingVertically(from: a, sections: [], columns: 0, down: true) == nil)
    }

    @Test func galleryRestoresAsACollectionAndKeepsItsSelection() throws {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        let saved = Browser()
        saved.sidebarItem = .recents
        saved.viewMode = .gallery
        saved.selection = [newer.id]
        let data = try JSONEncoder().encode(saved.snapshot())
        let restored = Browser()
        restored.restore(from: data, in: library, order: ItemOrder())
        #expect(restored.showsCollection)
        #expect(restored.selection == [newer.id])
    }

    @Test func aNewItemOpensInThePageAndReturningToGalleryOrChangingPlaceReturnsToTheGrid() async {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        browser.viewMode = .gallery
        browser.show(.recents, in: library, order: ItemOrder())
        browser.open(browser.selection, as: .fullPage)
        #expect(!browser.showsCollection)
        let settings = UserDefaults(suiteName: "GalleryTests.\(UUID().uuidString)")!
        settings.set(ItemOpening.fullPage.rawValue, forKey: ListKey.openItemsIn)
        let id = await browser.quickAdded("New", in: library, defaults: settings)
        #expect(!browser.showsCollection, "with Open Items at Full Page the new item opens in the page, not behind the grid")
        #expect(browser.selection == id.map { [$0] })
        browser.returnToCollection()
        #expect(browser.showsCollection)
        browser.open(browser.selection, as: .fullPage)
        browser.show(.inbox, in: library, order: ItemOrder())
        #expect(browser.showsCollection)
        browser.show(.recents, in: library, order: ItemOrder())
        #expect(browser.showsCollection)
    }

    @Test func aNewItemOpensInTheModalOverTheGridWhenSettingsSayModal() async {
        let (library, _, _, _) = BrowserTests().makeFakeLibrary()
        let browser = Browser()
        browser.viewMode = .gallery
        browser.show(.recents, in: library, order: ItemOrder())
        let settings = UserDefaults(suiteName: "GalleryTests.\(UUID().uuidString)")!
        let id = await browser.quickAdded("New", in: library, defaults: settings)
        #expect(browser.showsCollection, "the grid stays behind the modal")
        #expect(browser.modalItem == id)
    }

    @Test func aCardsFactsFollowItsShape() {
        let (library, _, newer, _) = BrowserTests().makeFakeLibrary()
        #expect(GalleryCardFacts(of: newer, attachments: [], in: library).kind == .text)
        var file = newer
        file.content = .file(.png, byteCount: 10)
        #expect(GalleryCardFacts(of: file, attachments: [], in: library).kind == .file(.png))
    }

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
