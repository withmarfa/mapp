import Foundation
import Marfa

/// The values that open in a panel under them, in a form and on the page: what the field is, whatever it is
/// called. A yes or no is two rows, a list of people or words adds and takes away, and any other list of entries is
/// edited member by member in the same panel.
nonisolated enum ValueEditKind: Hashable, Sendable {
    case status(ItemTypeInfo.Field)
    case choice(ItemTypeInfo.Field)
    case date(ItemTypeInfo.Field)
    case people(ItemTypeInfo.Field, ListShape)
    /// A yes or no, chosen from two rows.
    case yesNo(ItemTypeInfo.Field)
    /// A list of entries with members, such as emails and phone numbers with their labels: one block for each entry.
    case entries(ItemTypeInfo.Field, ListShape)
    /// A text of any format, which may run to many lines.
    case text(ItemTypeInfo.Field)
    case number(ItemTypeInfo.Field)
    /// A list of words, such as labels.
    case words(ItemTypeInfo.Field)
    /// The item's own tags, which no field holds.
    case tags
    /// The items the item is linked to through one edge field, named as `ItemLibrary.relationFields(of:)` names it (the
    /// parent's `child-of`, the collections' `in-collection`, an inverse as `inverse:` and the edge type): no field of the
    /// type holds them. Several items at once take only the collections.
    case relation(String)
    /// The item's type, which no field holds. A person chooses one of the types the item can become.
    case type
    /// The item's Location: a point on a map and, where the type has one, a name for the place. It is made of fields, so
    /// it has none of its own, and it is set by clicking a map, not by choosing from a list.
    case location(ItemLocation)
    /// An event's start, end, All Day and zone, which the type declares as fields and the panel writes together.
    case eventTime(EventTime)

    /// How the field is edited in a panel, or nil where it is not.
    init?(field: ItemTypeInfo.Field) {
        switch field.kind {
        case .status where field.isPicked: self = .status(field)
        case .choice where field.isPicked: self = .choice(field)
        case .date: self = .date(field)
        case .list(let shape) where shape.holdsPeople: self = .people(field, shape)
        case .list(let shape): self = .entries(field, shape)
        case .boolean: self = .yesNo(field)
        case .text: self = .text(field)
        case .number: self = .number(field)
        case .words: self = .words(field)
        default: return nil
        }
    }

    var field: ItemTypeInfo.Field? {
        switch self {
        case .status(let field), .choice(let field), .date(let field), .people(let field, _), .text(let field), .number(let field),
             .words(let field), .yesNo(let field), .entries(let field, _):
            field
        case .tags, .relation, .type, .location, .eventTime: nil
        }
    }

    /// What the panel changes of the item, which `Item.obstacle(to:)` judges.
    var change: ItemChange {
        switch self {
        case .tags: .tags
        case .relation: .links
        case .type: .type
        default: .fields
        }
    }

    /// The row's identifier on the page (`PagePlacement`): the field's key, or the one the tags and the parent have.
    var rowID: String {
        switch self {
        case .tags: PagePlacement.tags
        case .relation(let field): field
        case .type: PagePlacement.type
        case .location: ItemLocation.rowID
        case .eventTime: EventTime.rowID
        default: field?.key ?? ""
        }
    }

    var isNumber: Bool {
        if case .number = self { true } else { false }
    }

    /// Whether the value is typed into a field in the panel and written when the person is done, rather than chosen
    /// from a list.
    var isTyped: Bool {
        switch self {
        case .text, .number: true
        default: false
        }
    }

    /// Whether choosing a value is the whole of the edit, so the panel closes on it. The value held then shows as one
    /// chip in the search field; a value that holds several shows one chip each, and the panel stays open. A link closes
    /// it only where its field holds one (`ValueEditModel.holdsOne`).
    var closesOnChoice: Bool {
        switch self {
        case .status, .choice, .type, .yesNo: true
        case .date, .people, .tags, .relation, .text, .number, .words, .location, .eventTime, .entries: false
        }
    }
}

