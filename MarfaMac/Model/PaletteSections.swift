import Foundation

/// How the command palette's list divides into sections, and what Actions offers for a row. Both are plain values
/// worked out from what the palette has already ranked, so a keystroke costs a pass over the rows it lists and no
/// more.
nonisolated enum PaletteSections {
    nonisolated enum Kind: Hashable, Sendable {
        case recent, items, places, commands
        /// ⌘K with nothing typed: the commands that sit under one menu heading.
        case group(CommandGroup)
        /// Search Items: items whose title has what was typed, then items whose text does.
        case titles, inTheText

        var title: String {
            switch self {
            case .recent: String(localized: "Recent")
            case .items: String(localized: "Items")
            case .places: String(localized: "Places")
            case .commands: String(localized: "Commands")
            case .group(let group): group.title
            case .titles: String(localized: "Titles")
            case .inTheText: String(localized: "In the Text")
            }
        }
    }

    /// The menu a command of ⌘K belongs under, in the menu bar's order: the app menu (Settings), then File with Layouts,
    /// which its menu holds, and the rest. With nothing typed ⌘K lists its commands in these groups, each under the
    /// menu's own name; the View menu is split at its dividers.
    nonisolated enum CommandGroup: Int, CaseIterable, Hashable, Sendable {
        case settings, file, looks, edit, format, view, sortAndGroup, textSize, go, help
        #if DEBUG
        case debug
        #endif

        var title: String {
            switch self {
            case .file: String(localized: "File")
            case .edit: String(localized: "Edit")
            case .format: String(localized: "Format")
            case .view: String(localized: "View")
            case .sortAndGroup: String(localized: "Sort and Group")
            case .textSize: String(localized: "Text Size")
            case .go: String(localized: "Go")
            case .help: String(localized: "Help")
            case .looks: String(localized: "Layouts")
            case .settings: String(localized: "Settings")
            #if DEBUG
            case .debug: "Debug"
            #endif
            }
        }
    }

    struct Section<Row> {
        let kind: Kind
        var rows: [Row]
    }

    /// The most recent items ⌘K lists before anything is typed.
    static let recentLimit = 5

    /// The most items ⌘K lists under Items, so Places and Commands stay in view. Search Items has the rest.
    static let itemLimit = 8

    /// ⌘K's sections. Before anything is typed, the most recent items and then every command, in a section for each
    /// menu group that has one (`groups` holds each command's, by its place among the fixed picks; nil is a command
    /// only typing finds, as New Task is), the groups in the menu bar's order and the commands of a group in the order
    /// they were given. Once something is
    /// typed, the items, the places and the commands that answer it, each in the order it was ranked and each only
    /// if it has rows. The section holding the best match (`scores`, one per pick, lower is better) comes first, so
    /// Return runs it; sections whose best matches tie keep the order Items, Places, Commands. Items are cut to
    /// `itemLimit`, and a last row sends the rest to Search Items. The fixed picks are the commands, which `groups`
    /// holds one entry for each, and then the places.
    static func forCommands(picks: [PaletteMatch.Pick], scores: [Int] = [], typed: Bool, groups: [CommandGroup?], recentCount: Int) -> [Section<PaletteMatch.Pick>] {
        guard typed else {
            let recent = (0..<min(recentCount, recentLimit)).map(PaletteMatch.Pick.item)
            let grouped = CommandGroup.allCases.map { group in
                Section(kind: .group(group), rows: groups.indices.filter { groups[$0] == group }.map(PaletteMatch.Pick.fixed))
            }
            return dropEmpty([.init(kind: .recent, rows: recent)] + grouped)
        }
        var items: [PaletteMatch.Pick] = []
        var places: [PaletteMatch.Pick] = []
        var commands: [PaletteMatch.Pick] = []
        var best: [Kind: Int] = [:]
        for (position, pick) in picks.enumerated() {
            let kind: Kind
            switch pick {
            case .item: kind = .items; items.append(pick)
            case .searchItems: continue
            case .fixed(let index):
                if index < groups.count { kind = .commands; commands.append(pick) } else { kind = .places; places.append(pick) }
            }
            let score = position < scores.count ? scores[position] : 0
            best[kind] = min(best[kind] ?? score, score)
        }
        if items.count > itemLimit { items = Array(items.prefix(itemLimit)) + [.searchItems] }
        let sections = dropEmpty([.init(kind: .items, rows: items), .init(kind: .places, rows: places), .init(kind: .commands, rows: commands)])
        // A stable sort keeps the order above for sections whose best matches tie.
        return sections.enumerated().sorted { a, b in
            (best[a.element.kind] ?? 0, a.offset) < (best[b.element.kind] ?? 0, b.offset)
        }.map(\.element)
    }

    /// Search Items' sections: what was found by title, then what was found by its text, each in the order the
    /// library ranked them. With nothing typed, the recent items under one heading.
    static func forSearch<Row>(rows: [Row], typed: Bool, inTitle: (Row) -> Bool) -> [Section<Row>] {
        guard typed else { return dropEmpty([.init(kind: .recent, rows: rows)]) }
        return dropEmpty([
            .init(kind: .titles, rows: rows.filter(inTitle)),
            .init(kind: .inTheText, rows: rows.filter { !inTitle($0) }),
        ])
    }

    private static func dropEmpty<Row>(_ sections: [Section<Row>]) -> [Section<Row>] {
        sections.filter { !$0.rows.isEmpty }
    }

    /// The count the field shows: the rows that are results, once something is typed. A row that only sends the
    /// person elsewhere, such as the one that searches the items, is not a result.
    static func resultCount<Row>(_ sections: [Section<Row>], counting isResult: (Row) -> Bool = { _ in true }) -> Int {
        sections.reduce(0) { $0 + $1.rows.filter(isResult).count }
    }

    /// The ids with any repeat made distinct by its place among the repeats, so a list keyed by them never holds one
    /// twice and each row keeps its id while the list is built in the same order.
    static func distinct(_ ids: [String]) -> [String] {
        var seen: [String: Int] = [:]
        return ids.map { id in
            let count = seen[id, default: 0]
            seen[id] = count + 1
            return count == 0 ? id : "\(id)#\(count)"
        }
    }
}

