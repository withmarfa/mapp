import Foundation
import UniformTypeIdentifiers

/// Where a gallery card's picture can come from, decided from the item alone. Nothing here is fetched or drawn, so a
/// card says what it will try before any of it is asked for.
nonisolated enum CardPicture {
    /// What a file item is, as far as its picture goes.
    enum FileKind: Hashable, Sendable {
        /// Decoded by ImageIO, which reads any size down to the card's.
        case image
        /// A document's first page, from Quick Look.
        case pdf
        /// A frame of the video, from Quick Look.
        case video
        /// Whatever Quick Look has a thumbnail for.
        case other
    }

    enum Source: Hashable, Sendable {
        /// The item is a file: its own picture or thumbnail.
        case file(FileKind)
        /// The first image the item's text embeds.
        case embed
        /// An image file attached to the item, as a bookmark's saved cover is.
        case attached(ItemID)
    }

    /// The most files of one item tried as its picture.
    static let attachedLimit = 3

    /// The largest file fetched for a picture, so a grid of cards never downloads a large one: an image may be larger
    /// than the other kinds, since it is cut down as it is read.
    static func fetchLimit(_ kind: FileKind) -> Int64 { kind == .image ? 8 << 20 : 32 << 20 }

    static func kind(of type: UTType) -> FileKind {
        if type.conforms(to: .image) { .image }
        else if type.conforms(to: .pdf) { .pdf }
        else if type.conforms(to: .movie) || type.conforms(to: .video) { .video }
        else { .other }
    }

    /// The places an item's picture may come from, in the order they are tried. Empty when the app has none to make: an
    /// item with only a web address for a picture (`image_url`) is one, since a picture at a web address loads only when
    /// the person asks, never for a card. `attachments` are the items attached to it, in any state.
    static func sources(of item: Item, attachments: [Item]) -> [Source] {
        if case .file(let type, let byteCount) = item.content {
            let kind = kind(of: type)
            return byteCount <= fetchLimit(kind) ? [.file(kind)] : []
        }
        var sources: [Source] = item.boundEmbeds.isEmpty ? [] : [.embed]
        sources += attachedImages(of: attachments).prefix(attachedLimit).map { .attached($0.id) }
        return sources
    }

    /// The attached files that can be a picture: images not in the bin and small enough, the oldest first.
    static func attachedImages(of attachments: [Item]) -> [Item] {
        attachments
            .filter { file in
                guard file.state != .trashed, case .file(let type, let byteCount) = file.content else { return false }
                return type.conforms(to: .image) && byteCount <= fetchLimit(.image)
            }
            .sorted { ($0.created, $0.id.rawValue) < ($1.created, $1.id.rawValue) }
    }
}

/// What fills a card's picture area, from the view's choice of preview and what the item has. The picture is only what
/// the item can make: a card whose picture is not ready, or cannot be made, shows its `fallback` instead.
nonisolated enum CardFace: Hashable, Sendable {
    /// The item's picture or thumbnail.
    case picture
    /// The type's icon for a file with no picture of its own.
    case fileIcon
    /// The item's opening lines.
    case text
    /// The type's mark, quiet, for an item with no picture and no text.
    case placeholder

    static func of(preview: ViewCards.Preview, sources: [CardPicture.Source], isFile: Bool, text: String) -> CardFace {
        if preview.showsPicture, !sources.isEmpty { return .picture }
        return fallback(preview: preview, isFile: isFile, text: text)
    }

    /// What the card shows where it has no picture to show.
    static func fallback(preview: ViewCards.Preview, isFile: Bool, text: String) -> CardFace {
        if preview != .text, isFile { return .fileIcon }
        if preview != .picture, !text.isEmpty { return .text }
        return .placeholder
    }
}
