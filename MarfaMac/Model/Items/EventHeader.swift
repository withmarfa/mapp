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
        guard let event = EventSpan(item: item, calendar: calendar, locale: locale) else { return nil }
        guard event.precision != "year", event.precision != "month" else { return nil }
        let (inZone, inEndZone) = (event.inZone, event.inEndZone)
        let (eventZone, endZone) = (event.zone, event.endZone)
        let end = event.end

        func style(_ calendar: Calendar) -> Date.FormatStyle {
            Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        }
        // A date in another year says which, since the page has no other place for it.
        func dayText(_ date: Date, in calendar: Calendar) -> String {
            let day = style(calendar).weekday(.abbreviated).day().month(.abbreviated)
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            return date.formatted(sameYear ? day : day.year())
        }

        if event.wholeDays {
            let (first, last) = (event.firstDay, event.lastDay)
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
                if endZone == eventZone && inZone.isDate(event.start, inSameDayAs: finish) {
                    time = String(localized: "\(moment(event.start, in: inZone)) to \(clock(finish, in: inZone))")
                } else {
                    // Another day, or another zone at the far end, says which.
                    var endText = moment(finish, in: inEndZone)
                    if endZone != eventZone { endText += " (\(Self.abbreviation(endZone, at: finish)))" }
                    time = String(localized: "\(moment(event.start, in: inZone)) to \(endText)")
                }
            } else {
                time = moment(event.start, in: inZone)
            }
            span = nil
            zone = Self.zoneLabel(eventZone, at: event.start)
            relative = Self.relative(from: now, start: event.start, last: nil, finish: end, zone: inZone, locale: locale)
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