/// A value the panel holds, shown as a chip in its search field with an x to take it away.
nonisolated struct ValueChip: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var mark: ValueListRow.Mark = .none
    /// Whether the panel can take it away: a type and a required field's value cannot be.
    var isRemovable = true
    /// Whether the chip is the type being given to an item, the one chip that takes a tint.
    var givesType = false
    /// Whether the chip is "N More", which shows the chips it left out and takes nothing away.
    var revealsMore = false
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
        /// A choice's option, with the dot of the color the field gives it (`OptionTone.tone(of:in:isPriority:)`).
        case dot(TypeTone)
        /// A type, with its icon.
        case type(icon: String?)
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
    /// The date panel's row that takes the date away, the one panel with no chip to remove.
    static let notSetID = "not-set"
    static let optionPrefix = "option:"

    static func optionID(_ word: String) -> String { optionPrefix + word }

    /// The word a row chooses, or nil for a row that is not an option.
    static func word(of rowID: String) -> String? {
        rowID.hasPrefix(optionPrefix) ? String(rowID.dropFirst(optionPrefix.count)) : nil
    }

    /// A status field's words, each under its group, with the groups in the order the type declares them. A word the type does not
    /// declare, which an item can still hold, is listed under Other so the value it has is always shown. The value is taken
    /// away with its chip.
    static func statusRows(field: ItemTypeInfo.Field, current: String?) -> [ValueListRow] {
        guard case .status(let words) = field.kind else { return [] }
        var rows: [ValueListRow] = []
        func option(_ word: String, group: StatusGroup?) -> ValueListRow {
            ValueListRow(id: optionID(word), role: .option, title: ItemTypeInfo.Field.label(ofOption: word), mark: .status(group), isCurrent: word == current)
        }
        var groups: [StatusGroup] = []
        for word in words where !groups.contains(word.group) { groups.append(word.group) }
        for group in groups {
            let inGroup = words.filter { $0.group == group }
            rows.append(.header(StatusBucket.group(group).title, id: "header:" + group.rawValue))
            rows += inGroup.map { option($0.value, group: group) }
        }
        if let current, !current.isEmpty, !words.contains(where: { $0.value == current }) {
            rows.append(.header(StatusBucket.other.title, id: "header:other"))
            rows.append(option(current, group: nil))
        }
        return rows
    }

    static let yesWord = "yes"
    static let noWord = "no"

    /// The two rows of a yes or no, the one it holds marked. A value that is not set reads as no.
    static func yesNoRows(current: PropertyValue?) -> [ValueListRow] {
        let isYes = InspectorFields.isYes(current)
        return [
            ValueListRow(id: optionID(yesWord), role: .option, title: String(localized: "Yes"), isCurrent: isYes),
            ValueListRow(id: optionID(noWord), role: .option, title: String(localized: "No"), isCurrent: !isYes),
        ]
    }

    /// A choice's options in the catalogue's order. The item's own
    /// word is listed last where the catalogue does not declare it.
    static func choiceRows(field: ItemTypeInfo.Field, current: String?, isPriority: Bool) -> [ValueListRow] {
        field.options(including: current).map {
            ValueListRow(
                id: optionID($0), role: .option, title: ItemTypeInfo.Field.label(ofOption: $0),
                mark: .dot(OptionTone.tone(of: $0, in: field, isPriority: isPriority)), isCurrent: $0 == current)
        }
    }
}

