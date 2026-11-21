import Foundation

/// A page of Settings: one of MAPP's own, or one of the Marfa's. The window lists a page only once it exists, so a later
/// piece adds its pages here and to the sidebar's groups, and nothing else.
nonisolated enum SettingsPage: Hashable, Sendable {
    case general, appearance, keyboard, lists, editor, connection
    case marfa(MarfaSettingsPage)

    static let overview = SettingsPage.marfa(.overview)
    static let recentlyDeleted = SettingsPage.marfa(.recentlyDeleted)

    /// MAPP's pages as the sidebar lists them, in groups split by space.
    static let mappGroups: [[SettingsPage]] = [[.general, .appearance, .keyboard], [.editor, .lists], [.connection]]
    /// The Marfa's pages, in groups.
    static let marfaGroups: [[SettingsPage]] = MarfaSettingsPage.groups.map { $0.map(SettingsPage.marfa) }

    static var all: [SettingsPage] { (mappGroups + marfaGroups).flatMap { $0 } }

    /// Whether the page is one of the Marfa's, which stands on the server and needs a permission.
    var marfaPage: MarfaSettingsPage? {
        if case .marfa(let page) = self { page } else { nil }
    }

    /// A name for tests and accessibility, which never changes with the language.
    var key: String {
        switch self {
        case .general: "general"
        case .appearance: "appearance"
        case .keyboard: "keyboard"
        case .lists: "lists"
        case .editor: "editor"
        case .connection: "connection"
        case .marfa(let page): page.rawValue
        }
    }

    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .appearance: String(localized: "Appearance")
        case .keyboard: String(localized: "Keyboard")
        case .lists: String(localized: "Lists")
        case .editor: String(localized: "Editor")
        case .connection: String(localized: "Connection")
        case .marfa(let page): page.title
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.pointed.fill"
        case .keyboard: "keyboard"
        case .lists: "list.bullet"
        case .editor: "square.and.pencil"
        case .connection: "antenna.radiowaves.left.and.right"
        case .marfa(let page): page.symbol
        }
    }

    var tone: SettingsTokens.Tone {
        switch self {
        case .general: .gray
        case .appearance: .blue
        case .keyboard: .indigo
        case .lists: .orange
        case .editor: .yellow
        case .connection: .green
        case .marfa(let page): page.tone
        }
    }

    /// The titles of the rows the page holds, which the sidebar's search finds the page by.
    var searchWords: [String] {
        switch self {
        case .general:
            [
                String(localized: "Start With"), String(localized: "Reopen Windows"), String(localized: "Open Items"),
                String(localized: "New Items Are"), String(localized: "Today and Yesterday"), String(localized: "Week Starts On"),
                String(localized: "Date Format"), String(localized: "Time Format"), String(localized: "Pictures from Websites"),
                String(localized: "Send Error Reports"), String(localized: "Reset MAPP’s Settings"),
            ]
        case .appearance:
            [
                String(localized: "Theme"), String(localized: "Accent"), String(localized: "Highlights"), String(localized: "Text Size"),
                String(localized: "Text Font"), String(localized: "Code Font"), String(localized: "Value Panels"),
                String(localized: "Palettes"), String(localized: "Title When Scrolling"), String(localized: "Toolbar Background When Scrolling"),
                String(localized: "Symbols on Subtypes"), String(localized: "Window Layout"), String(localized: "Sidebar"), String(localized: "List"),
            ]
        case .keyboard:
            [
                String(localized: "Shortcuts"), String(localized: "Export Shortcuts"), String(localized: "Import Shortcuts"),
                String(localized: "Restore Defaults"), String(localized: "In Any App"),
            ] + AnyAppCommand.allCases.map(\.title) + ShortcutCommand.all.map(\.title)
        case .lists:
            [String(localized: "Density"), String(localized: "Sort By"), String(localized: "Group By")]
        case .editor:
            [
                String(localized: "Page Width"), String(localized: "Standard Width"), String(localized: "Title Length"),
                String(localized: "Text Size"), String(localized: "Check Spelling While Typing"), String(localized: "Links"),
            ]
        case .connection:
            [
                String(localized: "Server"), String(localized: "Address"), String(localized: "Sign In"), String(localized: "Disconnect"),
                String(localized: "Downloaded Files"), String(localized: "Use Another Marfa"),
            ]
        case .marfa(let page): page.searchWords
        }
    }

    /// Whether `query` finds the page, by its name or by the title of a row it holds.
    func matches(_ query: String) -> Bool {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return true }
        return ([title] + searchWords).contains { $0.localizedStandardContains(query) }
    }
}

/// What a page's row in the sidebar shows at its trailing edge.
nonisolated enum SettingsBadge: Hashable, Sendable {
    case count(Int)
    case dot
}
