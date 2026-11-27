import Foundation

/// A routable page of Settings, including pages opened from a sidebar entry.
nonisolated enum SettingsPage: CaseIterable, Hashable, Sendable {
    case general, appearance, keyboard, lists, editor, layouts, search, connection
    case marfa(MarfaSettingsPage)

    static let overview = SettingsPage.marfa(.overview)
    static let account = SettingsPage.marfa(.account)
    static let apps = SettingsPage.marfa(.apps)
    static let keys = SettingsPage.marfa(.keys)
    static let addresses = SettingsPage.marfa(.addresses)
    static let plugins = SettingsPage.marfa(.plugins)
    static let types = SettingsPage.marfa(.types)
    static let sources = SettingsPage.marfa(.sources)
    static let trash = SettingsPage.marfa(.trash)
    static let links = SettingsPage.marfa(.links)
    static let history = SettingsPage.marfa(.history)
    static let fileStorage = SettingsPage.marfa(.fileStorage)
    static let connectors = SettingsPage.marfa(.connectors)
    static let webhooks = SettingsPage.marfa(.webhooks)
    static let folders = SettingsPage.marfa(.folders)
    static let backups = SettingsPage.marfa(.backups)
    static let updates = SettingsPage.marfa(.updates)
    static let housekeeping = SettingsPage.marfa(.housekeeping)
    static let activity = SettingsPage.marfa(.activity)
    static let monitoring = SettingsPage.marfa(.monitoring)
    static let limits = SettingsPage.marfa(.limits)
    static let startUp = SettingsPage.marfa(.startUp)

    /// The app's pages as the sidebar lists them, in groups split by space.
    static let appGroups: [[SettingsPage]] = [[.general, .connection, .appearance, .keyboard], [.editor, .lists, .layouts, .search]]
    /// The Marfa's pages, in groups.
    static let marfaGroups: [[SettingsPage]] = MarfaSettingsPage.groups.map { $0.map(SettingsPage.marfa) }

    static let allCases: [SettingsPage] = appGroups.flatMap { $0 } + MarfaSettingsPage.allCases.map(Self.marfa)

    var sidebarEntry: SettingsPage {
        switch self {
        case .marfa(let page): .marfa(page.sidebarEntry)
        default: self
        }
    }

    /// Search hits from pages reached through another page appear under their sidebar entry.
    static func sidebarMatches(_ query: String) -> Set<SettingsPage> {
        Set(allCases.lazy.filter { $0.matches(query) }.map(\.sidebarEntry))
    }

    /// A name for tests and accessibility, which never changes with the language.
    var key: String {
        switch self {
        case .general: "general"
        case .appearance: "appearance"
        case .keyboard: "keyboard"
        case .lists: "lists"
        case .editor: "editor"
        case .layouts: "layouts"
        case .search: "search"
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
        case .layouts: String(localized: "Layouts")
        case .search: String(localized: "Search")
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
        case .layouts: "rectangle.split.1x2.fill"
        case .search: "magnifyingglass"
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
        case .editor: .amber
        case .layouts: .purple
        case .search: .teal
        case .connection: .green
        case .marfa(let page): page.tone
        }
    }

    /// The titles of the rows the page holds, which the sidebar's search finds the page by.
    var searchWords: [String] {
        switch self {
        case .general:
            [
                String(localized: "Start with"), String(localized: "Reopen windows after quitting"),
                String(localized: "Open items in"), String(localized: "Open Marfa links in"),
                String(localized: "New items are"), String(localized: "New item opens as"), String(localized: "Say today and yesterday"),
                String(localized: "Week starts on"), String(localized: "Date format"), String(localized: "Time format"),
                String(localized: "Load pictures from websites"), String(localized: "Send error reports"),
                String(localized: "Marfa for Mac"), String(localized: "Check for Updates"), String(localized: "Check automatically"),
                String(localized: "Try beta versions"), String(localized: "Kept in this Marfa"), String(localized: "Export settings"),
                String(localized: "Import settings"), String(localized: "Restore earlier settings"), String(localized: "Reset settings"),
            ]
        case .appearance:
            [
                String(localized: "Theme"), String(localized: "Accent"), String(localized: "App icon"), String(localized: "Dock"),
                String(localized: "Highlight color"), String(localized: "Type chip color"), String(localized: "Interface text size"),
                String(localized: "Value panels"), String(localized: "Palettes"), String(localized: "Sidebar color"),
                String(localized: "Back and forward over the sidebar"), String(localized: "Show item title when scrolling"),
                String(localized: "Toolbar background when scrolling"), String(localized: "Symbols on subtypes in the sidebar"),
                String(localized: "Window Layout"), String(localized: "Sidebar width"), String(localized: "List width"),
                String(localized: "From the front window"), String(localized: "Default widths"),
            ]
        case .keyboard:
            [
                String(localized: "Shortcuts"), String(localized: "Export Shortcuts"), String(localized: "Import Shortcuts"),
                String(localized: "Restore Defaults"), String(localized: "Global Shortcuts"),
                String(localized: "Search Shortcuts"), String(localized: "Search by Pressing a Shortcut"),
                String(localized: "Export…"), String(localized: "Import…"),
            ] + AnyAppCommand.allCases.map(\.title) + ShortcutMenu.allCases.map(\.title) + ShortcutCommand.all.map(\.title)
        case .lists:
            [
                String(localized: "Density"), String(localized: "Standard"), String(localized: "Compact"), String(localized: "Defaults"),
                String(localized: "From"), String(localized: "All Items"), String(localized: "Library"), String(localized: "Sort by"),
                String(localized: "Group by"), String(localized: "None"), String(localized: "Date"),
            ] + ItemSort.allCases.map { String(localized: $0.title) }
        case .editor:
            [
                String(localized: "Font"), String(localized: "Code font"), String(localized: "Text size"),
                String(localized: "Line spacing"), String(localized: "Paragraph spacing"), String(localized: "Links to items"),
                String(localized: "Page width"), String(localized: "Standard width"), String(localized: "Title length"),
                String(localized: "Fold headings with a triangle"), String(localized: "Line numbers in code"),
                String(localized: "Pinned properties"), String(localized: "PDF background"),
                String(localized: "Formats"), String(localized: "Text size and width"), String(localized: "Focus"),
                String(localized: "Edit pages as"), String(localized: "Articles open in"), String(localized: "Paste formatted text as"),
                String(localized: "Check spelling"), String(localized: "Smart quotes and dashes in formatted text"),
                String(localized: "Pair brackets and quotes"), String(localized: "Continue lists on Return"),
                String(localized: "Indent Markdown Source with"),
            ]
        case .layouts:
            [
                String(localized: "Preview"), String(localized: "Row"), String(localized: "Facts"), String(localized: "Page"),
                String(localized: "Linked From"), String(localized: "Restore Defaults"), String(localized: "Import…"),
                String(localized: "Export…"), String(localized: "Yours"), String(localized: "Built In"), String(localized: "From Plugins"),
                String(localized: "Date"), String(localized: "Secondary line"), String(localized: "Color"), String(localized: "Pin a Property…"),
            ]
        case .search:
            [
                String(localized: "Excluded"), String(localized: "Add…"), String(localized: "Type or source"), String(localized: "Included"),
                String(localized: "Archived items"), String(localized: "Feed items"), String(localized: "Results"), String(localized: "Order"),
                String(localized: "Best Match"), String(localized: "Most Recent"), String(localized: "Show matched words under each result"),
                String(localized: "Show snippets"),
            ]
        case .connection:
            [
                String(localized: "Marfa"), String(localized: "Address"), String(localized: "Sign In"), String(localized: "Signed in as"),
                String(localized: "Permissions"), String(localized: "Unsent changes"), String(localized: "Use another Marfa"),
                String(localized: "Downloaded Files"), String(localized: "Keep opened files"), String(localized: "Attachments"),
                String(localized: "Opened files"), String(localized: "Clear"), String(localized: "Remove downloaded files"),
                String(localized: "This Mac’s Copy"), String(localized: "Space used"), String(localized: "On This Mac"),
                String(localized: "Export everything"), String(localized: "Export automatically"), String(localized: "Export folder"),
                String(localized: "Download everything again"), String(localized: "Disconnect"),
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
