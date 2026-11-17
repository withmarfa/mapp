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

    /// Where `item` sits, by the date its `look` names or, where the person chose one, by `field`.
    static func of(
        _ item: Item, look: TypeLook, field: String?, catalogue: Catalogue, calendar: Calendar = .current
    ) -> Outcome {
        let info = catalogue.itemTypes[item.type]
        func hasDate(_ key: String) -> Bool { info?.fields.contains { $0.key == key && $0.kind.isDate } == true }
        func instant(_ date: Date) -> Outcome {
            .placed(ItemPlacement(start: date, end: nil, hasTime: true, raw: ""))
        }
        if let field {
            return hasDate(field) ? value(of: field, in: item, calendar: calendar) : .notApplicable
        }
        switch look.date {
        case .off: return .missing
        case .created: return instant(item.created)
        case .edited: return instant(item.trashed ?? item.modified)
        case .occurred: return instant(item.occurred ?? item.created)
        case .field(let key): return hasDate(key) ? value(of: key, in: item, calendar: calendar) : .missing
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
        func held(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        var allDay = false
        if case .bool(let flag)? = item.value(of: "all_day") { allDay = flag }
        let wholeDays = allDay || held("precision") == "day" || !parsed.hasTime

        // A whole day belongs to the zone it is lived in, and with none named, to UTC. A timed event with none is an
        // instant, which needs no zone to be placed.
        let named = held("timezone").flatMap { TimeZone(identifier: $0) }
        var inZone = Calendar(identifier: .gregorian)
        inZone.timeZone = named ?? (allDay ? TimeZone(identifier: "UTC")! : calendar.timeZone)
        var inEndZone = inZone
        if let endZone = held("end_timezone").flatMap({ TimeZone(identifier: $0) }) { inEndZone.timeZone = endZone }

        let zonedStart = ItemDate.parse(text, calendar: inZone) ?? parsed
        var finish = held(MarfaMapping.endField).flatMap { ItemDate.parse($0, calendar: inEndZone) }?.date
        if finish == nil, case .number(let seconds)? = item.value(of: "duration") {
            finish = zonedStart.date.addingTimeInterval(seconds.nearestDouble)
        }
        if let later = finish, later <= zonedStart.date { finish = nil }

        guard wholeDays else {
            return .placed(ItemPlacement(start: zonedStart.date, end: finish, hasTime: true, raw: text))
        }
        // The days as the event's zone counts them, laid on the Mac's calendar as the same days.
        func day(_ date: Date, in zoned: Calendar) -> Date {
            calendar.date(from: zoned.dateComponents([.year, .month, .day], from: date)).map { calendar.startOfDay(for: $0) } ?? date
        }
        let first = day(zonedStart.date, in: inZone)
        var last = first
        if let later = finish {
            // A run of whole days ends at the midnight that closes its last day.
            let closes = inEndZone.startOfDay(for: later) == later
            last = max(first, day(closes ? later.addingTimeInterval(-1) : later, in: inEndZone))
        }
        let end = calendar.date(byAdding: .day, value: 1, to: last)
        return .placed(ItemPlacement(start: first, end: end, hasTime: false, raw: text))
    }
}
