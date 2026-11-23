import Foundation

/// The files attached to each item of a gallery, read once for the place and handed to each card as a plain value, so a
/// card's body reads no library: a link that changes anywhere changes only the cards whose own attachments changed.
@MainActor
enum CardAttachments {
    /// The attached items of every item that can have a picture from them. A file has none, and a view whose cards show
    /// no picture needs none.
    static func of(_ items: [Item], in library: any ItemLibrary, showsPicture: Bool) -> [ItemID: [Item]] {
        guard showsPicture else { return [:] }
        var found: [ItemID: [Item]] = [:]
        for item in items where !item.isFile {
            let attached = of(item, in: library)
            if !attached.isEmpty { found[item.id] = attached }
        }
        return found
    }

    static func of(_ item: Item, in library: any ItemLibrary) -> [Item] {
        item.isFile ? [] : library.attachments(of: item.id).compactMap { library.item($0) }
    }
}
