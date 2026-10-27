import Foundation

/// What the line under a row's preview says about the item, as separate pieces. It leaves out whatever the list
/// already says, so a list of one type names no type, and the Inbox does not name itself.
nonisolated struct ItemMeta: Hashable, Sendable {
    struct Piece: Hashable, Sendable, Identifiable {
        let icon: RowIcon
        let label: String
        var id: String { "\(icon)" + label }
    }

    var pieces: [Piece]

    var isEmpty: Bool { pieces.isEmpty }

    /// What a list tells about itself: whether it holds several types, and whether it is the Inbox.
    struct Context: Hashable, Sendable {
        var mixesTypes = false
        var isInbox = false
    }

    @MainActor
    static func make(for item: Item, in library: any ItemLibrary, context: Context) -> ItemMeta {
        var pieces: [Piece] = []
        if context.mixesTypes {
            pieces.append(Piece(
                icon: .type(library.catalogue.icon(for: item.type)),
                label: library.catalogue.label(for: item.type)))
        }
        // Feed items wait in the Inbox, which the Inbox's own list need not say.
        if item.tier == .feed, !context.isInbox {
            pieces.append(Piece(icon: .symbol("tray"), label: String(localized: "Inbox")))
        }
        return ItemMeta(pieces: pieces)
    }
}
