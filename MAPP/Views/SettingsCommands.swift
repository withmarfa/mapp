import SwiftUI

/// A request made with no focused main window is consumed by the main window the command opens.
@Observable
final class SettingsRequest {
    var isPending = false
}

struct SettingsCommands: Commands {
    let request: SettingsRequest
    @FocusedValue(\.browser) private var browser
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…", systemImage: "gearshape") {
                if let browser {
                    browser.showSettings()
                } else {
                    request.isPending = true
                    openWindow(id: "main")
                }
            }
            .keyboardShortcut(",")
        }
    }
}
