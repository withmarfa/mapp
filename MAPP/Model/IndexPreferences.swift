import Foundation

/// An index page: a page that lists places rather than items. Each remembers its own layout and width.
nonisolated enum IndexPlace: String, CaseIterable, Sendable {
    case sources, collections

    var layoutKey: String { "indexLayout.\(rawValue)" }
    var widthKey: String { "indexWidth.\(rawValue)" }

    init?(_ item: SidebarItem) {
        switch item {
        case .sources: self = .sources
        case .collections: self = .collections
        default: return nil
        }
    }
}

/// How an index page shows its rows.
nonisolated enum IndexLayout: String, CaseIterable, Identifiable, Sendable {
    case list, cards, table

    var id: Self { self }
    static let `default` = IndexLayout.list

    var symbol: String {
        switch self {
        case .list: "list.bullet"
        case .cards: "square.grid.2x2"
        case .table: "tablecells"
        }
    }
}

/// How wide an index page runs. Wide is the window's whole width.
nonisolated enum IndexWidth: String, CaseIterable, Identifiable, Sendable {
    case narrow, standard, wide

    var id: Self { self }
    static let `default` = IndexWidth.narrow

    /// The widest the page's content runs, in points; nil for the window's width.
    var points: Double? {
        switch self {
        case .narrow: 720
        case .standard: 1000
        case .wide: nil
        }
    }
}

/// The choices kept for each index page, in the app's defaults. Views read the same keys through `@AppStorage`;
/// commands write them here.
nonisolated enum IndexPreferences {
    static func layout(for place: IndexPlace, in defaults: UserDefaults = .standard) -> IndexLayout {
        defaults.string(forKey: place.layoutKey).flatMap(IndexLayout.init) ?? .default
    }

    static func width(for place: IndexPlace, in defaults: UserDefaults = .standard) -> IndexWidth {
        defaults.string(forKey: place.widthKey).flatMap(IndexWidth.init) ?? .default
    }

    static func set(_ layout: IndexLayout, for place: IndexPlace, in defaults: UserDefaults = .standard) {
        defaults.set(layout.rawValue, forKey: place.layoutKey)
    }

    static func set(_ width: IndexWidth, for place: IndexPlace, in defaults: UserDefaults = .standard) {
        defaults.set(width.rawValue, forKey: place.widthKey)
    }
}

extension Browser {
    /// The index page the window shows, if it shows one.
    var indexPlace: IndexPlace? { showsSidebarIndex ? IndexPlace(item) : nil }
}
