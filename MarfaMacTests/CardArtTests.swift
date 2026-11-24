import Foundation
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// What fills a gallery card is decided from the item alone: a picture at a web address is never fetched unasked, and a
/// binned or oversized attachment is never the picture.
@MainActor
struct CardArtTests {
    private static let now = Date(timeIntervalSince1970: 1_794_000_000)

    private static func item(title: String? = "Title") -> Item {
        Item(
            id: .mint(), type: TypeID("core.note"), title: title ?? "", name: title, titleRule: .firstLine, preview: "",
            version: ItemVersion(1), created: now, modified: now)
    }

    private static func file(_ type: UTType, bytes: Int64 = 1000, state: ItemState = .active) -> Item {
        var file = item(title: "file")
        file.content = .file(type, byteCount: bytes)
        file.state = state
        return file
    }

    @Test func aBookmarkWithOnlyAPictureAddressShowsNoPicture() {
        var bookmark = Self.item(title: "A reading desk")
        bookmark.properties = [Property(key: "image_url", value: .string("https://example.com/a.png"))]
        #expect(CardPicture.sources(of: bookmark, attachments: []).isEmpty, "a picture at a web address loads only when asked")
        let face = CardFace.of(
            preview: .pictureOrText, sources: CardPicture.sources(of: bookmark, attachments: []), isFile: bookmark.isFile, text: bookmark.preview)
        #expect(face == .placeholder)
    }

    @Test func onlyAnImageNotInTheBinAndSmallEnoughIsAnAttachedPicture() {
        let bookmark = Self.item()
        let binned = Self.file(.png, state: .trashed)
        let document = Self.file(.pdf)
        let huge = Self.file(.png, bytes: 9 << 20)
        #expect(CardPicture.sources(of: bookmark, attachments: [binned, document, huge]).isEmpty)
        let kept = Self.file(.png)
        #expect(CardPicture.sources(of: bookmark, attachments: [binned, kept]) == [.attached(kept.id)])
    }
}
