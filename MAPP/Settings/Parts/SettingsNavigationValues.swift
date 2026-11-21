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
    /// Pushes a sub-page on the window's history; Back returns to the page that pushed it.
    @Entry var settingsPush: (SettingsSubpage) -> Void = { _ in }
    /// Goes back one place, as Back does, such as when the thing a sub-page shows has gone.
    @Entry var settingsBack: () -> Void = {}
    /// The sub-page the window shows, or nil where the page shows itself.
    @Entry var settingsSubpage: SettingsSubpage?
}
