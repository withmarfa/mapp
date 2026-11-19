import SwiftUI

/// The Help menu, after the system's search field: MAPP's own help, its keyboard shortcuts and what is new, then Marfa's
/// documentation and Report a Problem…. The links open in the browser, so a Mac with no network has nothing to handle here.
struct HelpCommands: Commands {
    let shortcuts: KeyboardShortcutsModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @FocusedValue(\.browser) private var browser

    var body: some Commands {
        CommandGroup(replacing: .help) {
            ForEach(HelpItem.allCases, id: \.self) { item in
                if item.startsGroup { Divider() }
                Button(item.title, systemImage: item.systemImage) {
                    item.perform(shortcuts: shortcuts, browser: browser, openWindow: openWindow, openURL: openURL)
                }
            }
        }
    }
}

extension HelpItem {
    /// Opens the address in the browser, or the window of shortcuts. The menu bar is read as the person left it, before the
    /// new window takes the keyboard, and only from a window with a browser (`browser`), the one whose menus are whole.
    func perform(shortcuts: KeyboardShortcutsModel, browser: Browser?, openWindow: OpenWindowAction, openURL: OpenURLAction) {
        if let url {
            openURL(url)
        } else {
            shortcuts.capture(from: browser)
            openWindow(id: KeyboardShortcutsView.windowID)
        }
    }
}

/// The window that lists the app's menu commands with their keys, grouped by menu.
struct KeyboardShortcutsView: View {
    static let windowID = "keyboardShortcuts"
    @Environment(KeyboardShortcutsModel.self) private var shortcuts

    var body: some View {
        List {
            ForEach(shortcuts.list.sections) { section in
                Section(section.title) {
                    ForEach(section.rows) { row in
                        LabeledContent(row.title) {
                            Text(verbatim: row.keys).monospaced().foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .overlay {
            if shortcuts.list.isEmpty { ContentUnavailableView("No Shortcuts", systemImage: "keyboard") }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 320, idealHeight: 560)
        .accessibilityIdentifier("KeyboardShortcuts")
    }
}
