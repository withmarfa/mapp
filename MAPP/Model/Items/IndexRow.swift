import Foundation

/// How many of an index row's items are of one type.
nonisolated struct TypeShare: Identifiable, Hashable, Sendable {
    /// Nil for the share that gathers the types beyond the ones shown.
    let type: TypeID?
    let label: String
    let count: Int
    var id: String { type?.rawValue ?? "" }
}

/// One row of an index page: a place the page leads to, and what is known of the items in it.
nonisolated struct IndexRow: Identifiable, Hashable, Sendable {
    let place: SidebarItem
    let title: String
    let symbol: String
    /// The line under the title where the rows are a list.
    let secondary: String
    /// The types of its items, as a line of text.
    let types: String
    let count: Int
    /// When its most recently changed item changed; nil where it has none.
    let latest: Date?
    /// Its items by type, the most numerous first.
    let breakdown: [TypeShare]

    var id: SidebarItem { place }
    /// For sorting by the latest item: a row with none sorts as the oldest.
    var latestOrOldest: Date { latest ?? .distantPast }
}

/// Where a source's icon is chosen. MAPP does not know what kind a source is (a folder, a connector, an app or an
/// API key), so every source has one icon; a kind, once known, chooses here.
nonisolated enum SourceTile {
    static func symbol(forSource name: String) -> String { "antenna.radiowaves.left.and.right" }
}

nonisolated enum IndexRows {
    /// The sources of `items`, by name, each with the types it wrote and its latest change.
    static func sources(of items: [Item], catalogue: Catalogue) -> [IndexRow] {
        var named: [String: [Item]] = [:]
        for item in items {
            if let source = item.source, !source.isEmpty { named[source, default: []].append(item) }
        }
        return named.map { name, items in
            let breakdown = breakdown(of: items, catalogue: catalogue)
            let types = summary(of: breakdown)
            return IndexRow(
                place: .source(name), title: name, symbol: SourceTile.symbol(forSource: name), secondary: types, types: types,
                count: items.count, latest: items.map(\.modified).max(), breakdown: breakdown)
        }
        .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// `collections` in the order given, each with its members' types. Its secondary line is its own type.
    static func collections(_ collections: [Item], membersOf: (Item) -> [Item], catalogue: Catalogue) -> [IndexRow] {
        collections.map { collection in
            let members = membersOf(collection)
            let breakdown = breakdown(of: members, catalogue: catalogue)
            return IndexRow(
                place: .collection(collection.id), title: collection.title,
                symbol: TypeSymbol.name(for: collection.type, in: catalogue),
                secondary: TypeSymbol.label(for: collection.type, in: catalogue), types: summary(of: breakdown),
                count: members.count, latest: members.map(\.modified).max(), breakdown: breakdown)
        }
    }

    /// The items by type, most first and then by label, each counted once.
    static func breakdown(of items: [Item], catalogue: Catalogue) -> [TypeShare] {
        var counts: [TypeID: Int] = [:]
        for item in items { counts[item.type, default: 0] += 1 }
        return counts
            .map { TypeShare(type: $0.key, label: TypeSymbol.label(for: $0.key, in: catalogue), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// At most `limit` shares, the rest gathered into one last share, so a bar and its key stay readable.
    static func collapsing(_ shares: [TypeShare], limit: Int = 4) -> [TypeShare] {
        guard shares.count > limit, limit > 1 else { return shares }
        let rest = shares.dropFirst(limit - 1)
        return Array(shares.prefix(limit - 1)) + [TypeShare(type: nil, label: String(localized: "Other"), count: rest.reduce(0) { $0 + $1.count })]
    }

    /// The type labels as one line, naming `limit` and counting the rest.
    static func summary(of shares: [TypeShare], limit: Int = 3) -> String {
        let labels = shares.map(\.label)
        guard labels.count > limit else { return labels.formatted(.list(type: .and, width: .standard)) }
        let more = String(localized: "\(labels.count - limit) more")
        return (Array(labels.prefix(limit)) + [more]).formatted(.list(type: .and, width: .standard))
    }
}
