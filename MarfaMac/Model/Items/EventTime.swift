import Foundation
import Marfa

/// An event's time as one value: where it starts and ends, whether it fills whole days, and the zone it is read in. The
/// type declares each of these as a field of its own, so the panel that edits them (`ValueEditKind.eventTime`) writes the
/// ones that changed together, in one edit and one undo step, and leaves the rest of the event as it was.
///
/// A whole-day event holds days, not moments: its end is the midnight that closes its last day (`EventSpan`), but the
/// panel shows and takes the last day itself, as a person says it ("Sat 28 to Sun 29 Nov").
nonisolated struct EventTime: Hashable, Sendable {
    /// The row's identifier on the page, which stands for the whole of the event's time.
    static let rowID = PagePlacement.when
    /// The fields an event keeps beside its start and end, which a type may or may not declare.
    static let allDayKey = "all_day"
    static let zoneKey = "timezone"

    let start: ItemTypeInfo.Field
    let end: ItemTypeInfo.Field?
    let allDay: ItemTypeInfo.Field?
    let zone: ItemTypeInfo.Field?

    /// Which end of the time a pick of a day or a time is for.
    enum Part: Hashable, Sendable { case start, end }

    /// The time an event type has, or nil where the type is no event or declares no start that takes a moment.
    static func of(_ type: TypeID, in catalogue: Catalogue) -> EventTime? {
        guard PageHeaderKind.of(type, in: catalogue) == .event, let info = catalogue.itemTypes[type] else { return nil }
        func field(_ key: String, where fits: (ItemTypeInfo.Field.Kind) -> Bool) -> ItemTypeInfo.Field? {
            info.fields.first { $0.key == key && fits($0.kind) }
        }
        func moment(_ kind: ItemTypeInfo.Field.Kind) -> Bool { if case .date(includesTime: true) = kind { true } else { false } }
        guard let start = field(MarfaMapping.startField, where: moment) else { return nil }
        return EventTime(
            start: start, end: field(MarfaMapping.endField, where: moment),
            allDay: field(Self.allDayKey) { $0 == .boolean }, zone: field(Self.zoneKey) { $0 == .text })
    }

    /// Every field the time is made of.
    var keys: Set<String> { Set([start.key] + [end, allDay, zone].compactMap { $0?.key }) }

    // MARK: Reading

    /// What the item holds, in the terms the panel works in.
    struct Reading: Equatable, Sendable {
        /// The instant it starts; for whole days, the midnight that opens the first day. Nil where the event has no start.
        var start: Date?
        /// The instant it ends; for whole days, the midnight that opens the last day. Nil where a timed event has no end.
        var end: Date?
        var allDay: Bool
        /// The zone the event names, nil where it names none.
        var zone: TimeZone?

        /// The calendar the days and the clock are read on: the event's own zone, else UTC for whole days (which no zone
        /// places), else the Mac's.
        func calendar(mac: Calendar) -> Calendar {
            var calendar = mac
            calendar.timeZone = zone ?? (allDay ? TimeZone(identifier: "UTC") ?? mac.timeZone : mac.timeZone)
            return calendar
        }
    }

    func reading(of item: Item, mac: Calendar) -> Reading {
        let named = item.value(of: Self.zoneKey)?.string.flatMap { TimeZone(identifier: $0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        guard let span = EventSpan(item: item, calendar: mac) else {
            var flag = false
            if case .bool(let held)? = item.value(of: Self.allDayKey) { flag = held }
            return Reading(start: nil, end: nil, allDay: flag, zone: named)
        }
        return Reading(
            start: span.wholeDays ? span.firstDay : span.start, end: span.wholeDays ? span.lastDay : span.end, allDay: span.wholeDays,
            zone: named)
    }

    // MARK: Changing

    /// Why a pick was not taken, in the person's words.
    enum Refusal: Error, Equatable, Sendable {
        case endBeforeStart
        /// The clock time the person typed does not exist on that day in the event's zone (a clock put forward).
        case noSuchTime

        var message: String {
            switch self {
            case .endBeforeStart: String(localized: "The end can’t be before the start.")
            case .noSuchTime: String(localized: "That time doesn’t exist on that day in this time zone.")
            }
        }
    }

    /// The reading with `day` chosen for `part`. Moving the start keeps the length; an end is taken only after the start.
    static func choosing(_ day: Date, for part: Part, in reading: Reading, mac: Calendar) throws(Refusal) -> Reading {
        let calendar = reading.calendar(mac: mac)
        var new = reading
        switch part {
        case .start:
            let old = reading.start
            let moment = Self.moving(day, to: calendar, keepingTimeOf: old ?? Self.defaultStart(on: day, calendar: calendar), whole: reading.allDay)
            new.start = moment
            if let old, let end = reading.end { new.end = end.addingTimeInterval(moment.timeIntervalSince(old)) }
        case .end:
            let basis = reading.end ?? reading.start ?? Self.defaultStart(on: day, calendar: calendar)
            let moment = Self.moving(day, to: calendar, keepingTimeOf: basis, whole: reading.allDay)
            if let start = reading.start, moment < start || (!reading.allDay && moment == start) { throw .endBeforeStart }
            new.end = moment
        }
        return new
    }

    /// The reading with the clock set for `part`: the day the part has, at `hour` and `minute`. A whole-day event has
    /// no clock to set.
    static func setting(
        hour: Int, minute: Int, for part: Part, in reading: Reading, mac: Calendar, now: Date
    ) throws(Refusal) -> Reading {
        guard !reading.allDay else { return reading }
        let calendar = reading.calendar(mac: mac)
        var new = reading
        // Strict: a time that is not on that day's clock is refused, never moved to the nearest one that is.
        func at(_ date: Date) throws(Refusal) -> Date {
            guard let moment = TimeOfDay.moment(hour: hour, minute: minute, on: date, calendar: calendar) else { throw .noSuchTime }
            return moment
        }
        switch part {
        case .start:
            let moment = try at(reading.start ?? now)
            new.start = moment
            if let old = reading.start, let end = reading.end { new.end = end.addingTimeInterval(moment.timeIntervalSince(old)) }
        case .end:
            let moment = try at(reading.end ?? reading.start ?? now)
            if let start = reading.start, moment <= start { throw .endBeforeStart }
            new.end = moment
        }
        return new
    }

    /// The reading with All Day switched. Timed to whole days keeps the days the event covers; whole days to timed starts
    /// at nine in the morning and runs an hour, the length a new event is given.
    static func setting(allDay: Bool, in reading: Reading, mac: Calendar, now: Date) -> Reading {
        guard allDay != reading.allDay else { return reading }
        let from = reading.calendar(mac: mac)
        var new = reading
        new.allDay = allDay
        let to = new.calendar(mac: mac)
        func midnight(of date: Date) -> Date {
            let parts = from.dateComponents([.year, .month, .day], from: date)
            return to.date(from: parts).map { to.startOfDay(for: $0) } ?? date
        }
        if allDay {
            new.start = midnight(of: reading.start ?? now)
            new.end = midnight(of: reading.end ?? reading.start ?? now)
        } else {
            let first = midnight(of: reading.start ?? now)
            let start = to.date(bySettingHour: 9, minute: 0, second: 0, of: first) ?? first
            new.start = start
            new.end = start.addingTimeInterval(3600)
        }
        return new
    }

    private static func defaultStart(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
    }

    /// `day` with the whole clock time of `basis`, or its midnight for whole days.
    private static func moving(_ day: Date, to calendar: Calendar, keepingTimeOf basis: Date, whole: Bool) -> Date {
        whole ? calendar.startOfDay(for: day) : TimeOfDay.keeping(clockOf: basis, on: day, calendar: calendar)
    }

    /// The properties to write for the person's change from `old` to `new`: only a part that changed, so a time the person
    /// did not touch stays exactly as the item holds it (marfa-mac#562), and nothing is written where nothing changed.
    func changes(from old: Reading, to new: Reading, in item: Item, mac: Calendar) -> [String: PropertyValue?] {
        var result: [String: PropertyValue?] = [:]
        let calendar = new.calendar(mac: mac)
        let switched = old.allDay != new.allDay
        if let allDay, switched { result[allDay.key] = .bool(new.allDay) }
        if let zone, old.zone?.identifier != new.zone?.identifier {
            result.updateValue(new.zone.map { .string($0.identifier) }, forKey: zone.key)
        }
        func text(_ date: Date) -> PropertyValue {
            .string(new.allDay ? ItemDate.day(date, calendar: calendar) : ItemDate.instant(date))
        }
        if let moment = new.start, old.start != moment || switched { result[start.key] = text(moment) }
        guard let end, old.end != new.end || switched else { return result }
        let holdsEnd = InspectorFields.hasValue(item.value(of: end.key))
        guard let last = new.end else {
            if holdsEnd { result.updateValue(nil, forKey: end.key) }
            return result
        }
        if new.allDay {
            // The end is the midnight that closes the last day. A single day with no end of its own needs none.
            let single = new.start.map { calendar.isDate(last, inSameDayAs: $0) } ?? false
            if single, !holdsEnd { return result }
            result[end.key] = text(calendar.date(byAdding: .day, value: 1, to: last) ?? last)
        } else {
            // A length that only the event's duration gives stays the duration's: the same length moved with the start.
            if !holdsEnd, !switched, let from = old.start, let to = old.end, let moved = new.start, last.timeIntervalSince(moved) == to.timeIntervalSince(from) {
                return result
            }
            result[end.key] = text(last)
        }
        return result
    }

    /// What taking the time away writes: the start and the end, wherever the item holds them. The zone and the whole-day
    /// flag are settings of the event, and stay.
    func clearing(in item: Item) -> [String: PropertyValue?] {
        var result: [String: PropertyValue?] = [:]
        for field in [start, end].compactMap({ $0 }) where InspectorFields.hasValue(item.value(of: field.key)) {
            result.updateValue(nil, forKey: field.key)
        }
        return result
    }

    /// The city a zone is named for, as the panel's menu says it: "London".
    static func name(of zone: TimeZone) -> String {
        zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
    }
}
