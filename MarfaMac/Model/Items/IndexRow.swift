import Foundation

/// How many of a source's items are of one type.
nonisolated struct TypeShare: Identifiable, Hashable, Sendable {
    let type: TypeID
    let label: String
    /// The type's icon from the catalogue; nil where it has none, which draws the neutral mark.
    let icon: String?
    let count: Int
    var id: String { type.rawValue }
}

/// Who writes under a source, as any app can tell: an app signed in, or a connector the server runs.
nonisolated enum SourceKind: Hashable, Sendable {
    case app, connector

    /// An app's code starts with `oauth:`; a connector's source is one `GET /plugins` names. Anything else is not told.
    static func of(_ code: String, connectors: ConnectorKeepers?) -> SourceKind? {
        if SourceCode.isApp(code) { return .app }
        return connectors?.isConnector(code) == true ? .connector : nil
    }
}

/// What a source's code says about who wrote it.
nonisolated enum SourceCode {
    /// An app signed in writes as `oauth:` and its client's identifier (`keys-and-oauth`).
    static let appPrefix = "oauth:"

    /// Only a code that starts with the prefix is an app: a key's code that has it later is still a key's.
    static func isApp(_ code: String) -> Bool { code.hasPrefix(appPrefix) }
}

/// One row of Library › Types, Collections or Sources: a place, and what is known of the items in it. Plain values, so
/// a change of the chosen row finds every cell unchanged.
nonisolated struct IndexRow: Identifiable, Hashable, Sendable {
    let place: Place
    let title: String
    let icon: RowIcon
    /// The active items it holds, of both tiers; a type's kinds included.
    let count: Int
    /// A type's or a source's latest item's change, nil where it has none; a collection's own change, which it always has.
    let latest: Date?
    /// The type a type's row is nested under, where that type is listed too.
    var parent: Place?
    /// How deep a type's row is nested.
    var depth = 0
    /// How many saved views have a type for their home.
    var views = 0
    /// The types a source writes, the most numerous first.
    var writes: [TypeShare] = []
    var kind: SourceKind?
    /// The name of the source that wrote a collection; empty where none did.
    var sourceName = ""
    /// Whether a collection is read-only, which cannot be renamed or deleted.
    var readOnly = false

    var id: Place { place }
    var sourceCode: String? {
        if case .source(let code) = place { code } else { nil }
    }
    var collectionID: ItemID? {
        if case .collection(let id) = place { id } else { nil }
    }
    var typeID: TypeID? {
        if case .type(let type) = place { type } else { nil }
    }
    /// For sorting by the date column: a row with none sorts as the oldest.
    var latestOrOldest: Date { latest ?? .distantPast }
    var kindTitle: String {
        switch kind {
        case .app: String(localized: "App")
        case .connector: String(localized: "Connector")
        case nil: ""
        }
    }
}

/// The mark beside a source: the one the server gives it, else a neutral symbol.
nonisolated enum SourceTile {
    static let fallbackSymbol = "antenna.radiowaves.left.and.right"

    static func icon(for source: SourceInfo) -> RowIcon {
        source.mark.map { .type($0) } ?? .symbol(fallbackSymbol)
    }
}

