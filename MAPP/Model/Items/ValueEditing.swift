import Foundation
import Marfa

/// The values that open in a panel under them, in the inspector and on the page: what the field is, whatever it is
/// called. A text, a number, a yes or no and every other list stay in the inspector's own controls.
nonisolated enum ValueEditKind: Hashable, Sendable {
    case status(ItemTypeInfo.Field)
    case choice(ItemTypeInfo.Field)
    case date(ItemTypeInfo.Field)
    case people(ItemTypeInfo.Field, ListShape)
    /// The item's own tags, which no field holds.
    case tags

    /// How the field is edited in a panel, or nil where it is not.
    init?(field: ItemTypeInfo.Field) {
        switch field.kind {
        case .status where field.isPicked: self = .status(field)
        case .choice where field.isPicked: self = .choice(field)
        case .date: self = .date(field)
        case .list(let shape) where shape.holdsPeople: self = .people(field, shape)
        default: return nil
        }
    }

    var field: ItemTypeInfo.Field? {
        switch self {
        case .status(let field), .choice(let field), .date(let field), .people(let field, _): field
        case .tags: nil
        }
    }

    /// Whether choosing a value is the whole of the edit, so the panel closes on it.
    var closesOnChoice: Bool {
        switch self {
        case .status, .choice: true
        case .date, .people, .tags: false
        }
    }
}

/// One line of a list in a value panel or a menu.
nonisolated struct ValueListRow: Identifiable, Hashable, Sendable {
    enum Role: Hashable, Sendable { case header, option, create, separator }
    enum Mark: Hashable, Sendable {
        case none
        case status(StatusGroup?)
        case person(initials: String)
        case tag
        case symbol(String)
    }

    let id: String
    var role: Role
    var title: String
    var detail: String?
    var mark: Mark = .none
    /// The value the item holds now, or a person or tag it has now.
    var isCurrent = false

    static func header(_ title: String, id: String) -> ValueListRow { .init(id: id, role: .header, title: title) }
    static let separator = ValueListRow(id: "separator", role: .separator, title: "")
}

/// The rows the lists in a value panel show, from the catalogue and what the item holds; pure, so the panel, the
/// menu and the tests agree.
nonisolated enum ValueEditOptions {
    static let notSetID = "not-set"
    static let optionPrefix = "option:"

    static func optionID(_ word: String) -> String { optionPrefix + word }

    /// The word a row chooses, or nil for Not Set and for a row that is not an option.
    static func word(of rowID: String) -> String? {
        rowID.hasPrefix(optionPrefix) ? String(rowID.dropFirst(optionPrefix.count)) : nil
    }

    /// A status field's words, each under its group in the order groups are always listed in. A word the type does not
    /// declare, which an item can still hold, is listed under Other so the value it has is always shown. Not Set closes
    /// the list unless the field requires a value.
    static func statusRows(field: ItemTypeInfo.Field, current: String?) -> [ValueListRow] {
        guard case .status(let words) = field.kind else { return [] }
        var rows: [ValueListRow] = []
        func option(_ word: String, group: StatusGroup?) -> ValueListRow {
            ValueListRow(id: optionID(word), role: .option, title: ItemTypeInfo.Field.label(ofOption: word), mark: .status(group), isCurrent: word == current)
        }
        for group in StatusGroup.allCases {
            let inGroup = words.filter { $0.group == group }
            guard !inGroup.isEmpty else { continue }
            rows.append(.header(StatusBucket.group(group).title, id: "header:" + group.rawValue))
            rows += inGroup.map { option($0.value, group: group) }
        }
        if let current, !current.isEmpty, !words.contains(where: { $0.value == current }) {
            rows.append(.header(StatusBucket.other.title, id: "header:other"))
            rows.append(option(current, group: nil))
        }
        return rows + notSet(field: field, current: current)
    }

    /// A choice's options in the catalogue's order, then Not Set unless the field requires a value. The item's own
    /// word is listed last where the catalogue does not declare it.
    static func choiceRows(field: ItemTypeInfo.Field, current: String?) -> [ValueListRow] {
        let rows = field.options(including: current).map {
            ValueListRow(id: optionID($0), role: .option, title: ItemTypeInfo.Field.label(ofOption: $0), isCurrent: $0 == current)
        }
        return rows + notSet(field: field, current: current)
    }

    private static func notSet(field: ItemTypeInfo.Field, current: String?) -> [ValueListRow] {
        guard !field.required else { return [] }
        return [.separator, ValueListRow(id: notSetID, role: .option, title: String(localized: "Not Set"), isCurrent: current == nil || current == "")]
    }
}

