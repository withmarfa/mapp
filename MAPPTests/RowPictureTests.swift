import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// Whether a list's row has a picture, decided with its content from the item alone: the places a gallery card's picture
/// comes from, only in a Standard list.
@MainActor
struct RowPictureTests {
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let catalogue = LookFixture.catalogue()

    private static func item(content: Item.Content = .markdown, embeds: [BoundEmbed] = [], state: ItemState = .active) -> Item {
        var item = Item(
            id: .mint(), type: TypeID("core.note"), title: "Title", name: "Title", titleRule: .firstLine, version: ItemVersion(1),
            created: now, modified: now)
        item.content = content
        item.boundEmbeds = embeds
        item.state = state
        return item
    }

    private static func file(_ type: UTType, bytes: Int64 = 1000, state: ItemState = .active) -> Item {
        item(content: .file(type, byteCount: bytes), state: state)
    }

    private static func picture(of item: Item, attachments: [Item] = [], standard: Bool = true) -> RowPicture? {
        let list = RowList(showsPictures: standard, day: Calendar.current.startOfDay(for: now))
        return RowContent.make(for: item, look: .empty, catalogue: catalogue, list: list, attachments: attachments).picture
    }

    @Test func aStandardRowHasAPictureWhereACardHasASource() {
        let embed = BoundEmbed(text: "![[a.png]]", resolution: .missing)
        for item in [Self.file(.png), Self.file(.pdf), Self.file(.mpeg4Movie), Self.file(.zip), Self.item(embeds: [embed])] {
            #expect(Self.picture(of: item)?.item == item)
        }
    }

    @Test func aCompactRowAndACardHaveNone() {
        let image = Self.file(.png)
        #expect(Self.picture(of: image, standard: false) == nil)
        let card = RowContent.card(
            for: image, look: .empty, catalogue: Self.catalogue, list: RowList(showsPictures: true, day: .now), shape: CardShape())
        #expect(card.picture == nil, "a card draws its own picture")
    }

    @Test func anItemWithNothingToMakeAPictureFromHasNone() {
        #expect(Self.picture(of: Self.item()) == nil)
        #expect(Self.picture(of: Self.file(.png, bytes: 9 << 20)) == nil, "too large to fetch for a list")
        var bookmark = Self.item()
        bookmark.properties = [Property(key: "image_url", value: .string("https://example.com/a.png"))]
        #expect(Self.picture(of: bookmark) == nil, "a picture at a web address is never loaded for a row")
    }

    @Test func aBookmarkTakesItsAttachedImageAndNoOtherAttachment() {
        let bookmark = Self.item()
        let cover = Self.file(.jpeg)
        let picture = Self.picture(of: bookmark, attachments: [Self.file(.pdf), cover, Self.file(.png, state: .trashed)])
        #expect(picture?.attachments == [cover], "an image not in the bin; a document is no picture")
        #expect(Self.picture(of: bookmark, attachments: [Self.file(.pdf)]) == nil)
    }
}
