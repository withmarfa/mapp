import Foundation
import Marfa

/// When an event runs, read from the event's own fields: the one rule for its zone, whether it is a whole day or a run
/// of days, and where it ends. The event's page (`EventHeader`) and the lists that place it (`ItemPlacement`) both read it.
///
/// A whole day belongs to the zone it is lived in, and with none named, to UTC. An hour with no zone is an instant, which
/// reads in the reader's own zone. A timed event with no end has none here; the default length is the caller's to give.
nonisolated struct EventSpan: Sendable {
    /// The event holds a day, or a run of days, rather than hours.
    let wholeDays: Bool
    /// The calendars the start and the end are read in: the event's zone, and its end's zone where it names one.
    let inZone: Calendar
    let inEndZone: Calendar
    /// The instant it starts, or, for whole days, the start of its first day in the event's zone.
    let start: Date
    /// The instant it ends, or nil where it holds no end after its start. For whole days, the end as given, which
    /// `lastDay` and `placed(on:)` read as the midnight that closes the last day or a moment within it.
    let end: Date?
    /// The event's `precision`, where it names one.
    let precision: String?

    var zone: TimeZone { inZone.timeZone }
    var endZone: TimeZone { inEndZone.timeZone }

    /// The start of the day the event begins on, in its zone.
    var firstDay: Date { inZone.startOfDay(for: start) }

    /// The start of the day the event ends on, in its end's zone; the first day for a single day.
    var lastDay: Date {
        let first = firstDay
        guard let finish = end else { return first }
        let closes = inEndZone.startOfDay(for: finish) == finish
        return max(first, inEndZone.startOfDay(for: closes ? finish.addingTimeInterval(-1) : finish))
    }

    /// Nil where the event has no start that is a date.
    init?(item: Item, calendar: Calendar = .current, locale: Locale = .current) {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let startText = text(MarfaMapping.startField) else { return nil }
        var allDay = false
        if case .bool(let flag)? = item.value(of: "all_day") { allDay = flag }
        precision = text("precision")

        let named = text("timezone").flatMap { TimeZone(identifier: $0) }
        var inZone = Calendar(identifier: .gregorian)
        inZone.timeZone = named ?? (allDay ? TimeZone(identifier: "UTC")! : calendar.timeZone)
        inZone.locale = locale
        guard let parsed = ItemDate.parse(startText, calendar: inZone) else { return nil }
        var inEndZone = inZone
        if let endZone = text("end_timezone").flatMap({ TimeZone(identifier: $0) }) { inEndZone.timeZone = endZone }

        var finish = text(MarfaMapping.endField).flatMap { ItemDate.parse($0, calendar: inEndZone) }?.date
        if finish == nil, case .number(let seconds)? = item.value(of: "duration") {
            finish = parsed.date.addingTimeInterval(seconds.nearestDouble)
        }
        if let later = finish, later <= parsed.date { finish = nil }

        self.inZone = inZone
        self.inEndZone = inEndZone
        wholeDays = allDay || precision == "day" || !parsed.hasTime
        start = parsed.date
        end = finish
    }

    /// The span as a calendar lays it: where it starts, where it ends (exclusive), and whether the start names a time.
    /// Whole days are the days the event is lived in, laid on `calendar` as the same days whatever its zone, and end at
    /// the start of the day after the last.
    func placed(on calendar: Calendar) -> (start: Date, end: Date?, hasTime: Bool) {
        guard wholeDays else { return (start, end, true) }
        // The days are built on the Gregorian calendar the event counts them in, then read in the Mac's calendar.
        var local = Calendar(identifier: .gregorian)
        local.timeZone = calendar.timeZone
        func day(_ date: Date, in zoned: Calendar) -> Date {
            local.date(from: zoned.dateComponents([.year, .month, .day], from: date)).map { calendar.startOfDay(for: $0) } ?? date
        }
        let first = day(start, in: inZone)
        let last = max(first, day(lastDay, in: inEndZone))
        return (first, calendar.date(byAdding: .day, value: 1, to: last), false)
    }
}