/// The days a date panel offers before its calendar, in the person's calendar.
nonisolated enum QuickDates {
    struct Entry: Hashable, Identifiable, Sendable {
        let id: String
        let title: String
        let symbol: String
        let date: Date
    }

    /// Today, tomorrow and the first day of next week, as the person's calendar counts the week.
    static func entries(now: Date, calendar: Calendar) -> [Entry] {
        let today = calendar.startOfDay(for: now)
        var entries = [Entry(id: "today", title: String(localized: "Today"), symbol: "sun.max", date: today)]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            entries.append(Entry(id: "tomorrow", title: String(localized: "Tomorrow"), symbol: "arrow.right.circle", date: tomorrow))
        }
        if let week = calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday), matchingPolicy: .nextTime) {
            entries.append(Entry(id: "next-week", title: String(localized: "Next Week"), symbol: "calendar.badge.clock", date: week))
        }
        return entries
    }

    /// The day beside a quick date, such as "Tue 3 Nov".
    static func detail(of entry: Entry, calendar: Calendar, locale: Locale) -> String {
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.abbreviated).day().month(.abbreviated)
        return entry.date.formatted(style)
    }

    /// The date to store for choosing `day`: with a time, the day at the time the item already holds, else at the
    /// start of the day.
    static func moment(on day: Date, keepingTimeOf current: Date?, calendar: Calendar) -> Date {
        guard let current else { return calendar.startOfDay(for: day) }
        let time = calendar.dateComponents([.hour, .minute], from: current)
        return calendar.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: 0, of: day) ?? day
    }
}

/// The people a list of people can offer: those other items hold in the same kind of list. The library has no list of
/// people to choose from, so this is the cheapest honest source.
nonisolated enum PeopleSuggestions {
    struct Person: Hashable, Sendable {
        let name: String
        let entry: ListEntries.Entry

        /// Two entries are the same person when their words match, whatever else the entry carries.
        var identity: String { name.lowercased() }
    }

    /// The distinct people in the lists, most often named first, then by name.
    static func pool(from lists: [PropertyValue?], shape: ListShape) -> [Person] {
        var counts: [String: (person: Person, count: Int)] = [:]
        for list in lists {
            for case let entry? in ListEntries.entries(of: list).map(ListEntries.object) {
                guard let name = shape.personName(of: entry) else { continue }
                let person = Person(name: name, entry: entry)
                counts[person.identity, default: (person, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending }
            .map(\.person)
    }

    /// The people to offer for what is typed: those whose name or any member contains it, less those already held.
    static func matching(_ typed: String, in pool: [Person], excluding held: [Person]) -> [Person] {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(held.map(\.identity))
        return pool.filter { person in
            !taken.contains(person.identity)
                && (typed.isEmpty || person.entry.values.contains { $0.string?.localizedStandardContains(typed) == true })
        }
    }

    /// The people a list already holds.
    static func held(in list: PropertyValue?, shape: ListShape) -> [Person] {
        ListEntries.entries(of: list).compactMap { value in
            guard let entry = ListEntries.object(value), let name = shape.personName(of: entry) else { return nil }
            return Person(name: name, entry: entry)
        }
    }

    /// The entry a typed name makes: an address goes in the address member and a name in the name member, and a list
    /// that requires the name member is given the address there too. Nil where nothing is typed.
    static func entry(from typed: String, shape: ListShape) -> ListEntries.Entry? {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, shape.members.count >= 2 else { return nil }
        let (name, address) = (shape.members[0], shape.members[1])
        let isAddress = text.contains("@") && !text.contains(where: \.isWhitespace)
        var entry: ListEntries.Entry = [:]
        if isAddress {
            entry[address.key] = .string(text)
            if name.required { entry[name.key] = .string(text) }
        } else {
            entry[name.key] = .string(text)
        }
        return entry
    }
}