/// A time of day as a person types it in the date panel, or as the clock writes it back (`DateDisplay.timeOfDay`): `9`,
/// `930`, `9:30`, `21.30`, `9:30 pm` or `9:30 p.m.`.
nonisolated enum TimeOfDay {
    static func parse(_ text: String) -> (hour: Int, minute: Int)? {
        let typed = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = typed.wholeMatch(of: /(\d{1,2})(?:[:.]?(\d{2}))?\s*(?:([ap])\.?(?:m\.?)?)?/),
              var hour = Int(match.1) else { return nil }
        let minute = match.2.flatMap { Int($0) } ?? 0
        guard minute < 60 else { return nil }
        if let suffix = match.3 {
            guard (1...12).contains(hour) else { return nil }
            if suffix.hasPrefix("a") { hour = hour == 12 ? 0 : hour } else { hour = hour == 12 ? 12 : hour + 12 }
        }
        return hour < 24 ? (hour, minute) : nil
    }

    /// `day` with the whole clock time of `basis` in `calendar`, seconds and fractions included, so a time the person did
    /// not touch is never rounded. A clock time that the day does not have goes to the next one that it does, as a
    /// calendar moves an event onto such a day.
    static func keeping(clockOf basis: Date, on day: Date, calendar: Calendar) -> Date {
        let start = calendar.startOfDay(for: day)
        var parts = calendar.dateComponents([.year, .month, .day], from: start)
        let time = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: basis)
        (parts.hour, parts.minute, parts.second, parts.nanosecond) = (time.hour, time.minute, time.second, time.nanosecond)
        return calendar.date(from: parts) ?? start
    }

    /// `hour` and `minute` on the day of `day` in `calendar`, or nil where that day's clock has no such time (a clock put
    /// forward). The next time that does exist is never taken for it.
    static func moment(hour: Int, minute: Int, on day: Date, calendar: Calendar) -> Date? {
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        (parts.hour, parts.minute, parts.second) = (hour, minute, 0)
        guard let moment = calendar.date(from: parts) else { return nil }
        let kept = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment)
        return kept.year == parts.year && kept.month == parts.month && kept.day == parts.day && kept.hour == hour && kept.minute == minute ? moment : nil
    }
}

/// A day typed into a date panel's field: "25 Nov 2026", "2026-11-25", "tomorrow". The system's date reader takes it,
/// so it follows the person's language and order; only a text that is wholly one day is taken.
nonisolated enum TypedDay {
    /// The start of the day `text` names, in `calendar`, or nil where it names none or more than one.
    static func parse(_ text: String, calendar: Calendar) -> Date? {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty, let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let whole = NSRange(typed.startIndex..., in: typed)
        let matches = detector.matches(in: typed, options: [], range: whole)
        guard matches.count == 1, let match = matches.first, match.range == whole, let date = match.date else { return nil }
        // The reader places the day in the system's zone; the day is what it names, whatever zone the panel reads in.
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: parts).map { calendar.startOfDay(for: $0) }
    }

    /// A day and a time typed together, "25 Nov 2026 at 09:00": the two parts, the time nil where there is none.
    static func split(_ text: String) -> (day: String, time: String?) {
        let typed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = typed.wholeMatch(of: /(.+?)\s+(?:at|@)\s+(.+)/.ignoresCase()) else { return (typed, nil) }
        return (String(match.1), String(match.2))
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

    /// Today, tomorrow and the first day of next week, as the person's calendar counts the week; a filter's panel adds the
    /// first day of the week after.
    static func entries(now: Date, calendar: Calendar, includingTwoWeeks: Bool = false) -> [Entry] {
        let today = calendar.startOfDay(for: now)
        var entries = [Entry(id: "today", title: String(localized: "Today"), symbol: "sun.max", date: today)]
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) {
            entries.append(Entry(id: "tomorrow", title: String(localized: "Tomorrow"), symbol: "arrow.right.circle", date: tomorrow))
        }
        if let week = calendar.nextDate(after: today, matching: DateComponents(weekday: calendar.firstWeekday), matchingPolicy: .nextTime) {
            entries.append(Entry(id: "next-week", title: String(localized: "Next Week"), symbol: "calendar.badge.clock", date: week))
            if includingTwoWeeks, let later = calendar.date(byAdding: .weekOfYear, value: 1, to: week) {
                entries.append(Entry(id: "two-weeks", title: String(localized: "In Two Weeks"), symbol: "calendar.badge.plus", date: later))
            }
        }
        return entries
    }

    /// The day beside a quick date, such as "Tue 3 Nov", with the year only where it is not the one of `now`, in the
    /// order and punctuation the locale uses, unless the person chose how a date is written.
    static func detail(of entry: Entry, now: Date, calendar: Calendar, locale: Locale, format: DateFormat = .standard) -> String {
        if format.date != .system {
            return DateDisplay.text(of: entry.date, hasTime: false, place: .value, format: format, now: now, calendar: calendar, locale: locale)
        }
        let sameYear = calendar.isDate(entry.date, equalTo: now, toGranularity: .year)
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate(sameYear ? "EEEdMMM" : "EEEdMMMy")
        return formatter.string(from: entry.date)
    }

    /// The date to store for choosing `day`: with a time, the day at the whole time the item already holds, else at the
    /// start of the day.
    static func moment(on day: Date, keepingTimeOf current: Date?, calendar: Calendar) -> Date {
        guard let current else { return calendar.startOfDay(for: day) }
        return TimeOfDay.keeping(clockOf: current, on: day, calendar: calendar)
    }
}

