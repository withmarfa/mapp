import Foundation
import Marfa

/// How a column groups a place's items, beside which column (`ItemTableOptions.Grouping`).
nonisolated enum GroupMode: Hashable, Sendable {
    /// One group per value: a choice's options, a status's words, a parent, a type.
    case value
    /// A date's day, week, month or year, as a view's `group.bucket` names it.
    case bucket(LibraryViewGroup.Bucket)
    /// Whether the field holds a value: Not Set where it is missing or null, as Marfa's `not_exists` selects, and Set
    /// otherwise, an empty text or list included. Keyed `false` and `true`.
    case presence
    /// Marfa's four status groups, then No Status, each item by its own type's status field.
    case statusGroups

    var bucket: LibraryViewGroup.Bucket? {
        if case .bucket(let bucket) = self { bucket } else { nil }
    }

    /// Whether a saved view can hold the grouping. Marfa's group has no presence span and no status groups yet, so
    /// those stay in a place's default view and are named as not kept on Save as View (`ViewDraft.Unkept.groupMode`).
    var isKeptByView: Bool {
        switch self {
        case .value, .bucket: true
        case .presence, .statusGroups: false
        }
    }

    /// The choice's name under its field: Words, Groups, Day and the rest, Set or Not Set.
    var title: String {
        switch self {
        case .value: String(localized: "Words")
        case .bucket(let bucket): bucket.title
        case .presence: String(localized: "Set or Not Set")
        case .statusGroups: String(localized: "Groups")
        }
    }
}

/// The keys of the groups every grouping may make beside its values.
nonisolated enum GroupKey {
    /// The items with no value, which Marfa keys `null`.
    static let none = ""
    /// The items whose type does not declare the field grouped by, last of all.
    static let notApplicable = "\u{1}notApplicable"
    /// Set or Not Set's groups, as Marfa keys them.
    static let notSet = "false"
    static let set = "true"

    /// A group's key as a view's `group.order` and `group.hidden` hold it: the null group is `null`, a yes-or-no's a
    /// bool, any other a string. Not Applicable is the app's own and is never written.
    static func json(_ key: String, booleans: Bool) -> JSONValue? {
        if key == none { return .null }
        if key == notApplicable { return nil }
        if booleans, key == "true" || key == "false" { return .bool(key == "true") }
        return .string(key)
    }

    /// A key a view's lists name, as the window keys its groups.
    static func key(of value: JSONValue) -> String? {
        switch value {
        case .null: none
        case .bool(let flag): flag ? "true" : "false"
        case .string(let text): text
        case .integer(let number): "\(number)"
        case .number(let number): "\(number)"
        default: nil
        }
    }
}

nonisolated extension LibraryViewGroup.Bucket {
    /// The span's name in a menu: Day, Week, Month, Year.
    var title: String {
        switch self {
        case .day: String(localized: "Day")
        case .week: String(localized: "Week")
        case .month: String(localized: "Month")
        case .year: String(localized: "Year")
        }
    }
}

/// Groups of dates: the span each covers, its key as Marfa names it, and its title.
nonisolated enum DateGroups {
    /// The calendar a saved view's dates are grouped on: weeks start on Monday, as Marfa fixes them for every app
    /// (`device/view-date-bucket`), whatever Settings says. A place's own grouping follows Settings (`Calendar.chosenWeekStart`).
    static func viewCalendar(_ base: Calendar = .current) -> Calendar {
        var calendar = base
        calendar.firstWeekday = 2
        return calendar
    }

    /// The first moment of the day, week, month or year that holds `date`.
    static func start(of date: Date, bucket: LibraryViewGroup.Bucket, calendar: Calendar) -> Date {
        let component: Calendar.Component = switch bucket {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
        return calendar.dateInterval(of: component, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// A group's key as Marfa names it: its first day, `YYYY-MM-DD`, on the calendar's clock. Keys sort as their days do.
    static func key(of date: Date, bucket: LibraryViewGroup.Bucket, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: start(of: date, bucket: bucket, calendar: calendar))
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The day a key names, on the calendar's clock.
    static func day(ofKey key: String, calendar: Calendar) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    /// How a group reads: Today, Yesterday or Tomorrow, else the day; "Week of 16 Nov"; "November 2026"; "2026". A
    /// day or week in another year names the year.
    static func title(ofKey key: String, bucket: LibraryViewGroup.Bucket, now: Date, calendar: Calendar) -> String {
        guard let day = day(ofKey: key, calendar: calendar) else { return key }
        let style = Date.FormatStyle(locale: calendar.locale ?? .current, calendar: calendar, timeZone: calendar.timeZone)
        let sameYear = calendar.component(.year, from: day) == calendar.component(.year, from: now)
        switch bucket {
        case .day:
            let today = calendar.startOfDay(for: now)
            switch calendar.dateComponents([.day], from: today, to: day).day {
            case 0: return String(localized: "Today")
            case -1: return String(localized: "Yesterday")
            case 1: return String(localized: "Tomorrow")
            default:
                let shown = style.weekday(.abbreviated).day().month(.abbreviated)
                return day.formatted(sameYear ? shown : shown.year())
            }
        case .week:
            let shown = style.day().month(.abbreviated)
            let first = day.formatted(sameYear ? shown : shown.year())
            return String(localized: "Week of \(first)")
        case .month:
            return day.formatted(style.month(.wide).year())
        case .year:
            return day.formatted(style.year())
        }
    }
}

nonisolated extension ItemTableColumn {
    /// Whether the column can group as `mode` says: each value of a column with a few to pick from, a date's span,
    /// whether a field or Happened is set, or a status by its groups.
    func groups(by mode: GroupMode) -> Bool {
        switch mode {
        case .value: isCategorical
        case .bucket: isDated
        case .presence: field != nil || content == .occurred
        case .statusGroups: style == .status
        }
    }

    /// Whether a row holds a value in the column, as Marfa's `exists` tests it: a missing or null value is not set, and
    /// anything else is, an empty text or list included.
    func isSet(in row: ItemTableRow) -> Bool {
        switch content {
        case .field(let field):
            guard let value = row.item.value(of: field.key) else { return false }
            return value != .null
        case .occurred: return row.item.occurred != nil
        default: return true
        }
    }

    /// The values a grouping by each value lists before any row holds them: a choice's options, a status's words, Yes
    /// and No.
    var declaredValues: Set<String> {
        switch style {
        case .status, .priority, .choice: Set((field?.options ?? []).filter { !$0.isEmpty })
        case .boolean: ["true", "false"]
        default: []
        }
    }

    /// Whether the column holds a date, which groups by day, week, month or year.
    var isDated: Bool {
        switch content {
        case .created, .edited, .occurred: true
        case .field: style == .date
        default: false
        }
    }

    /// The date a row holds in the column, read on the calendar's clock, or nil where it holds none or one that is not a
    /// date: Marfa puts both in the group with no value (`device/view-date-missing`). Happened has no fallback here, since
    /// Marfa groups by `occurred_at` alone.
    func date(of row: ItemTableRow, calendar: Calendar) -> Date? {
        switch content {
        case .created: return row.item.created
        case .edited: return row.item.modified
        case .occurred: return row.item.occurred
        case .field(let field):
            guard style == .date, let text = row.item.value(of: field.key)?.string else { return nil }
            return ItemDate.parse(text, calendar: calendar)?.date
        default: return nil
        }
    }
}
