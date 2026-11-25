import Foundation

/// One row of the Items index: an item as its table shows it. Plain values only, so a change of the chosen row finds
/// every cell unchanged.
nonisolated struct ItemIndexRow: Identifiable, Hashable, Sendable {
    let id: ItemID
    let title: String
    /// The core's name for one item of its type.
    let typeLabel: String
    /// The type's icon from the catalogue; nil where it has none, which draws the neutral mark.
    let icon: String?
    /// The name of the source that made it; empty where none did.
    let sourceName: String
    let modified: Date
    let tier: Tier
}

/// The rows of each tab of the Items index, in the order of the table. Worked out once for the items and the sort, so
/// a change of tab reads one of these and counts nothing.
nonisolated struct ItemIndexTabs: Sendable {
    let all: [ItemIndexRow]
    let library: [ItemIndexRow]
    let feed: [ItemIndexRow]

    static let empty = ItemIndexTabs(all: [], library: [], feed: [])

    /// The rows under `tab`. A tab the Items page lacks lists nothing.
    func rows(for tab: IndexTab) -> [ItemIndexRow] {
        switch tab {
        case .all: all
        case .library: library
        case .feed: feed
        case .apps, .keys: []
        }
    }

    func count(for tab: IndexTab) -> Int { rows(for: tab).count }

    /// The tabs with only the rows `isKept` takes, in the order they were.
    func keeping(where isKept: (ItemIndexRow) -> Bool) -> ItemIndexTabs {
        ItemIndexTabs(all: all.filter(isKept), library: library.filter(isKept), feed: feed.filter(isKept))
    }

    /// These tabs with the row of `id` at the place it held in `earlier`, in each tab that held it then and holds it now.
    func holding(_ id: ItemID, as earlier: ItemIndexTabs) -> ItemIndexTabs {
        func held(_ rows: [ItemIndexRow], _ before: [ItemIndexRow]) -> [ItemIndexRow] {
            guard let was = before.firstIndex(where: { $0.id == id }), let now = rows.firstIndex(where: { $0.id == id }),
                  was != now else { return rows }
            var moved = rows
            moved.insert(moved.remove(at: now), at: min(was, moved.count))
            return moved
        }
        return ItemIndexTabs(
            all: held(all, earlier.all), library: held(library, earlier.library), feed: held(feed, earlier.feed))
    }
}

nonisolated extension IndexTab {
    /// Whether an item in `tier` belongs under this tab: Library is the library tier and Feed the feed tier.
    func includes(tier: Tier) -> Bool {
        switch self {
        case .all: true
        case .library: tier == .library
        case .feed: tier == .feed
        case .apps, .keys: false
        }
    }
}

nonisolated enum ItemIndexRows {
    /// The rows of `items`, in the order given. A type's label and a source's name are looked up once for each.
    static func rows(of items: [Item], catalogue: Catalogue, directory: SourceDirectory) -> [ItemIndexRow] {
        var labels: [TypeID: String] = [:]
        var sources: [String: String] = [:]
        return items.map { item in
            let label = labels[item.type] ?? { let made = catalogue.label(for: item.type); labels[item.type] = made; return made }()
            let source: String
            if let code = item.source, !code.isEmpty {
                source = sources[code] ?? { let made = directory.name(code); sources[code] = made; return made }()
            } else {
                source = ""
            }
            return ItemIndexRow(
                id: item.id, title: item.displayTitle, typeLabel: label, icon: catalogue.icon(for: item.type), sourceName: source,
                modified: item.modified, tier: item.tier)
        }
    }

    /// The rows of each tab in the order of `sort`.
    static func arranged(_ rows: [ItemIndexRow], by sort: IndexSort) -> ItemIndexTabs { split(sort.sorted(rows)) }

    /// The rows of each tab in the order given, which a search's relevance is.
    static func split(_ rows: [ItemIndexRow]) -> ItemIndexTabs {
        ItemIndexTabs(
            all: rows, library: rows.filter { IndexTab.library.includes(tier: $0.tier) },
            feed: rows.filter { IndexTab.feed.includes(tier: $0.tier) })
    }

    /// The tabs for `items`, as the index page lists them.
    static func tabs(of items: [Item], catalogue: Catalogue, directory: SourceDirectory, sort: IndexSort) -> ItemIndexTabs {
        arranged(rows(of: items, catalogue: catalogue, directory: directory), by: sort)
    }
}
