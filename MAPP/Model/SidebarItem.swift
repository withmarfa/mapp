import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    case allNotes
    case pinned
    /// A shortcut to one pinned item, distinct from the collection containing every pin.
    case pinnedItem(UUID)
    case folder(Folder.ID)
    case itemType(String)
    case project(UUID)
    case files
    case recentlyDeleted
    /// Marfa's types: a page of their own, in place of the list and the note, that holds no notes.
    case marfaTypes
}
