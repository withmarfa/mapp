import Foundation

/// A page of Settings: one of MAPP's own, or one of the Marfa's. The window lists a page only once it exists, so a later
/// piece adds its pages here and to the sidebar's groups, and nothing else.
nonisolated enum SettingsPage: Hashable, Sendable {
    case appearance, lists, editor, connection
    case marfa(MarfaSettingsPage)

    static let overview = SettingsPage.marfa(.overview)
    static let recentlyDeleted = SettingsPage.marfa(.recentlyDeleted)

    /// MAPP's pages as the sidebar lists them, in groups split by space.
    static let mappGroups: [[SettingsPage]] = [[.appearance], [.editor, .lists], [.connection]]
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
        case .appearance: "appearance"
        case .lists: "lists"
        case .editor: "editor"
        case .connection: "connection"
        case .marfa(let page): page.rawValue
        }
    }

    var title: String {
        switch self {
        case .appearance: String(localized: "Appearance")
        case .lists: String(localized: "Lists")
        case .editor: String(localized: "Editor")
        case .connection: String(localized: "Connection")
        case .marfa(let page): page.title
        }
    }

    var symbol: String {
        switch self {
        case .appearance: "paintbrush.pointed.fill"
        case .lists: "list.bullet"
        case .editor: "square.and.pencil"
        case .connection: "antenna.radiowaves.left.and.right"
        case .marfa(let page): page.symbol
        }
    }

    var tone: SettingsTokens.Tone {
        switch self {
        case .appearance: .blue
        case .lists: .orange
        case .editor: .yellow
        case .connection: .green
        case .marfa(let page): page.tone
        }
    }

    /// The titles of the rows the page holds, which the sidebar's search finds the page by.
    var searchWords: [String] {
        switch self {
        case .appearance:
            [
                String(localized: "Base Text Size"), String(localized: "Value Panels"), String(localized: "Palettes"),
                String(localized: "Show Title When Scrolling"), String(localized: "Show Toolbar Background When Scrolling"),
                String(localized: "Default Column Widths"), String(localized: "Date Format"),
            ]
        case .lists:
            [String(localized: "Density"), String(localized: "Sort"), String(localized: "Group"), String(localized: "Open Items In")]
        case .editor:
            [
                String(localized: "Page Width"), String(localized: "Standard Width"), String(localized: "Title Length"),
                String(localized: "Text Size"), String(localized: "Check Spelling While Typing"), String(localized: "Links"),
                String(localized: "Remote Pictures"),
            ]
        case .connection:
            [
                String(localized: "Server"), String(localized: "Address"), String(localized: "Sign In"), String(localized: "Disconnect"),
                String(localized: "Downloaded files"), String(localized: "Send Error Reports"), String(localized: "Use a different server"),
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
