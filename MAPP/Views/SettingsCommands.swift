import SwiftUI

/// A request made with no focused main window is consumed by the main window the command opens.
@Observable
final class SettingsRequest {
    var isPending = false
    /// The page the request asked for; nil keeps the page shown last.
    var page: SettingsPage?

    /// Shows Settings in `browser`'s window, or in a main window opened for it where the window in front has no
    /// browser, as an item's window has none.
    func show(_ page: SettingsPage? = nil, in browser: Browser?, openWindow: OpenWindowAction) {
        if let browser {
            browser.showSettings(page)
        } else {
            self.page = page
            isPending = true
            openWindow(id: "main")
        }
    }
}

struct SettingsCommands: Commands {
    let request: SettingsRequest
    @FocusedValue(\.browser) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                request.show(in: browser, openWindow: openWindow)
            }
            .keyboardShortcut(",")
        }
    }
}

/// An item's window tells the notices too, and has no browser, so a notice's way to Settings opens a main window.
struct ItemWindowNotices: ViewModifier {
    let notices: Notices
    let settingsRequest: SettingsRequest
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content.notices(notices) { settingsRequest.show($0, in: nil, openWindow: openWindow) }
    }
}