nonisolated enum IndexRows {
    /// The items of each source, in code order. Items with no source belong to none. Sources and the palette's source
    /// list both read this, so they cannot disagree.
    static func groupedBySource(_ items: [Item]) -> [(code: String, items: [Item])] {
        var named: [String: [Item]] = [:]
        for item in items {
            if let source = item.source, !source.isEmpty { named[source, default: []].append(item) }
        }
        return named.map { (code: $0.key, items: $0.value) }
            .sorted { $0.code.localizedStandardCompare($1.code) == .orderedAscending }
    }

    /// The types that hold items, each under the nearest of its ancestors that is listed too, with its count, the saved
    /// views whose home it is and its latest item's change, its kinds' included. In no order: `nested` orders them.
    static func types(
        _ counts: [ItemTypeCount], items: [Item], views: [LibraryView], catalogue: Catalogue, name: (TypeID) -> String
    ) -> [IndexRow] {
        var latestOwn: [TypeID: Date] = [:]
        for item in items where latestOwn[item.type].map({ item.modified > $0 }) ?? true { latestOwn[item.type] = item.modified }
        var viewCounts: [TypeID: Int] = [:]
        for view in views {
            if case .type(let type) = Place.home(of: view.query, catalogue: catalogue) { viewCounts[type, default: 0] += 1 }
        }
        let listed = Set(counts.map(\.id))
        let parents: [TypeID: TypeID] = Dictionary(uniqueKeysWithValues: counts.compactMap { count in
            catalogue.ancestors(of: count.id).first(where: listed.contains).map { (count.id, $0) }
        })
        func depth(of type: TypeID) -> Int {
            var depth = 0
            var current = type
            while let parent = parents[current], depth < 32 { depth += 1; current = parent }
            return depth
        }
        return counts.map { count in
            let latest = ([count.id] + catalogue.descendants(of: count.id)).compactMap { latestOwn[$0] }.max()
            return IndexRow(
                place: .type(count.id), title: name(count.id), icon: .type(count.icon), count: count.count, latest: latest,
                parent: parents[count.id].map(Place.type), depth: depth(of: count.id), views: viewCounts[count.id] ?? 0)
        }
    }

    /// The sources `directory` lists (`SourceDirectory.listing`), each with the types of its loaded `items`, their latest
    /// change and its kind; a source whose items are not loaded has a row that writes nothing.
    static func sources(
        of items: [Item], catalogue: Catalogue, directory: SourceDirectory = SourceDirectory(), connectors: ConnectorKeepers? = nil
    ) -> [IndexRow] {
        let grouped = Dictionary(uniqueKeysWithValues: groupedBySource(items).map { ($0.code, $0.items) })
        return directory.listing(loaded: grouped.mapValues(\.count)).map { entry in
            let items = grouped[entry.code] ?? []
            return IndexRow(
                place: .source(entry.code), title: entry.name, icon: SourceTile.icon(for: directory.info(entry.code)), count: entry.count,
                latest: items.map(\.modified).max(), writes: breakdown(of: items, catalogue: catalogue),
                kind: SourceKind.of(entry.code, connectors: connectors))
        }
    }

    /// `collections` in the order given, each with how many items it lists, the source that wrote it as `directory`
    /// names it, and when it last changed.
    static func collections(
        _ collections: [Item], count: (Item) -> Int, catalogue: Catalogue, directory: SourceDirectory = SourceDirectory()
    ) -> [IndexRow] {
        collections.map { collection in
            IndexRow(
                place: .collection(collection.id), title: collection.displayTitle, icon: .type(catalogue.icon(for: collection.type)),
                count: count(collection), latest: collection.modified,
                sourceName: collection.source.flatMap { $0.isEmpty ? nil : directory.name($0) } ?? "", readOnly: collection.readOnly)
        }
    }

    /// The items by type, most first and then by label, each counted once.
    static func breakdown(of items: [Item], catalogue: Catalogue) -> [TypeShare] {
        var counts: [TypeID: Int] = [:]
        for item in items { counts[item.type, default: 0] += 1 }
        return counts
            .map { TypeShare(type: $0.key, label: catalogue.label(for: $0.key), icon: catalogue.icon(for: $0.key), count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.label.localizedStandardCompare($1.label) == .orderedAscending }
    }

    /// `rows` in the order of `comparators`, each row's children after it in the same order, so a sort never takes a kind
    /// from under its type. With no comparators, the most items first.
    static func nested(_ rows: [IndexRow], by comparators: [KeyPathComparator<IndexRow>]) -> [IndexRow] {
        let order = comparators.isEmpty ? [KeyPathComparator(\IndexRow.count, order: .reverse)] : comparators
        let tieBreak = KeyPathComparator(\IndexRow.title, comparator: .localizedStandard)
        let listed = Set(rows.map(\.place))
        var children: [Place?: [IndexRow]] = [:]
        for row in rows { children[row.parent.flatMap { listed.contains($0) ? $0 : nil }, default: []].append(row) }
        var ordered: [IndexRow] = []
        ordered.reserveCapacity(rows.count)
        func walk(_ parent: Place?) {
            for row in (children[parent] ?? []).sorted(using: order + [tieBreak]) {
                ordered.append(row)
                walk(row.place)
            }
        }
        walk(nil)
        return ordered
    }
}
