import Foundation

/// What the command palette's filter row narrows its items by: type, collection and when an item was last updated. A
/// filter with no values narrows nothing. They apply to the items a palette lists, never to its commands or places.
nonisolated struct PaletteFilters: Equatable, Sendable {
    enum Field: String, CaseIterable, Sendable {
        case type, collection, updated
    }

    /// How recently an item was updated, as the calendar counts it now.
    enum Period: String, CaseIterable, Sendable {
        case today, thisWeek, thisMonth, thisYear

        var component: Calendar.Component {
            switch self {
            case .today: .day
            case .thisWeek: .weekOfYear
            case .thisMonth: .month
            case .thisYear: .year
            }
        }

        func contains(_ date: Date, now: Date, calendar: Calendar) -> Bool {
            calendar.dateInterval(of: component, for: now)?.contains(date) ?? false
        }
    }

    var types: Set<TypeID> = []
    var collections: Set<ItemID> = []
    /// One period at a time: two of them would only be the wider.
    var period: Period?
    /// The fields whose filter reads "is not".
    var negated: Set<Field> = []

    /// Whether the field holds any value.
    func isSet(_ field: Field) -> Bool {
        switch field {
        case .type: !types.isEmpty
        case .collection: !collections.isEmpty
        case .updated: period != nil
        }
    }

    /// How many fields narrow the items: the number the filter button shows.
    var count: Int { Field.allCases.filter(isSet).count }

    var isEmpty: Bool { count == 0 }

    /// Takes a field's values away, and its "is not" with them.
    mutating func clear(_ field: Field) {
        switch field {
        case .type: types = []
        case .collection: collections = []
        case .updated: period = nil
        }
        negated.remove(field)
    }

    func admits(_ item: Item, now: Date, calendar: Calendar = .current) -> Bool {
        func holds(_ field: Field, _ matches: () -> Bool) -> Bool {
            !isSet(field) || matches() != negated.contains(field)
        }
        return holds(.type) { types.contains(item.type) }
            && holds(.collection) { item.collectionIDs.contains { collections.contains($0) } }
            && holds(.updated) { period?.contains(item.modified, now: now, calendar: calendar) ?? true }
    }

    /// The items that pass, in their order. Unfiltered, the same array.
    func apply(to items: [Item], now: Date, calendar: Calendar = .current) -> [Item] {
        isEmpty ? items : items.filter { admits($0, now: now, calendar: calendar) }
    }
}
