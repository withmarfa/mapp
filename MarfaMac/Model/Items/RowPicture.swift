import Foundation

/// What a Standard row needs to show a small picture of its item: the item and the image files attached to it, which are
/// the places a gallery card's picture comes from (`CardPicture`). It is decided once, with the row's content
/// (`RowContent.picture`), so the row only draws it: a row whose item has no place to get one from has none and keeps its
/// height.
nonisolated struct RowPicture: Hashable, Sendable {
    let item: Item
    /// The attached image files its picture may be (`CardPicture.attachedImages`), the oldest first.
    let attachments: [Item]

    /// The most files of an item a row asks for, which are the ones a card tries.
    static let attachedLimit = CardPicture.attachedLimit

    /// Nil unless the list shows pictures and `CardPicture` has a source for the item. `attachments` are the items
    /// attached to it, in any state.
    static func of(_ item: Item, attachments: [Item], in list: RowList) -> RowPicture? {
        guard list.showsPictures else { return nil }
        return of(item, attachments: attachments)
    }

    static func of(_ item: Item, attachments: [Item]) -> RowPicture? {
        guard !CardPicture.sources(of: item, attachments: attachments).isEmpty else { return nil }
        return RowPicture(item: item, attachments: Array(CardPicture.attachedImages(of: attachments).prefix(attachedLimit)))
    }
}
