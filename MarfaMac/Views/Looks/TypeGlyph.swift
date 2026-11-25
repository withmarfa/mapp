import MarfaIcons
import SwiftUI

/// The symbols the app draws for a type's icon in place of the SDK's choice, by icon id, so no item type is named here.
/// At the 10 to 12 points of a mark the SDK's `note.text` reads as a little calendar, and it has no symbol for the
/// others, whose Lucide artwork is a heavier line than the symbols round it.
nonisolated enum TypeSymbol {
    static let table: [String: String] = [
        "lucide:sticky-note": "doc.text",
        "lucide:file-image": "photo",
        "lucide:file-music": "music.note",
        "lucide:file-video-camera": "video",
        "lucide:disc-3": "opticaldisc",
        "lucide:scroll-text": "scroll",
        "lucide:signpost": "signpost.right",
    ]
}

/// A type's icon: the symbol `TypeSymbol` holds for it, otherwise what the SDK draws.
struct TypeGlyph: View {
    let id: String?

    var body: some View {
        if let symbol = id.flatMap({ TypeSymbol.table[$0] }) {
            Image(systemName: symbol)
        } else {
            TypeIcon(id: id)
        }
    }
}

/// A type's icon in its own tone, with nothing behind it: how a row, a page and a palette show a type's mark. A tile is
/// only a gallery cover with no picture and the Settings type page (`TypeTile`).
struct TonedGlyph: View {
    let id: String?
    var size: CGFloat = ChipLooks.defaults.chipMarkSize

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Image(typeGlyph: id)
            .resizable()
            .scaledToFit()
            .foregroundStyle(TypeTone(icon: id).ink(ChipLooks.current, for: scheme))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

extension Image {
    /// The image for a type's icon where the mark has to be an image, as `TypeGlyph` draws it.
    init(typeGlyph id: String?) {
        if let symbol = id.flatMap({ TypeSymbol.table[$0] }) {
            self.init(systemName: symbol)
        } else {
            self.init(typeIcon: id)
        }
    }
}
