import SwiftUI

/// An item's window tells the notices too, and has no browser, so a notice's way to Settings opens the Settings window.
struct ItemWindowNotices: ViewModifier {
    let notices: Notices
    let launcher: SettingsLauncher
    @Environment(\.openWindow) private var openWindow

    func body(content: Content) -> some View {
        content
            .onAppear { launcher.open = { openWindow(id: SettingsLauncher.windowID) } }
            .notices(notices) { launcher.show($0) }
    }
}
