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

        /// The span of the day, week, month or year `now` falls in, in the calendar's time zone and first weekday.
        func interval(now: Date, calendar: Calendar) -> DateInterval? {
            calendar.dateInterval(of: component, for: now)
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

    /// `span` is the period's span, worked out once for all the items. It ends where the next period starts, so that
    /// instant is not in it.
    private func admits(_ item: Item, span: DateInterval?) -> Bool {
        func holds(_ field: Field, _ matches: () -> Bool) -> Bool {
            !isSet(field) || matches() != negated.contains(field)
        }
        return holds(.type) { types.contains(item.type) }
            && holds(.collection) {
                // Reads the edges in place: no list of the item's collections is built for each item.
                item.edgesOut.contains { edge in
                    guard edge.type == MarfaMapping.collectionEdge, case .item(let id) = edge.target else { return false }
                    return collections.contains(id)
                }
            }
            && holds(.updated) { span.map { $0.start <= item.modified && item.modified < $0.end } ?? false }
    }

    /// The items that pass, in their order. Unfiltered, the same array.
    func apply(to items: [Item], now: Date, calendar: Calendar = .current) -> [Item] {
        guard !isEmpty else { return items }
        let span = period?.interval(now: now, calendar: calendar)
        return items.filter { admits($0, span: span) }
    }
}
