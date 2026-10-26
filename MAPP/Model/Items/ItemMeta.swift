import Foundation

/// What the line under a row's preview says about the item, as separate pieces. It leaves out whatever the list
/// already says, so a list of one type names no type, and the Inbox does not name itself.
nonisolated struct ItemMeta: Hashable, Sendable {
    struct Piece: Hashable, Sendable, Identifiable {
        let symbol: String
        let label: String
        var id: String { symbol + label }
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
                symbol: TypeSymbol.name(for: item.type, in: library.catalogue),
                label: TypeSymbol.label(for: item.type, in: library.catalogue)))
        }
        // Feed items wait in the Inbox, which the Inbox's own list need not say.
        if item.tier == .feed, !context.isInbox {
            pieces.append(Piece(symbol: "tray", label: String(localized: "Inbox")))
        }
        return ItemMeta(pieces: pieces)
    }
}
