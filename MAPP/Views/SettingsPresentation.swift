import Observation
import SwiftUI

/// Settings belongs to one main window; its browser and editor state are retained while Settings is shown.
@Observable
final class SettingsPresentation {
    var isPresented = false
    var pane: SettingsPane? = .appearance
    var query = ""

    var matchingPanes: [SettingsPane] {
        SettingsPane.allCases.filter { $0.matches(query) }
    }

    var displayedPane: SettingsPane? {
        guard let pane, matchingPanes.contains(pane) else { return matchingPanes.first }
        return pane
    }

    var title: String { displayedPane?.title ?? String(localized: "Settings") }

    func show() { isPresented = true }

    /// Opens Settings at a pane, whatever was searched for before.
    func show(_ pane: SettingsPane) {
        query = ""
        self.pane = pane
        isPresented = true
    }
    func close() { isPresented = false }
}

/// A request made with no focused main window is consumed by the main window the command opens.
@Observable
final class SettingsRequest {
    var isPending = false
}

extension FocusedValues {
    @Entry var settingsPresentation: SettingsPresentation?
}

enum SettingsPane: String, CaseIterable, Identifiable {
    case appearance, editor, library, marfa, about

    var id: Self { self }

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .editor: String(localized: "Editor")
        case .library: String(localized: "Library")
        case .marfa: String(localized: "Marfa")
        case .about: String(localized: "About")
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintpalette"
        case .editor: "square.and.pencil"
        case .library: "folder"
        case .marfa: "server.rack"
        case .about: "info.circle"
        }
    }

    private var searchTerms: String {
        switch self {
        case .appearance: String(localized: "Base Text Size Font Sidebar Sort By Group by Date List Preview Notes List")
        case .editor: String(localized: "Page Width Standard Full Width Reading Width Text Size Check Spelling While Typing")
        case .library: String(localized: "Notes Folder Change Show in Finder Recently Deleted Empty Now Delete")
        case .marfa: String(localized: "Marfa Server Address Sign In Switch Try Again Disconnect Offline Sync Changes Waiting")
        case .about: String(localized: "MAPP Version Build")
        }
    }

    func matches(_ query: String) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace)
        let text = title + " " + searchTerms
        return words.allSatisfy { text.localizedStandardContains(String($0)) }
    }
}

struct SettingsCommands: Commands {
    let request: SettingsRequest
    @FocusedValue(\.settingsPresentation) private var settings
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                if let settings {
                    settings.show()
                } else {
                    request.isPending = true
                    openWindow(id: "main")
                }
            }
            .keyboardShortcut(",")
        }
    }
}