extension PaletteSections.Section: Equatable where Row: Equatable {}

/// One thing Actions can do for the chosen row.
nonisolated struct PaletteAction: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case open, openInNewWindow, copyLink, copyWikiLink, addToFavorites, removeFromFavorites, versionHistory, delete
        /// A command row's only action.
        case run
    }

    let kind: Kind
    let title: String
    let symbol: String
    /// The keys of the shortcut, one cap each.
    let keys: [String]
    let isDestructive: Bool

    var id: Kind { kind }

    private init(_ kind: Kind, _ title: String, _ symbol: String, keys: [String] = [], isDestructive: Bool = false) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.keys = keys
        self.isDestructive = isDestructive
    }

    /// Actions can copy any item's link. Wiki links and version history apply to non-file items only.
    /// Only active items can be favorited or moved to Recently Deleted from Actions.
    static func forItem(isFile: Bool, isFavorite: Bool, isActive: Bool) -> [PaletteAction] {
        var actions = [
            PaletteAction(.open, String(localized: "Open"), "arrow.up.right", keys: ["↩"]),
            PaletteAction(.openInNewWindow, String(localized: "Open in New Window"), "macwindow", keys: ["⌘", "↩"]),
        ]
        actions.append(PaletteAction(.copyLink, String(localized: "Copy Link"), "link", keys: ["⇧", "⌘", "C"]))
        if !isFile {
            actions.append(PaletteAction(.copyWikiLink, String(localized: "Copy Wiki Link"), "link.badge.plus"))
        }
        if isActive {
            actions.append(isFavorite
                ? PaletteAction(.removeFromFavorites, String(localized: "Remove from Favorites"), "star.slash")
                : PaletteAction(.addToFavorites, String(localized: "Add to Favorites"), "star"))
        }
        if !isFile {
            actions.append(PaletteAction(.versionHistory, String(localized: "Version History…"), "clock.arrow.circlepath", keys: ["⌥", "⌘", "Y"]))
        }
        if isActive {
            actions.append(PaletteAction(.delete, String(localized: "Delete"), "trash", keys: ["⌘", "⌫"], isDestructive: true))
        }
        return actions
    }

    /// A command row offers its one action.
    static var forCommand: [PaletteAction] { [PaletteAction(.run, String(localized: "Run"), "return", keys: ["↩"])] }

    /// The action of `kind` a shortcut may run: one the row offers and the Actions field still shows.
    /// Nil for a row that does not offer it or a field that hides it, so the shortcut does nothing.
    static func reachable(_ kind: Kind, among offered: [PaletteAction], filteredBy query: String) -> PaletteAction? {
        filtered(offered, by: query).first { $0.kind == kind }
    }

    /// The actions whose titles answer what was typed in the panel's field.
    static func filtered(_ actions: [PaletteAction], by query: String) -> [PaletteAction] {
        let query = PaletteMatch.Query(query)
        guard !query.isEmpty else { return actions }
        return actions.filter { PaletteMatch.score($0.title, query: query) != nil }
    }
}
