import Foundation

/// How the command palette's list divides into sections, and what Actions offers for a row. Both are plain values
/// worked out from what the palette has already ranked, so a keystroke costs a pass over the rows it lists and no
/// more.
nonisolated enum PaletteSections {
    nonisolated enum Kind: Hashable, Sendable {
        case recent, items, places, commands
        /// Search Notes: notes whose title has what was typed, then notes whose text does.
        case titles, inTheText

        var title: String {
            switch self {
            case .recent: String(localized: "Recent")
            case .items: String(localized: "Items")
            case .places: String(localized: "Places")
            case .commands: String(localized: "Commands")
            case .titles: String(localized: "Titles")
            case .inTheText: String(localized: "In the Text")
            }
        }
    }

    struct Section<Row> {
        let kind: Kind
        var rows: [Row]
    }

    /// The most recent items ⌘K lists before anything is typed.
    static let recentLimit = 5

    /// ⌘K's sections. Before anything is typed, the most recent items and then every command. Once something is
    /// typed, the items, the places and the commands that answer it, each in the order it was ranked and each only
    /// if it has rows. `commandCount` is how many of the fixed picks (commands first, then places) are commands.
    static func forCommands(picks: [PaletteMatch.Pick], typed: Bool, commandCount: Int, recentCount: Int) -> [Section<PaletteMatch.Pick>] {
        guard typed else {
            let recent = (0..<min(recentCount, recentLimit)).map(PaletteMatch.Pick.item)
            let commands = (0..<commandCount).map(PaletteMatch.Pick.fixed)
            return dropEmpty([.init(kind: .recent, rows: recent), .init(kind: .commands, rows: commands)])
        }
        var items: [PaletteMatch.Pick] = []
        var places: [PaletteMatch.Pick] = []
        var commands: [PaletteMatch.Pick] = []
        for pick in picks {
            switch pick {
            case .item: items.append(pick)
            case .fixed(let index): if index < commandCount { commands.append(pick) } else { places.append(pick) }
            }
        }
        return dropEmpty([.init(kind: .items, rows: items), .init(kind: .places, rows: places), .init(kind: .commands, rows: commands)])
    }

    /// Search Notes' sections: what was found by title, then what was found by its text, each in the order the
    /// library ranked them. With nothing typed, the recent notes under one heading.
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

    /// The count the field shows: every row listed, once something is typed.
    static func resultCount<Row>(_ sections: [Section<Row>]) -> Int {
        sections.reduce(0) { $0 + $1.rows.count }
    }
}

extension PaletteSections.Section: Equatable where Row: Equatable {}

/// One thing Actions can do for the chosen row.
nonisolated struct PaletteAction: Identifiable, Equatable, Sendable {
    nonisolated enum Kind: Hashable, Sendable {
        case open, openInNewWindow, copyLink, addToFavorites, removeFromFavorites, versionHistory, delete
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

    /// What Actions offers for an item, by the same rules as the menus: the favorite toggle and Delete only for an
    /// item that is not in the bin, Version History and Copy Link only for a note. Never Delete Immediately.
    static func forItem(isFile: Bool, isFavorite: Bool, isActive: Bool, openTitle: String = String(localized: "Open")) -> [PaletteAction] {
        var actions = [
            PaletteAction(.open, openTitle, "arrow.up.right", keys: ["↩"]),
            PaletteAction(.openInNewWindow, String(localized: "Open in New Window"), "macwindow", keys: ["⌘", "↩"]),
        ]
        if !isFile {
            actions.append(PaletteAction(.copyLink, String(localized: "Copy Link"), "link", keys: ["⇧", "⌘", "C"]))
        }
        if isActive {
            actions.append(isFavorite
                ? PaletteAction(.removeFromFavorites, String(localized: "Remove from Favorites"), "heart.slash")
                : PaletteAction(.addToFavorites, String(localized: "Add to Favorites"), "heart"))
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

    /// The actions whose titles answer what was typed in the panel's field.
    static func filtered(_ actions: [PaletteAction], by query: String) -> [PaletteAction] {
        let query = PaletteMatch.Query(query)
        guard !query.isEmpty else { return actions }
        return actions.filter { PaletteMatch.score($0.title, query: query) != nil }
    }
}
