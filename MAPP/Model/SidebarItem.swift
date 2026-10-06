import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    case allNotes
    case favorites
    /// A shortcut to one favorite item, distinct from the collection containing every favorite.
    case favoriteItem(ItemID)
    case folder(ItemID)
    case itemType(String)
    case project(ItemID)
    case files
    case recentlyDeleted
    /// Marfa's types: a page of their own, in place of the list and the note, that holds no notes.
    case marfaTypes
}
