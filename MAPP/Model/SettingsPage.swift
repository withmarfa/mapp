import Foundation

/// A page of Settings, which the window shows in place of the list and the item page once the Settings row of the
/// sidebar is chosen.
nonisolated enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appearance, editor, sidebar, library, recentlyDeleted, about

    var id: Self { self }

    /// The pages as the list shows them, in groups.
    static let groups: [[SettingsPage]] = [[.appearance, .editor, .sidebar], [.library, .recentlyDeleted], [.about]]

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .editor: String(localized: "Editor")
        case .sidebar: String(localized: "Sidebar")
        case .library: String(localized: "Library")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .about: String(localized: "About")
        }
    }

    /// The one line under the page's heading.
    var summary: String {
        switch self {
        case .appearance: String(localized: "How text and lists look.")
        case .editor: String(localized: "How a page looks while you write.")
        case .sidebar: String(localized: "What the sidebar shows, and in what order.")
        case .library: String(localized: "Where your notes are kept.")
        case .recentlyDeleted: String(localized: "Items you’ve deleted. Restore them, or delete them for good.")
        case .about: String(localized: "The app, and the library it’s reading.")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .editor: "square.and.pencil"
        case .sidebar: "sidebar.left"
        case .library: "books.vertical"
        case .recentlyDeleted: "trash"
        case .about: "info.circle"
        }
    }
}
