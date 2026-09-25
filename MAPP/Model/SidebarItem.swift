import Foundation

nonisolated enum SidebarItem: Hashable, Codable {
    case inbox
    case allNotes
    case pinned
    case folder(Folder.ID)
    case recentlyDeleted
}