/// The people a list of people can offer: those other items hold in the same kind of list. The library has no list of
/// people to choose from, so this is the cheapest honest source.
nonisolated enum PeopleSuggestions {
    struct Person: Hashable, Sendable {
        let name: String
        let entry: ListEntries.Entry
        let address: String?
        /// What tells one person from another: the address where the entry has one, else the name. Two people can share
        /// a name, so a name alone would merge them.
        let identity: String

        init?(entry: ListEntries.Entry, shape: ListShape) {
            guard let name = shape.personName(of: entry) else { return nil }
            self.name = name
            self.entry = entry
            address = shape.members.dropFirst().first.flatMap { shape.text(of: $0, in: entry) }
            identity = (address ?? name).lowercased()
        }

        /// Whether typed text names this person, by name or by address.
        func isNamed(_ typed: String) -> Bool {
            let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return typed == name.lowercased() || typed == identity
        }
    }

    /// A person a list holds, with the entry's place in the stored list and a row identifier that is the person's own
    /// even when the list holds the same person twice.
    struct Held: Identifiable, Hashable, Sendable {
        static let prefix = "held:"
        let person: Person
        let index: Int
        let id: String
    }

    /// The distinct people in the lists, most often named first, then by name.
    static func pool(from lists: [PropertyValue?], shape: ListShape) -> [Person] {
        var counts: [String: (person: Person, count: Int)] = [:]
        for list in lists {
            for case let entry? in ListEntries.entries(of: list).map(ListEntries.object) {
                guard let person = Person(entry: entry, shape: shape) else { continue }
                counts[person.identity, default: (person, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.person.name.localizedStandardCompare($1.person.name) == .orderedAscending }
            .map(\.person)
    }

    /// The people the library holds as items of its own, as entries of `shape`: the name in the first member and, where the
    /// second takes an address and the person's type has a list that starts with one, the first address in it. Those the
    /// lists already name (`known`) are left out, so nobody is offered twice.
    static func pool(of items: [Item], catalogue: Catalogue, shape: ListShape, excluding known: [Person]) -> [Person] {
        guard let nameMember = shape.members.first else { return [] }
        let addressMember = shape.members.dropFirst().first.flatMap { member -> ListShape.Member? in
            if case .text(.email) = member.kind { member } else { nil }
        }
        var taken = Set(known.map(\.identity))
        var people: [Person] = []
        var personTypes: [TypeID: Bool] = [:]
        for item in items {
            let isPerson = personTypes[item.type] ?? (PageHeaderKind.of(item.type, in: catalogue) == .person)
            personTypes[item.type] = isPerson
            guard isPerson, let name = item.name, !name.isEmpty else { continue }
            var entry: ListEntries.Entry = [nameMember.key: .string(name)]
            if let addressMember, let address = firstAddress(of: item, catalogue: catalogue) { entry[addressMember.key] = .string(address) }
            guard let person = Person(entry: entry, shape: shape), taken.insert(person.identity).inserted else { continue }
            people.append(person)
        }
        return people.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func firstAddress(of item: Item, catalogue: Catalogue) -> String? {
        for field in catalogue.itemTypes[item.type]?.fields ?? [] {
            guard case .list(let shape) = field.kind, let first = shape.members.first, case .text(.email) = first.kind else { continue }
            for case let entry? in ListEntries.entries(of: item.value(of: field.key)).map(ListEntries.object) {
                if let text = shape.text(of: first, in: entry) { return text }
            }
        }
        return nil
    }

    /// The people to offer for what is typed: those whose name or any member contains it, less those already held.
    static func matching(_ typed: String, in pool: [Person], excluding held: [Held]) -> [Person] {
        let typed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(held.map(\.person.identity))
        return pool.filter { person in
            !taken.contains(person.identity)
                && (typed.isEmpty || person.entry.values.contains { $0.string?.localizedStandardContains(typed) == true })
        }
    }

    /// The people a list already holds, each with its place in the stored list, which also holds entries that are no
    /// person.
    static func held(in list: PropertyValue?, shape: ListShape) -> [Held] {
        var seen: [String: Int] = [:]
        return ListEntries.entries(of: list).enumerated().compactMap { index, value in
            guard let entry = ListEntries.object(value), let person = Person(entry: entry, shape: shape) else { return nil }
            let occurrence = seen[person.identity, default: 0]
            seen[person.identity] = occurrence + 1
            return Held(person: person, index: index, id: "\(Held.prefix)\(person.identity)#\(occurrence)")
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

/// The words a list of words can offer: those other items hold in the same field, most often held first.
nonisolated enum WordSuggestions {
    /// One word, as the first item that holds it spells it, with how many items hold it.
    struct Entry: Hashable, Sendable {
        let word: String
        let count: Int
    }

    static func pool(from lists: [PropertyValue?]) -> [Entry] {
        var counts: [String: (word: String, count: Int)] = [:]
        for list in lists {
            for word in ListEntries.entries(of: list).compactMap(\.string) where !word.isEmpty {
                counts[word.lowercased(), default: (word, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word.localizedStandardCompare($1.word) == .orderedAscending }
            .map { Entry(word: $0.word, count: $0.count) }
    }
}

/// A value the panel wrote that the library's copy may not show yet. A library can take a write after it is made
/// (`MarfaLibrary` queues it), so the panel builds its next change on this, not on a copy that still shows the value
/// from before; otherwise two quick taps would each start from the same stored list and the second would undo the
/// first.
nonisolated struct PendingValue: Sendable {
    /// What the panel wrote.
    var value: PropertyValue?
    /// What the copy held before the oldest write still on its way.
    var base: PropertyValue?
    /// The writes on their way before this one.
    var earlier: [PropertyValue?] = []
    /// The library's mark for the write (`ItemLibrary.lastPropertyWrite`), nil where it keeps none.
    var mark: Int?

    enum State: Sendable {
        /// The library is still writing, and the copy does not show the last write yet.
        case waiting
        /// The copy shows it, or took it.
        case landed
        /// The copy still shows the value from before and the library is not writing: the write was refused.
        case refused
        /// The copy shows neither, so it changed elsewhere meanwhile.
        case elsewhere
    }

    func state(stored: PropertyValue?, isWriting: Bool, took: (Int) -> Bool) -> State {
        if let mark, took(mark) { return .landed }
        // A write that puts back the value from before looks landed before it is, so only its mark settles it.
        if stored == value, value != base || mark == nil { return .landed }
        // While writes are on their way the copy can show any of them, which is not a change made elsewhere.
        if isWriting, stored == base || earlier.contains(stored) { return .waiting }
        return stored == base ? .refused : .elsewhere
    }
}

/// Three-way change of a list of entries: what the panel changed against the list it started from, applied to the list
/// the copy holds now, so neither change is lost.
nonisolated enum ListRebase {
    /// `theirs` without the entries `mine` removed from `base`, then the entries `mine` added, in order, that `theirs`
    /// does not hold. `same` says whether two entries are one (an entry of a person is, by the person). Nil where
    /// none is left, so the field is unset rather than holding `[]`.
    static func merge(
        base: PropertyValue?, mine: PropertyValue?, theirs: PropertyValue?,
        same: (PropertyValue, PropertyValue) -> Bool = { $0 == $1 }
    ) -> PropertyValue? {
        let (base, mine) = (ListEntries.entries(of: base), ListEntries.entries(of: mine))
        var result = ListEntries.entries(of: theirs)
        for entry in difference(base, mine, same: same) {
            if let at = result.firstIndex(where: { same($0, entry) }) { result.remove(at: at) }
        }
        for entry in difference(mine, base, same: same) where !result.contains(where: { same($0, entry) }) {
            result.append(entry)
        }
        return result.isEmpty ? nil : .array(result)
    }

    /// The entries of `first` that `second` does not hold, counting repeats.
    private static func difference(
        _ first: [PropertyValue], _ second: [PropertyValue], same: (PropertyValue, PropertyValue) -> Bool
    ) -> [PropertyValue] {
        var rest = second
        return first.filter { entry in
            guard let at = rest.firstIndex(where: { same($0, entry) }) else { return true }
            rest.remove(at: at)
            return false
        }
    }
}
