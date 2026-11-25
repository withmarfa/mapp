import Foundation

/// An index page: a table under tabs. Sources and Collections list the places that hold items, and Items lists the items.
/// Each remembers its own tab and sort, among the settings that sync.
nonisolated enum IndexPlace: String, CaseIterable, Sendable {
    case sources, collections, items

    var tabKey: String { "indexTab.\(rawValue)" }
    var sortKey: String { "indexSort.\(rawValue)" }

    /// The tabs of the page, in order. The first is All.
    var tabs: [IndexTab] {
        switch self {
        case .sources: [.all, .apps, .keys]
        case .collections, .items: [.all, .library, .feed]
        }
    }

    /// How the page's rows are ordered until the person chooses: collections by name, sources by what they wrote, items
    /// by when they changed, the latest first.
    var defaultSort: IndexSort {
        switch self {
        case .sources: IndexSort(column: .count, ascending: false)
        case .collections: IndexSort(column: .name, ascending: true)
        case .items: IndexSort(column: .latest, ascending: false)
        }
    }

    init?(_ item: PlaceView) {
        switch item {
        case .sources: self = .sources
        case .collections: self = .collections
        case .library: self = .items
        default: return nil
        }
    }
}

/// A tab of an index page: which of its rows it lists. Collections split by the tier they are kept in; sources into
/// the apps a person signed in and the keys they made.
nonisolated enum IndexTab: String, Sendable {
    /// The library tier and the feed tier are kept under the words earlier copies stored.
    case all, library = "yours", feed = "fromApps", apps, keys

    /// Whether the row belongs under this tab. A collection is Library in the library tier and Feed in the feed
    /// tier; a source is an app when its code starts with `oauth:`, which the contract keeps for apps signed in and
    /// no key may claim, and a key otherwise.
    func includes(_ row: IndexRow) -> Bool {
        switch self {
        case .all: true
        case .library: row.tier == .library
        case .feed: row.tier == .feed
        case .apps: row.sourceCode.map(SourceCode.isApp) == true
        case .keys: row.sourceCode.map { !SourceCode.isApp($0) } == true
        }
    }

    /// The rows the tab lists, in their order.
    func rows(in rows: [IndexRow]) -> [IndexRow] { self == .all ? rows : rows.filter(includes) }
}

/// What a source's code says about who wrote it.
nonisolated enum SourceCode {
    /// An app signed in writes as `oauth:` and its client's identifier (`keys-and-oauth`).
    static let appPrefix = "oauth:"

    /// Only a code that starts with the prefix is an app: a key's code that has it later is still a key's.
    static func isApp(_ code: String) -> Bool { code.hasPrefix(appPrefix) }
}

/// A column of an index table. `latest` is a source's latest item, and a collection's or an item's own update; `types` is
/// what a source writes and an item's type.
nonisolated enum IndexColumn: String, CaseIterable, Sendable {
    case name, types, source, count, latest
}

nonisolated extension IndexPlace {
    /// The columns of the page's table, in order: a collection says where it came from, and a source what it writes.
    var columns: [IndexColumn] {
        switch self {
        case .sources: [.name, .types, .count, .latest]
        case .collections: [.name, .source, .count, .latest]
        case .items: [.name, .types, .source, .latest]
        }
    }
}

