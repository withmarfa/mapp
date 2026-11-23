import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// What fills a gallery card, decided from the item alone, and what the card says under it.
@MainActor
struct CardArtTests {
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)
    private static let catalogue = LookFixture.catalogue()

    private static func item(
        title: String? = "Title", preview: String = "", content: Item.Content = .markdown, state: ItemState = .active,
        created: Date = now, embeds: [BoundEmbed] = []
    ) -> Item {
        var item = Item(
            id: .mint(), type: TypeID("core.note"), title: title ?? "", name: title, titleRule: .firstLine, preview: preview,
            version: ItemVersion(1), created: created, modified: created)
        item.content = content
        item.state = state
        item.boundEmbeds = embeds
        return item
    }

    private static func file(_ type: UTType, bytes: Int64 = 1000, state: ItemState = .active, created: Date = now) -> Item {
        item(title: "file", content: .file(type, byteCount: bytes), state: state, created: created)
    }

    private static func face(_ item: Item, _ preview: ViewCards.Preview = .pictureOrText, attachments: [Item] = []) -> CardFace {
        CardFace.of(preview: preview, sources: CardPicture.sources(of: item, attachments: attachments), isFile: item.isFile, text: item.preview)
    }

    // MARK: A picture, text, or neither

    @Test func anItemWithOnlyTextShowsItsOpeningLines() {
        #expect(Self.face(Self.item(preview: "Twelve walks, one a month")) == .text)
    }

    @Test func anItemWithNeitherShowsThePlaceholder() {
        #expect(Self.face(Self.item()) == .placeholder)
    }

    @Test func aPictureOnlyPreviewNeverShowsText() {
        #expect(Self.face(Self.item(preview: "Words"), .picture) == .placeholder)
    }

    @Test func aTextOnlyPreviewNeverShowsAPicture() {
        let image = Self.file(.png)
        #expect(Self.face(image, .text) == .placeholder, "a file's own text is its kind line, which `text` alone does not hide")
        let note = Self.item(preview: "Words", embeds: [BoundEmbed(text: "![[a.png]]", resolution: .missing)])
        #expect(Self.face(note, .text) == .text)
    }

    @Test func anItemsEmbeddedImageIsItsPicture() {
        let note = Self.item(preview: "Words", embeds: [BoundEmbed(text: "![[a.png]]", resolution: .missing)])
        #expect(CardPicture.sources(of: note, attachments: []) == [.embed])
        #expect(Self.face(note) == .picture)
        #expect(Self.face(note, .none) == .text)
    }

    // MARK: Files

    @Test func eachKindOfFileHasItsOwnSource() {
        #expect(CardPicture.sources(of: Self.file(.pdf), attachments: []) == [.file(.pdf)])
        #expect(CardPicture.sources(of: Self.file(.png), attachments: []) == [.file(.image)])
        #expect(CardPicture.sources(of: Self.file(.mpeg4Movie), attachments: []) == [.file(.video)])
        #expect(CardPicture.sources(of: Self.file(.zip), attachments: []) == [.file(.other)])
        for type in [UTType.pdf, .png, .mpeg4Movie, .zip] { #expect(Self.face(Self.file(type)) == .picture) }
    }

    @Test func aFileTooLargeToFetchShowsItsTypesIcon() {
        #expect(Self.face(Self.file(.png, bytes: 9 << 20)) == .fileIcon)
        #expect(Self.face(Self.file(.pdf, bytes: 33 << 20)) == .fileIcon)
        #expect(CardPicture.sources(of: Self.file(.pdf, bytes: 20 << 20), attachments: []) == [.file(.pdf)], "a document may be larger than an image")
    }

    @Test func aFileWithoutPictureShowsItsIconEvenWhenTheViewWantsOnlyAPicture() {
        #expect(CardFace.fallback(preview: .picture, isFile: true, text: "") == .fileIcon)
        #expect(CardFace.fallback(preview: .pictureOrText, isFile: true, text: "PDF, 4 KB") == .fileIcon)
    }

    // MARK: A bookmark's picture

    @Test func aBookmarkWithAnAttachedPictureShowsIt() {
        let bookmark = Self.item(title: "A reading desk")
        let cover = Self.file(.jpeg)
        #expect(CardPicture.sources(of: bookmark, attachments: [cover]) == [.attached(cover.id)])
        #expect(Self.face(bookmark, attachments: [cover]) == .picture)
    }

    @Test func aBookmarkWithOnlyAPictureAddressShowsNoPicture() {
        var bookmark = Self.item(title: "A reading desk")
        bookmark.properties = [Property(key: "image_url", value: .string("https://example.com/a.png"))]
        #expect(CardPicture.sources(of: bookmark, attachments: []).isEmpty, "a picture at a web address loads only when asked")
        #expect(Self.face(bookmark) == .placeholder)
    }

    @Test func onlyAnImageNotInTheBinAndSmallEnoughIsAnAttachedPicture() {
        let bookmark = Self.item()
        let binned = Self.file(.png, state: .trashed)
        let document = Self.file(.pdf)
        let huge = Self.file(.png, bytes: 9 << 20)
        #expect(CardPicture.sources(of: bookmark, attachments: [binned, document, huge]).isEmpty)
    }

    @Test func theOldestAttachedImageComesFirst() {
        let older = Self.file(.png, created: Self.now - 100)
        let newer = Self.file(.png, created: Self.now)
        #expect(CardPicture.sources(of: Self.item(), attachments: [newer, older]) == [.attached(older.id), .attached(newer.id)])
    }

    @Test func anEmbeddedImageIsTriedBeforeAnAttachedOne() {
        let cover = Self.file(.png)
        let note = Self.item(embeds: [BoundEmbed(text: "![[a.png]]", resolution: .missing)])
        #expect(CardPicture.sources(of: note, attachments: [cover]) == [.embed, .attached(cover.id)])
    }

    // MARK: What a card says

    private static func said(_ item: Item) -> RowContent {
        RowContent.card(
            for: item, look: .empty, catalogue: catalogue, list: RowList(day: Calendar.current.startOfDay(for: now)), shape: CardShape())
    }

    @Test func aTitleIsKeptWholeWhateverItsLength() {
        let one = "Oak worktop"
        let three = "The cliff path that teaches you to slow down, an evening on the Jurassic Coast, in the long light of late September"
        #expect(Self.said(Self.item(title: one)).title == one)
        #expect(Self.said(Self.item(title: three)).title == three, "the card clips it to two lines and keeps room for two")
    }

    @Test func anUntitledItemSaysUntitled() {
        let untitled = Self.item(title: nil)
        #expect(Self.said(untitled).title == untitled.displayTitle)
        #expect(!Self.said(untitled).title.isEmpty)
    }

    @Test func theShapesAreFourToThreeSquareAndTwoToThree() {
        #expect(ViewCards.Shape.standard.aspect == 4.0 / 3.0)
        #expect(ViewCards.Shape.square.aspect == 1)
        #expect(ViewCards.Shape.cover.aspect == 2.0 / 3.0)
        #expect(ViewCards().shape == .standard)
        let cards = ViewCards(shape: .cover)
        let read = try? JSONDecoder().decode(ViewCards.self, from: JSONEncoder().encode(cards))
        #expect(read == cards)
    }
}
