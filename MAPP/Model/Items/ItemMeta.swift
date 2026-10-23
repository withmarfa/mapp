import Foundation

extension ItemLibrary {
    /// The nearest project above the item, following the parent each item holds (`child-of`). Nil for an item
    /// outside every project.
    func project(of item: Item) -> Item? {
        var current = item
        var visited: Set<ItemID> = [item.id]
        while let parent = current.edgesOut.lazy.compactMap({ edge -> ItemID? in
            guard edge.type == "child-of", case .item(let id) = edge.target else { return nil }
            return id
        }).first, visited.insert(parent).inserted, let next = self.item(parent) {
            if next.type == .project || catalogue.isSubtype(next.type, ofAnyOf: [.project]) { return next }
            current = next
        }
        return nil
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

    /// What a list tells about itself: whether it holds several types, the project it lists (which its rows need
    /// not name again), and whether it mixes places.
    struct Context: Hashable, Sendable {
        var mixesTypes = false
        var project: ItemID?
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
        if let project = library.project(of: item), project.id != context.project {
            pieces.append(Piece(symbol: "folder", label: project.title))
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
