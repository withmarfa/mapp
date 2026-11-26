import Foundation
import Marfa

/// What an item's page lists under its text: its sub-items, nested, and the items that link to it. The page draws it
/// and the app builds it, as it does the head (`PageHead`).
///
/// A list shows `step` rows, and its Show More shows `step` more: the page says which (`PageFoot.Limits`), so an item
/// that hundreds of others link to makes the rows it shows and no more, and each row's date is worked out only for those.
nonisolated struct PageFoot: Equatable, Sendable, Encodable {
    /// How many rows a list shows before Show More, and how many more each Show More adds.
    static let step = 30
    /// How many levels of sub-items one drawing nests. A row deeper than this is reached by opening its parent.
    static let depth = 3

    /// How many rows each list has been asked to show, by `Section.key` and `Row.key`. A list not named shows `step`.
    typealias Limits = [String: Int]

    enum Kind: String, Sendable, Encodable {
        case subItems, timeline, linkedFrom
    }

    struct Row: Equatable, Sendable {
        let item: ItemID
        let title: String
        /// The icon of the item's type, an Iconify ID. A task is drawn with its status instead.
        let icon: String?
        let mark: PageHeader.Pin.Mark?
        let date: String
        /// The item's own sub-items, to the depth `depth` allows.
        let children: [Row]
        /// How many sub-items wait behind this row's Show More, and the key its Show More asks by.
        let hiddenChildren: Int
        var key: String { Self.key(of: item) }

        static func key(of item: ItemID) -> String { "sub:" + item.rawValue }
    }

    struct Section: Equatable, Sendable {
        let kind: Kind
        let title: String
        /// How many rows the list has altogether, shown or not. For sub-items, everything beneath the item.
        let total: Int
        let rows: [Row]
        let hidden: Int
        var key: String { kind.rawValue }
    }

    let sections: [Section]

    var isEmpty: Bool { sections.isEmpty }

    /// What a list's Show More says, which the page draws and never makes.
    static func moreWords(_ count: Int) -> String { String(localized: "Show \(count) More") }

    /// The page is sent the sections alone.
    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sections)
    }

    /// The icon names the rows draw, for the page to be sent their images.
    var icons: Set<String?> {
        var names: Set<String?> = []
        func collect(_ rows: [Row]) {
            for row in rows {
                if row.mark == nil { names.insert(row.icon) }
                collect(row.children)
            }
        }
        for section in sections { collect(section.rows) }
        return names
    }

    /// The foot of `item`: its sub-items, if it has any, then the items that link to it where its Linked From is on the
    /// page, as a Timeline on a person or a place and as Linked From on any other item.
    @MainActor
    static func of(
        _ item: Item, in library: any ItemLibrary, relationships: [ItemRelationship], showsLinkedFrom: Bool, limits: Limits = [:],
        format: DateFormat, now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> PageFoot {
        Cost.measure(.linkedItems) {
            let catalogue = library.catalogue
            let formed = Formed(library: library, format: format, now: now, calendar: calendar, locale: locale)
            var sections: [Section] = []
            var listed: Set<ItemID> = [item.id]
            let children = formed.children(of: item.id, listKey: Kind.subItems.rawValue, depth: 1, limits: limits, seen: &listed)
            if children.total > 0 {
                sections.append(Section(
                    kind: .subItems, title: String(localized: "Sub-Items"), total: formed.descendants(of: item.id), rows: children.rows,
                    hidden: children.hidden))
            }
            guard showsLinkedFrom else { return PageFoot(sections: sections) }
            let kind = PageHeaderKind.of(item.type, in: catalogue)
            let found = formed.mentions(of: item.id, in: relationships)
            guard !found.isEmpty else { return PageFoot(sections: sections) }
            let isTimeline = kind == .person || kind == .place
            let key = (isTimeline ? Kind.timeline : .linkedFrom).rawValue
            let shown = Array(found.prefix(limits[key] ?? step))
            sections.append(Section(
                kind: isTimeline ? .timeline : .linkedFrom,
                title: isTimeline ? String(localized: "Timeline") : String(localized: "Linked From"),
                total: found.count, rows: shown.map { formed.row($0, children: [], hidden: 0) }, hidden: found.count - shown.count))
            return PageFoot(sections: sections)
        }
    }

    /// Makes rows from the items the library holds, with the settings every row shares.
    @MainActor
    private struct Formed {
        let library: any ItemLibrary
        let format: DateFormat
        let now: Date
        let calendar: Calendar
        let locale: Locale

        func row(_ item: Item, children: [Row], hidden: Int) -> Row {
            let catalogue = library.catalogue
            let status = PanelLinks.status(of: item, in: catalogue)
            let hasStatus = catalogue.itemTypes[item.type]?.statusField != nil
            return Row(
                item: item.id, title: item.displayTitle, icon: catalogue.icon(for: item.type),
                mark: hasStatus ? .init(StatusSymbol(group: status)) : nil, date: date(of: item), children: children, hiddenChildren: hidden)
        }

        /// The day the item is due or starts, where it has one, or else when it last changed.
        private func date(of item: Item) -> String {
            for key in [MarfaMapping.dueField, MarfaMapping.startField] {
                if let text = item.value(of: key)?.string, let day = ItemDate.parse(text) {
                    return DateDisplay.text(of: day.date, hasTime: day.hasTime, place: .list, format: format, now: now, calendar: calendar, locale: locale)
                }
            }
            return DateDisplay.text(of: item.modified, place: .list, format: format, now: now, calendar: calendar, locale: locale)
        }

        /// The sub-items of `parent`, by title, as many as its list has been asked to show, each with its own to the
        /// depth `depth` allows. An item already listed is not listed again, so a loop in the edges ends.
        func children(of parent: ItemID, listKey: String, depth: Int, limits: Limits, seen: inout Set<ItemID>) -> (rows: [Row], total: Int, hidden: Int) {
            var held: [Item] = []
            for id in library.childIDs(of: parent) {
                guard let child = library.headerItem(id), child.state == .active, child.problem == nil else { continue }
                held.append(child)
            }
            held.sort {
                switch $0.displayTitle.localizedStandardCompare($1.displayTitle) {
                case .orderedAscending: true
                case .orderedDescending: false
                case .orderedSame: $0.id.rawValue < $1.id.rawValue
                }
            }
            let shown = held.prefix(limits[listKey] ?? step)
            var rows: [Row] = []
            for child in shown where seen.insert(child.id).inserted {
                let nested: (rows: [Row], total: Int, hidden: Int) = depth < PageFoot.depth
                    ? children(of: child.id, listKey: Row.key(of: child.id), depth: depth + 1, limits: limits, seen: &seen) : ([], 0, 0)
                rows.append(row(child, children: nested.rows, hidden: nested.hidden))
            }
            return (rows, held.count, held.count - shown.count)
        }

        /// Every sub-item beneath `root`, children of children included, each once.
        func descendants(of root: ItemID) -> Int {
            var seen: Set<ItemID> = [root]
            var waiting = [root]
            while let next = waiting.popLast() {
                for id in library.childIDs(of: next) where !seen.contains(id) {
                    guard let child = library.headerItem(id), child.state == .active, child.problem == nil else { continue }
                    seen.insert(id)
                    waiting.append(id)
                }
            }
            return seen.count - 1
        }

        /// The active items that hold a link to `id` in any relationship but a sub-item's or a collection's member's, which
        /// each have a place, once each, the most recently edited first.
        func mentions(of id: ItemID, in relationships: [ItemRelationship]) -> [Item] {
            var seen: Set<ItemID> = [id]
            var found: [Item] = []
            for relationship in relationships where relationship.field.hasPrefix(RelationField.inversePrefix) && relationship.field != PagePlacement.subItems
                && relationship.field != RelationField.inversePrefix + MarfaMapping.collectionEdge {
                for target in relationship.targets {
                    guard let other = target.itemID, !target.isDeleted, let held = library.headerItem(other), held.state == .active,
                          seen.insert(other).inserted else { continue }
                    found.append(held)
                }
            }
            return found.sorted { $0.modified != $1.modified ? $0.modified > $1.modified : $0.title < $1.title }
        }
    }
}

extension PageFoot.Row: Encodable {
    private enum Key: String, CodingKey { case item, title, symbol, tone, mark, date, children, more, key }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(item, forKey: .item)
        try container.encode(title, forKey: .title)
        try container.encode(TypeIconKey.value(for: icon), forKey: .symbol)
        try container.encodeIfPresent(mark, forKey: .mark)
        if mark == nil { try container.encode(TypeTone(icon: icon).rawValue, forKey: .tone) }
        try container.encode(date, forKey: .date)
        if !children.isEmpty { try container.encode(children, forKey: .children) }
        if hiddenChildren > 0 {
            try container.encode(PageFoot.moreWords(hiddenChildren), forKey: .more)
            try container.encode(key, forKey: .key)
        }
    }
}

extension PageFoot.Section: Encodable {
    private enum Key: String, CodingKey { case kind, title, total, rows, more, key }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(title, forKey: .title)
        try container.encode(total, forKey: .total)
        try container.encode(rows, forKey: .rows)
        try container.encode(key, forKey: .key)
        if hidden > 0 { try container.encode(PageFoot.moreWords(hidden), forKey: .more) }
    }
}
