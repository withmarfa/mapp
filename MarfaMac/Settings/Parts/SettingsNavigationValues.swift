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

extension EnvironmentValues {
    /// The window's history, shared by pages that open or leave a sub-page.
    @Entry var settingsNavigation: SettingsNavigation?
    /// The sub-page the window shows, or nil where the page shows itself.
    @Entry var settingsSubpage: SettingsSubpage?
}
