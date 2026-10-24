import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    /// The items edited most recently, as many as `ItemLibrary.recentLimit`.
    case recents
    case allNotes
    case favorites
    /// A shortcut to one favorite item, distinct from the collection containing every favorite.
    case favoriteItem(ItemID)
    case folder(ItemID)
    case itemType(String)
    case collection(ItemID)
    case collections
    case sources
    case source(String)
    case files
    case recentlyDeleted
}
