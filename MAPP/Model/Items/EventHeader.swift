import Foundation
import Marfa

/// When an event happens, for the first pin of its page: the date and time or the range, the zone and how far off it
/// is. Worked out from the event's own fields, in the event's own time zone, so the day an event falls on is the same
/// for every reader. It is laid out in the event's zone and ignores the Dates setting (`DateFormat`).
nonisolated struct EventHeader: Hashable, Sendable {
    /// "Thu 29 Oct, 10:00 to 11:00", or "Thu 29 Oct" for a whole day, or the dates of a run of days.
    let time: String
    /// "London time (BST)". Nil for a whole-day event, which has no hour to place.
    let zone: String?
    /// "All day" for a single whole day; nil for anything else, whose time says so.
    private let span: String?
    /// "in 2 days", "tomorrow", "Happening now".
    let relative: String

    /// The pin's help: all of its time, which a narrow page may cut, then the zone and how far off it is.
    var help: String {
        time + "\n" + [span, zone, relative].compactMap { $0 }.joined(separator: ", ")
    }

    /// The properties the pin says, which the property block leaves out.
    static let keys: Set<String> = [
        "starts_at", "ends_at", "duration", "all_day", "timezone", "end_timezone", "precision",
    ]

    /// Nil where the event has no start the pin can place: none, one that is not a date, or one known only to the
    /// month or the year, which no calendar day stands for. The fields then stay in the property block.
    init?(item: Item, now: Date, calendar: Calendar = .current, locale: Locale = .current) {
        func text(_ key: String) -> String? {
            item.value(of: key)?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        guard let startText = text("starts_at") else { return nil }
        let precision = text("precision")
        guard precision != "year", precision != "month" else { return nil }
        var allDay = false
        if case .bool(let flag)? = item.value(of: "all_day") { allDay = flag }

        // A whole day belongs to the zone it is lived in, and with none named, to UTC. An hour with no zone is an
        // instant, which reads in the reader's own.
        let named = text("timezone").flatMap { TimeZone(identifier: $0) }
        let eventZone = named ?? (allDay ? TimeZone(identifier: "UTC")! : calendar.timeZone)
        var inZone = Calendar(identifier: .gregorian)
        inZone.timeZone = eventZone
        inZone.locale = locale
        guard let start = ItemDate.parse(startText, calendar: inZone) else { return nil }
        let wholeDays = allDay || precision == "day" || !start.hasTime

        let endZone = text("end_timezone").flatMap { TimeZone(identifier: $0) } ?? eventZone
        var inEndZone = inZone
        inEndZone.timeZone = endZone
        var end = text("ends_at").flatMap { ItemDate.parse($0, calendar: inEndZone) }?.date
        if end == nil, case .number(let seconds)? = item.value(of: "duration") {
            end = start.date.addingTimeInterval((seconds as NSDecimalNumber).doubleValue)
        }
        if let finish = end, finish <= start.date { end = nil }

        func style(_ calendar: Calendar) -> Date.FormatStyle {
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        }
        // A date in another year says which, since the page has no other place for it.
        func dayText(_ date: Date, in calendar: Calendar) -> String {
            let day = style(calendar).weekday(.abbreviated).day().month(.abbreviated)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return date.formatted(sameYear ? day : day.year())
        }

        if wholeDays {
            let first = inZone.startOfDay(for: start.date)
            var last = first
            if let finish = end {
                // A whole-day event ends at the midnight that closes its last day.
                let closes = inEndZone.startOfDay(for: finish) == finish
                last = max(first, inEndZone.startOfDay(for: closes ? finish.addingTimeInterval(-1) : finish))
            }
            if last == first {
                time = dayText(first, in: inZone)
                span = String(localized: "All day")
            } else {
                time = String(localized: "\(dayText(first, in: inZone)) to \(dayText(last, in: inEndZone))")
                span = nil
            }
            zone = nil
            relative = Self.relative(from: now, start: first, last: last, finish: nil, zone: inZone, locale: locale)
        } else {
            func clock(_ date: Date, in calendar: Calendar) -> String { date.formatted(style(calendar).hour().minute()) }
            func moment(_ date: Date, in calendar: Calendar) -> String {
                "\(dayText(date, in: calendar)), \(clock(date, in: calendar))"
            }
            if let finish = end {
                if endZone == eventZone && inZone.isDate(start.date, inSameDayAs: finish) {
                    time = String(localized: "\(moment(start.date, in: inZone)) to \(clock(finish, in: inZone))")
                } else {
                    // Another day, or another zone at the far end, says which.
                    var endText = moment(finish, in: inEndZone)
                    if endZone != eventZone { endText += " (\(Self.abbreviation(endZone, at: finish)))" }
                    time = String(localized: "\(moment(start.date, in: inZone)) to \(endText)")
                }
            } else {
                time = moment(start.date, in: inZone)
            }
            span = nil
            zone = Self.zoneLabel(eventZone, at: start.date)
            relative = Self.relative(from: now, start: start.date, last: nil, finish: end, zone: inZone, locale: locale)
        }
    }

    /// "London time (BST)": the city the zone is named for, and its short name at that moment. UTC has no city.
    static func zoneLabel(_ zone: TimeZone, at date: Date) -> String {
        let city = zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? zone.identifier
        let short = abbreviation(zone, at: date)
        return city == short ? city : String(localized: "\(city) time (\(short))")
    }

    private static func abbreviation(_ zone: TimeZone, at date: Date) -> String {
        zone.abbreviation(for: date) ?? zone.identifier
    }

    /// How far off the event is, from `now`. A day counts on the event's own calendar, so "tomorrow" agrees with
    /// the date the pin shows. An event under way says so, and one today is told in hours or minutes.
    static func relative(from now: Date, start: Date, last: Date?, finish: Date?, zone: Calendar, locale: Locale) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.calendar = zone
        formatter.dateTimeStyle = .named
        formatter.unitsStyle = .full
        let today = zone.startOfDay(for: now)
        let first = zone.startOfDay(for: start)
        if let last {
            // A run of whole days is under way from its first day to its last.
            if today >= first, today <= last, last > first { return String(localized: "Happening now") }
        } else if let finish, start <= now, now < finish {
            return String(localized: "Happening now")
        }
        let days = zone.dateComponents([.day], from: today, to: first).day ?? 0
        if last != nil || days != 0 { return formatter.localizedString(from: DateComponents(day: days)) }
        return formatter.localizedString(for: start, relativeTo: now)
    }
}
