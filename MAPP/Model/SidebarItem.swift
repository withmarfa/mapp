import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    /// The items edited most recently, as many as `ItemLibrary.recentLimit`.
    case recents
    case allItems
    case favorites
    /// A shortcut to one favorite item, distinct from the collection containing every favorite.
    case favoriteItem(ItemID)
    case itemType(String)
    case collection(ItemID)
    case collections
    case sources
    case source(String)
    case files
    /// A view saved on the server, listing what the copy holds of its items.
    case view(ItemID)

    /// `allItems` keeps the key it was stored under (`storageKey` names a place's saved columns and density by it).
    private enum CodingKeys: String, CodingKey {
        case inbox, recents, allItems = "allNotes", favorites, favoriteItem, itemType, collection, collections
        case sources, source, files, view
    }
}

nonisolated extension SidebarItem {
    /// The place as the defaults name it, for what this Mac keeps for each place: its columns and its density.
    var storageKey: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }
}
