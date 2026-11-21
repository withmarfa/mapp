import SwiftUI

/// Where the Settings window is, and where Back and Forward go: a history of pages and the sub-pages pushed on them. The
/// app holds one, so every route that opens Settings names a page in the same window.
@Observable @MainActor final class SettingsNavigation {
    struct Place: Hashable {
        var page: SettingsPage
        var subpage: SettingsSubpage?
    }

    private(set) var places = [Place(page: .appearance)]
    private(set) var index = 0

    var current: Place { places[index] }
    var page: SettingsPage { current.page }
    var canGoBack: Bool { index > 0 }
    var canGoForward: Bool { index < places.count - 1 }

    /// What the toolbar shows: the sub-page's name where one is shown, otherwise the page's.
    var title: String { current.subpage?.title ?? current.page.title }

    /// Shows `page`. A page already shown stays as it is; any other is a new place, and what Forward held is dropped.
    func show(_ page: SettingsPage) {
        guard current != Place(page: page) else { return }
        push(Place(page: page))
    }

    /// Opens `subpage` on the page shown.
    func push(_ subpage: SettingsSubpage) {
        guard current.subpage != subpage else { return }
        push(Place(page: current.page, subpage: subpage))
    }

    func back() {
        if canGoBack { index -= 1 }
    }

    func forward() {
        if canGoForward { index += 1 }
    }

    private func push(_ place: Place) {
        places.removeSubrange((index + 1)...)
        places.append(place)
        index += 1
    }
}

/// Opens the Settings window: the one the app holds, at a page. A route that has a page to show names it; one that has
/// none brings the window forward where it was.
@Observable @MainActor final class SettingsLauncher {
    static let windowID = "settings"

    let navigation = SettingsNavigation()
    /// Opens the window, or brings it forward. The scene's own action, handed over by whichever view has it first.
    @ObservationIgnored var open: () -> Void = {}

    func show(_ page: SettingsPage? = nil) {
        if let page { navigation.show(page) }
        open()
    }
}

extension FocusedValues {
    /// The navigation of the Settings window while it is key, which the Back and Forward commands move.
    @Entry var settingsNavigation: SettingsNavigation?
}

/// MAPP > Settings…, which opens the window. Back and Forward (⌘[ and ⌘]) are the View menu's own, which move through the
/// Settings window's pages while it is key (`AppCommands`).
struct SettingsCommands: Commands {
    let launcher: SettingsLauncher
    let shortcuts: ShortcutBindings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                launcher.open = { openWindow(id: SettingsLauncher.windowID) }
                launcher.show()
            }
            .shortcut(.settings, shortcuts)
        }
    }
}
