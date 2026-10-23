import Foundation

extension ItemLibrary {
    /// The collection a list names an item by: the ancestor just below the top of its chain of parents
    /// (`child-of`), as the sidebar's Collections section shows them, so a ticket under an epic under Marfa under
    /// WithMarfa is in Marfa. An item whose only ancestor is the top is in the top; one with no parent is in none.
    /// No type is special, so it reads the same on any Marfa.
    func collection(of item: Item) -> Item? {
        var chain: [Item] = []
        var current = item
        var visited: Set<ItemID> = [item.id]
        while let parent = current.parentID, visited.insert(parent).inserted, let next = self.item(parent), next.state == .active {
            chain.append(next)
            current = next
        }
        return chain.count >= 2 ? chain.dropLast().last : chain.last
    }
}

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

    /// What a list tells about itself: whether it holds several types, the collection it lists (which its rows need
    /// not name again), and whether it mixes places.
    struct Context: Hashable, Sendable {
        var mixesTypes = false
        var collection: ItemID?
        var showsPlaces = false
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
        if let collection = library.collection(of: item), collection.id != context.collection {
            pieces.append(Piece(symbol: TypeSymbol.name(for: collection.type, in: library.catalogue), label: collection.title))
        }
        if context.showsPlaces, let folder = library.folder(of: item), !pieces.contains(where: { $0.label == folder.name }) {
            pieces.append(Piece(symbol: "folder", label: folder.name))
        }
        // A server's feed items wait in the Inbox; a folder's loose notes are the Inbox, which says nothing.
        if item.tier == .feed, !context.isInbox {
            pieces.append(Piece(symbol: "tray", label: String(localized: "Inbox")))
        }
        return ItemMeta(pieces: pieces)
    }
}
