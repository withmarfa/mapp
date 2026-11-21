import SwiftUI

/// The Help menu, after the system's search field: MAPP's own help, its keyboard shortcuts and what is new, then Marfa's
/// documentation and Report a Problem…. The links open in the browser, so a Mac with no network has nothing to handle here.
/// Keyboard Shortcuts opens Settings at the Keyboard page.
struct HelpCommands: Commands {
    let launcher: SettingsLauncher
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL

    var body: some Commands {
        CommandGroup(replacing: .help) {
            ForEach(HelpItem.allCases, id: \.self) { item in
                if item.startsGroup { Divider() }
                Button(item.title, systemImage: item.systemImage) {
                    item.perform(openSettings: { page in
                        launcher.open = { openWindow(id: SettingsLauncher.windowID) }
                        launcher.show(page)
                    }, openURL: openURL)
                }
            }
        }
    }
}

extension HelpItem {
    /// Opens the address in the browser, or the Settings page the item names.
    func perform(openSettings: (SettingsPage) -> Void, openURL: OpenURLAction) {
        if let url {
            openURL(url)
        } else {
            openSettings(.keyboard)
        }
    }
}
