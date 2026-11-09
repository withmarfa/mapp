import Foundation
import Marfa

/// The values that open in a panel under them, in the inspector and on the page: what the field is, whatever it is
/// called. A yes or no is a checkbox in both places, and a list of anything but people or words stays in the inspector's
/// own list editor.
nonisolated enum ValueEditKind: Hashable, Sendable {
    case status(ItemTypeInfo.Field)
    case choice(ItemTypeInfo.Field)
    case date(ItemTypeInfo.Field)
    case people(ItemTypeInfo.Field, ListShape)
    /// A text of any format, which may run to many lines.
    case text(ItemTypeInfo.Field)
    case number(ItemTypeInfo.Field)
    /// A list of words, such as labels.
    case words(ItemTypeInfo.Field)
    /// The item's own tags, which no field holds.
    case tags
    /// The item's parent, which no field holds: a link to another item.
    case parent
    /// The item's type, which no field holds. A person chooses one of the types the item can become.
    case type

    /// How the field is edited in a panel, or nil where it is not.
    init?(field: ItemTypeInfo.Field) {
        switch field.kind {
        case .status where field.isPicked: self = .status(field)
        case .choice where field.isPicked: self = .choice(field)
        case .date: self = .date(field)
        case .list(let shape) where shape.holdsPeople: self = .people(field, shape)
        case .text: self = .text(field)
        case .number: self = .number(field)
        case .words: self = .words(field)
        default: return nil
        }
    }

    var field: ItemTypeInfo.Field? {
        switch self {
        case .status(let field), .choice(let field), .date(let field), .people(let field, _), .text(let field), .number(let field),
             .words(let field):
            field
        case .tags, .parent, .type: nil
        }
    }

    /// The row's identifier on the page (`PagePlacement`): the field's key, or the one the tags and the parent have.
    var rowID: String {
        switch self {
        case .tags: PagePlacement.tags
        case .parent: PagePlacement.parent
        case .type: PagePlacement.type
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
    /// chip in the search field; a value that holds several shows one chip each, and the panel stays open.
    var closesOnChoice: Bool {
        switch self {
        case .status, .choice, .parent, .type: true
        case .date, .people, .tags, .text, .number, .words: false
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
        /// A choice's option, with the dot of its own color.
        case dot(String)
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
    static let notSetID = "not-set"
    static let optionPrefix = "option:"

    static func optionID(_ word: String) -> String { optionPrefix + word }

    /// The word a row chooses, or nil for Not Set and for a row that is not an option.
    static func word(of rowID: String) -> String? {
        rowID.hasPrefix(optionPrefix) ? String(rowID.dropFirst(optionPrefix.count)) : nil
    }

    /// A status field's words, each under its group, with the groups in the order the type declares them. A word the type does not
    /// declare, which an item can still hold, is listed under Other so the value it has is always shown. Not Set closes
    /// the list unless the field requires a value.
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
        return rows + notSet(field: field, current: current)
    }

    /// A choice's options in the catalogue's order, then Not Set unless the field requires a value. The item's own
    /// word is listed last where the catalogue does not declare it.
    static func choiceRows(field: ItemTypeInfo.Field, current: String?) -> [ValueListRow] {
        let rows = field.options(including: current).map {
            ValueListRow(id: optionID($0), role: .option, title: ItemTypeInfo.Field.label(ofOption: $0), mark: .dot($0), isCurrent: $0 == current)
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
    static func pool(from lists: [PropertyValue?]) -> [String] {
        var counts: [String: (word: String, count: Int)] = [:]
        for list in lists {
            for word in ListEntries.entries(of: list).compactMap(\.string) where !word.isEmpty {
                counts[word.lowercased(), default: (word, 0)].count += 1
            }
        }
        return counts.values
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.word.localizedStandardCompare($1.word) == .orderedAscending }
            .map(\.word)
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
