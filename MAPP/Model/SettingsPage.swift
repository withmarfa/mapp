import Foundation

/// A page of Settings, which the window shows in place of the list and the item page once the Settings row of the
/// sidebar is chosen.
nonisolated enum SettingsPage: String, CaseIterable, Identifiable, Hashable, Sendable {
    case appearance, editor, sidebar, library, thisMarfa, recentlyDeleted, about

    var id: Self { self }

    /// The pages as the list shows them, in groups.
    static let groups: [[SettingsPage]] = [[.appearance, .editor, .sidebar], [.library, .thisMarfa, .recentlyDeleted], [.about]]

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .editor: String(localized: "Editor")
        case .sidebar: String(localized: "Sidebar")
        case .library: String(localized: "Library")
        case .thisMarfa: String(localized: "This Marfa")
        case .recentlyDeleted: String(localized: "Recently Deleted")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .editor: "square.and.pencil"
        case .sidebar: "sidebar.left"
        case .library: "books.vertical"
        case .thisMarfa: "server.rack"
        case .recentlyDeleted: "trash"
        case .about: "info.circle"
        }
    }
}
