import Foundation

/// A view saved on the server (Marfa's `system.view`): a named list of items that every app shows. MAPP reads its
/// title and the items it lists, and writes none.
nonisolated struct LibraryView: Identifiable, Hashable, Sendable {
    let id: ItemID
    var title: String
    /// Changes with every change to the view, so one whose query changed but not its title still differs.
    var version: Int64 = 0

    /// By title, as the sidebar lists them, with the id settling two of one title.
    static func ordered(_ views: [LibraryView]) -> [LibraryView] {
        views.sorted {
            switch $0.title.localizedStandardCompare($1.title) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.id.rawValue < $1.id.rawValue
            }
        }
    }
}