/// The order of an index table, kept as text such as `count.desc` so a default can hold it.
nonisolated struct IndexSort: RawRepresentable, Hashable, Sendable {
    var column: IndexColumn
    var ascending: Bool

    init(column: IndexColumn, ascending: Bool) {
        self.column = column
        self.ascending = ascending
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: ".")
        guard parts.count == 2, let column = IndexColumn(rawValue: String(parts[0])), ["asc", "desc"].contains(parts[1]) else { return nil }
        self.init(column: column, ascending: parts[1] == "asc")
    }

    var rawValue: String { "\(column.rawValue).\(ascending ? "asc" : "desc")" }

    /// The rows in this order, equal rows by name, so the order never shifts between two refreshes.
    func sorted(_ rows: [IndexRow]) -> [IndexRow] {
        rows.sorted(using: comparators + [KeyPathComparator(\IndexRow.title, comparator: .localizedStandard)])
    }

    /// The sort an item table's header asks for, from its comparators' first.
    init?(comparators: [KeyPathComparator<ItemIndexRow>]) {
        guard let first = comparators.first else { return nil }
        let path: AnyKeyPath = first.keyPath
        let ascending = first.order == .forward
        if path == \ItemIndexRow.title { self.init(column: .name, ascending: ascending) }
        else if path == \ItemIndexRow.typeLabel { self.init(column: .types, ascending: ascending) }
        else if path == \ItemIndexRow.sourceName { self.init(column: .source, ascending: ascending) }
        else if path == \ItemIndexRow.modified { self.init(column: .latest, ascending: ascending) }
        else { return nil }
    }

    /// The items in this order, equal items by name and then by identifier, so the order never shifts between two refreshes.
    func sorted(_ rows: [ItemIndexRow]) -> [ItemIndexRow] {
        rows.sorted(using: itemComparators + [
            KeyPathComparator(\ItemIndexRow.title, comparator: .localizedStandard),
            KeyPathComparator(\ItemIndexRow.id.rawValue),
        ])
    }

    /// The comparators an item table shows its header arrow for. A column the Items page lacks orders by name.
    var itemComparators: [KeyPathComparator<ItemIndexRow>] {
        let order: SortOrder = ascending ? .forward : .reverse
        return switch column {
        case .types: [KeyPathComparator(\ItemIndexRow.typeLabel, comparator: .localizedStandard, order: order)]
        case .source: [KeyPathComparator(\ItemIndexRow.sourceName, comparator: .localizedStandard, order: order)]
        case .latest: [KeyPathComparator(\ItemIndexRow.modified, order: order)]
        case .name, .count: [KeyPathComparator(\ItemIndexRow.title, comparator: .localizedStandard, order: order)]
        }
    }

    /// The sort a table's header asks for, from its comparators' first.
    init?(comparators: [KeyPathComparator<IndexRow>]) {
        guard let first = comparators.first else { return nil }
        let path: AnyKeyPath = first.keyPath
        let ascending = first.order == .forward
        if path == \IndexRow.title { self.init(column: .name, ascending: ascending) }
        else if path == \IndexRow.types { self.init(column: .types, ascending: ascending) }
        else if path == \IndexRow.sourceName { self.init(column: .source, ascending: ascending) }
        else if path == \IndexRow.count { self.init(column: .count, ascending: ascending) }
        else if path == \IndexRow.latestOrOldest { self.init(column: .latest, ascending: ascending) }
        else { return nil }
    }

    /// The comparators a table shows its header arrow for.
    var comparators: [KeyPathComparator<IndexRow>] {
        let order: SortOrder = ascending ? .forward : .reverse
        return switch column {
        case .name: [KeyPathComparator(\IndexRow.title, comparator: .localizedStandard, order: order)]
        case .types: [KeyPathComparator(\IndexRow.types, comparator: .localizedStandard, order: order)]
        case .source: [KeyPathComparator(\IndexRow.sourceName, comparator: .localizedStandard, order: order)]
        case .count: [KeyPathComparator(\IndexRow.count, order: order)]
        case .latest: [KeyPathComparator(\IndexRow.latestOrOldest, order: order)]
        }
    }
}

/// The choices kept for each index page, in the app's defaults. Views read the same keys through `@AppStorage`;
/// commands write them here.
nonisolated enum IndexPreferences {
    /// The tab of `place`; All when nothing is kept, or what is kept is not one of its tabs.
    static func tab(for place: IndexPlace, in defaults: UserDefaults = .standard) -> IndexTab {
        defaults.string(forKey: place.tabKey).flatMap(IndexTab.init).flatMap { place.tabs.contains($0) ? $0 : nil } ?? .all
    }

    static func set(_ tab: IndexTab, for place: IndexPlace, in defaults: UserDefaults = .standard) {
        defaults.set(tab.rawValue, forKey: place.tabKey)
    }

    static func sort(for place: IndexPlace, in defaults: UserDefaults = .standard) -> IndexSort {
        defaults.string(forKey: place.sortKey).flatMap(IndexSort.init).flatMap { place.columns.contains($0.column) ? $0 : nil } ?? place.defaultSort
    }

    static func set(_ sort: IndexSort, for place: IndexPlace, in defaults: UserDefaults = .standard) {
        defaults.set(sort.rawValue, forKey: place.sortKey)
    }
}

extension Browser {
    /// The index page the window shows, if it shows one.
    var indexPlace: IndexPlace? { showsSidebarIndex ? IndexPlace(shown) : nil }
}
