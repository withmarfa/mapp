import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    case allNotes
    case pinned
    case folder(Folder.ID)
    case recentlyDeleted
    /// Marfa's types: a page of their own, in place of the list and the note, that holds no notes.
    case marfaTypes
}
