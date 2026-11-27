import Foundation

/// How the app writes the dates and times it shows, as the person chose in Settings > General > Dates and Times. It is
/// one value in the defaults (`key`), read as JSON, so a change reaches every list, table, header and inspector that
/// watches the key.
nonisolated struct DateFormat: Hashable, Sendable, RawRepresentable {
    /// How an absolute date is written. `system` keeps each place's own way, in the system's formats.
    enum DateStyle: String, CaseIterable, Identifiable, Sendable, Codable {
        /// Abbreviated in a value, the system's short date in a list and a day and month in a table.
        case system
        /// The date in numbers: 27/10/2026.
        case numeric
        /// The month shortened: 27 Oct 2026.
        case abbreviated
        /// The month in full: 27 October 2026.
        case long

        var id: Self { self }
    }

    /// The clock a time is read on.
    enum TimeStyle: String, CaseIterable, Identifiable, Sendable, Codable {
        case system
        case twelveHour
        case twentyFourHour

        var id: Self { self }

        var hourCycle: Locale.HourCycle? {
            switch self {
            case .system: nil
            case .twelveHour: .oneToTwelve
            case .twentyFourHour: .zeroToTwentyThree
            }
        }
    }

    /// Whether a list or a table says Today, Yesterday and the weekday instead of the date, while it is recent.
    var usesWords = true
    var date = DateStyle.system
    var time = TimeStyle.system

    static let key = "dateFormat"
    /// Each entry is a stored value that could not be read, in the order it was found.
    static let setAsideKey = "dateFormatSetAside"
    static let standard = DateFormat()

    init(usesWords: Bool = true, date: DateStyle = .system, time: TimeStyle = .system) {
        self.usesWords = usesWords
        self.date = date
        self.time = time
    }

    // RawRepresentable's own `==` and `hash(into:)` would encode the JSON form each time, and every table cell compares
    // its format whenever the table is drawn.
    static func == (lhs: DateFormat, rhs: DateFormat) -> Bool {
        lhs.usesWords == rhs.usesWords && lhs.date == rhs.date && lhs.time == rhs.time
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(usesWords)
        hasher.combine(date)
        hasher.combine(time)
    }

    /// The stored form. A field it lacks is the standard's, so a value saved before the field existed still reads.
    private struct Stored: Codable {
        var usesWords: Bool?
        var date: DateStyle?
        var time: TimeStyle?
    }

    /// A stored value that does not read gives the standard format.
    init?(rawValue: String) {
        guard let stored = try? JSONDecoder().decode(Stored.self, from: Data(rawValue.utf8)) else { return nil }
        self.init(usesWords: stored.usesWords ?? true, date: stored.date ?? .system, time: stored.time ?? .system)
    }

    var rawValue: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let stored = Stored(usesWords: usesWords, date: date, time: time)
        return (try? encoder.encode(stored)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    /// The stored format, or the standard where none is stored or it does not read. A value that does not read is first
    /// set aside (`setAsideUnreadable`), never translated.
    @MainActor
    static func stored(in defaults: UserDefaults = .standard) -> DateFormat {
        setAsideUnreadable(in: defaults)
        return defaults.string(forKey: key).flatMap(Self.init(rawValue:)) ?? standard
    }

    /// Keeps a stored value that does not read, such as an older version's word, under `setAsideKey` and removes it, so
    /// the page starts from the standard and a change writes over nothing. Run at launch, before any view writes.
    @MainActor
    static func setAsideUnreadable(in defaults: UserDefaults = .standard) {
        guard let value = defaults.object(forKey: key) else { return }
        let text = value as? String ?? String(describing: value)
        guard Self(rawValue: text) == nil else { return }
        defaults.set((defaults.stringArray(forKey: setAsideKey) ?? []) + [text], forKey: setAsideKey)
        PreferenceHolds.willWrite(nil, forKey: key, in: defaults)
        defaults.removeObject(forKey: key)
    }

    /// `locale` read on the chosen clock.
    func locale(_ locale: Locale) -> Locale {
        guard let hourCycle = time.hourCycle else { return locale }
        var components = Locale.Components(locale: locale)
        components.hourCycle = hourCycle
        return Locale(components: components)
    }
}

/// The one place a date becomes text, so a choice of format reaches every list, table, header and inspector alike.
/// The package reads and writes the contract's forms (`Marfa.ItemDate`); this only decides how a moment reads.
nonisolated enum DateDisplay {
    /// Where the date is shown, since a row has little room and a value is read by itself.
    enum Place: Sendable {
        /// A property, the inspector or a version: the day, and the time where there is one.
        case value
        /// A line of the list, where the time shows only today.
        case list
        /// A cell of the table, where a day is all there is, except that a stamp of the item's (`hasTime`) reads as its time today.
        /// Every date column of every table reads this way.
        case table
    }

    /// `hasTime` is false for a value that names only a day. `now` matters only to the words of a list and a table.
    static func text(
        of date: Date, hasTime: Bool = true, place: Place, format: DateFormat, now: Date = .now,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        let locale = format.locale(locale)
        switch place {
        case .value:
            return absolute(date, hasTime: hasTime, style: style(format.date, system: .abbreviated), calendar: calendar, locale: locale)
        case .list:
            guard format.usesWords else {
                return absolute(date, hasTime: false, style: style(format.date, system: .numeric), calendar: calendar, locale: locale)
            }
            return listLabel(date, now: now, format: format, calendar: calendar, locale: locale)
        case .table:
            guard format.usesWords else { return dated(date, now: now, format: format, calendar: calendar, locale: locale) }
            if hasTime, calendar.isDate(date, inSameDayAs: now) { return timeOfDay(of: date, format: format, calendar: calendar, locale: locale) }
            return dayLabel(date, now: now, format: format, calendar: calendar, locale: locale)
        }
    }

    static func style(_ choice: DateFormat.DateStyle, system: Date.FormatStyle.DateStyle) -> Date.FormatStyle.DateStyle {
        switch choice {
        case .system: system
        case .numeric: .numeric
        case .abbreviated: .abbreviated
        case .long: .long
        }
    }

    private static func absolute(
        _ date: Date, hasTime: Bool, style: Date.FormatStyle.DateStyle, calendar: Calendar, locale: Locale
    ) -> String {
        date.formatted(Date.FormatStyle(
            date: style, time: hasTime ? .shortened : .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
    }

    /// The time of day alone, which a row shows inside the group of a day, where the day is already said. It is
    /// written as a list line writes the time today, so a row reads the same in any group.
    static func timeOfDay(
        of date: Date, format: DateFormat = .standard, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        date.formatted(Date.FormatStyle(locale: format.locale(locale), calendar: calendar, timeZone: calendar.timeZone).hour().minute())
    }

    /// The label of an hour on the clock, as a calendar's gutter has it, read on a day that has no daylight saving
    /// change so the hour a change skips still has its label.
    static func hourLabel(_ hour: Int, format: DateFormat = .standard, locale: Locale = .current) -> String {
        var plain = Calendar(identifier: .gregorian)
        plain.timeZone = .gmt
        let date = plain.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: hour))
            ?? Date(timeIntervalSinceReferenceDate: TimeInterval(hour * 3600))
        return date.formatted(Date.FormatStyle(locale: format.locale(locale), calendar: plain, timeZone: .gmt).hour())
    }

    /// A day without words: the day and month, with the year when it is not this one, unless the person chose how a
    /// date is written.
    private static func dated(_ date: Date, now: Date, format: DateFormat, calendar: Calendar, locale: Locale) -> String {
        if format.date != .system {
            return absolute(date, hasTime: false, style: style(format.date, system: .abbreviated), calendar: calendar, locale: locale)
        }
        let sameYear = calendar.isDate(date, equalTo: now, toGranularity: .year)
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        if !sameYear { style = style.year() }
        return date.formatted(style)
    }

    /// As Mail writes it: the time today, "Yesterday", the weekday within the week, and the short date before that. A
    /// day to come, such as a due date or the start of an event, is a day as people say it.
    private static func listLabel(_ date: Date, now: Date, format: DateFormat, calendar: Calendar, locale: Locale) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        switch daysAgo {
        case ..<0:
            return dayLabel(date, now: now, format: format, calendar: calendar, locale: locale)
        case 0:
            style = style.hour().minute()
        case 1:
            return String(localized: "Yesterday")
        case 2...6:
            style = style.weekday(.wide)
        default:
            return absolute(date, hasTime: false, style: self.style(format.date, system: .numeric), calendar: calendar, locale: locale)
        }
        return date.formatted(style)
    }

    /// A day as people say it: Today, Yesterday, Tomorrow, a weekday within a week, then the date.
    private static func dayLabel(_ date: Date, now: Date, format: DateFormat, calendar: Calendar, locale: Locale) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
        switch days {
        case 0: return String(localized: "Today")
        case -1: return String(localized: "Yesterday")
        case 1: return String(localized: "Tomorrow")
        case -6...(-2), 2...6:
            return date.formatted(Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).weekday(.wide))
        default:
            return dated(date, now: now, format: format, calendar: calendar, locale: locale)
        }
    }
}
