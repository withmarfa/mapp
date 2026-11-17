import Foundation
import Marfa

/// Where an item sits in time, which the timeline and the calendar both read. One rule places every item, so a place
/// that mixes types puts each on the date its own type's look names (`TypeLook.date`):
///
/// - An event is placed by its start, with its end where it has one. An event is a whole day, or a run of days, when it
///   is flagged all-day or its start names no time; it then sits on the days it is lived in, whatever the Mac's zone.
///   A timed event is an instant, which the Mac's calendar puts on its own day.
/// - A task is placed by its due date, a day alone where the due date has no time.
/// - Any other type is placed by the date its look gives it: a date field, or when the item was created, last changed
///   or happened. A look that names no date, or a field the item holds no value in, places nothing.
///
/// A person who pointed the view at one date field (`field`) places every item by that field alone.
nonisolated struct ItemPlacement: Hashable, Sendable {
    /// What placing an item found.
    enum Outcome: Hashable, Sendable {
        case placed(ItemPlacement)
        /// The item's type has a date to place it by, and the item holds no value in it, or its look names none.
        case missing
        /// The date is there and is not one.
        case invalid(String)
        /// A field the person chose, which the item's type does not have.
        case notApplicable
    }

    /// The first moment of the item: its instant, or the start of its first day where `hasTime` is false.
    let start: Date
    /// Where it ends, exclusive, or nil where it has no end. A run of whole days ends at the start of the day after its
    /// last, and a single whole day at the start of the next, both in the Mac's calendar.
    let end: Date?
    /// Whether `start` names a time, rather than a whole day.
    let hasTime: Bool
    /// The value as the item holds it, for a help tag.
    let raw: String
    /// Whether the item is an event, which alone is said to be "all day".
    var isEvent = false

    /// Where `item` sits, by the date its `look` names or, where the person chose one, by `field`.
    static func of(
        _ item: Item, look: TypeLook, field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> Outcome {
        let info = catalogue.itemTypes[item.type]
        func hasDate(_ key: String) -> Bool { info?.fields.contains { $0.key == key && $0.kind.isDate } == true }
        func instant(_ date: Date?) -> Outcome {
            date.map { .placed(ItemPlacement(start: $0, end: nil, hasTime: true, raw: "")) } ?? .missing
        }
        if let field {
            return hasDate(field) ? value(of: field, in: item, calendar: calendar) : .notApplicable
        }
        switch look.date {
        case .field(let key): return hasDate(key) ? value(of: key, in: item, calendar: calendar) : .missing
        case .off, .created, .edited, .occurred: return instant(ItemMoment.stamp(look.date, of: item))
        }
    }

    private static func value(of key: String, in item: Item, calendar: Calendar) -> Outcome {
        guard let value = item.value(of: key), value != .null, value != .string("") else { return .missing }
        guard let text = value.string, let parsed = ItemDate.parse(text, calendar: calendar) else {
            return .invalid(ItemValueText.string(value))
        }
        if key == MarfaMapping.startField { return event(startingAt: text, parsed: parsed, of: item, calendar: calendar) }
        return .placed(ItemPlacement(start: parsed.date, end: nil, hasTime: parsed.hasTime, raw: text))
    }

    /// An event's start, which is read with the zone, the all-day flag and the end the event holds beside it.
    private static func event(startingAt text: String, parsed: ItemDate, of item: Item, calendar: Calendar) -> Outcome {
        guard let span = EventSpan(item: item, calendar: calendar) else {
            return .placed(ItemPlacement(start: parsed.date, end: nil, hasTime: parsed.hasTime, raw: text, isEvent: true))
        }
        let placed = span.placed(on: calendar)
        return .placed(ItemPlacement(start: placed.start, end: placed.end, hasTime: placed.hasTime, raw: text, isEvent: true))
    }
}

/// The moments every item has, which a look or a list can name: when it was created, last changed, or happened.
nonisolated enum ItemMoment {
    /// The moment `date` names, nil for a field, which only the item's type can read, and for no date at all.
    static func stamp(_ date: LookDate, of item: Item) -> Date? {
        switch date {
        case .created: item.created
        case .edited: item.trashed ?? item.modified
        case .occurred: item.occurred ?? item.created
        case .field, .off: nil
        }
    }
}
