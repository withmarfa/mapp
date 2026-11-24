import SwiftUI

/// A page of its own inside a page, such as a key's own page: pushed, so Back returns. `id` names it for the page that
/// opened it; `title` is what the toolbar shows.
struct SettingsSubpage: Hashable, Sendable {
    let id: String
    let title: String

    init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

@MainActor protocol SettingsSubpageNavigation: AnyObject, Sendable {
    func push(_ subpage: SettingsSubpage)
    func back()
}

/// Keeps the environment value stable as the window's history changes.
nonisolated struct SettingsNavigationActions: Equatable, Sendable {
    let navigation: any SettingsSubpageNavigation

    static func == (left: Self, right: Self) -> Bool { left.navigation === right.navigation }

    @MainActor func push(_ subpage: SettingsSubpage) { navigation.push(subpage) }
    @MainActor func back() { navigation.back() }
}

extension EnvironmentValues {
    @Entry var settingsNavigation: SettingsNavigationActions?
    /// The sub-page the window shows, or nil where the page shows itself.
    @Entry var settingsSubpage: SettingsSubpage?
}
