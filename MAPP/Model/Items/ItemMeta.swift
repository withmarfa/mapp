import Foundation

/// What the line under a row's preview says about the item, as separate pieces. It leaves out whatever the list
/// already says, so a list of one type names no type. It never names the tier: the Inbox is a place to look, not a
/// property of the item.
nonisolated struct ItemMeta: Hashable, Sendable {
    struct Piece: Hashable, Sendable, Identifiable {
        let icon: RowIcon
        let label: String
        var id: String { "\(icon)" + label }
    }

    var pieces: [Piece]

    var isEmpty: Bool { pieces.isEmpty }

    /// What a list tells about itself: whether it holds several types.
    struct Context: Hashable, Sendable {
        var mixesTypes = false
    }

    @MainActor
    static func make(for item: Item, in library: any ItemLibrary, context: Context) -> ItemMeta {
        var pieces: [Piece] = []
        if context.mixesTypes {
            pieces.append(Piece(
                icon: .type(library.catalogue.icon(for: item.type)),
                label: library.catalogue.label(for: item.type)))
        }
        return ItemMeta(pieces: pieces)
    }
}
