import Foundation
import Marfa

/// What a version holds that Version History reads and compares: its type, title, text and the other fields its type
/// declares. A tag, a link or anything else the server does not keep with a version is not here, so it is never
/// reported as changed.
nonisolated struct VersionContent: Hashable, Sendable {
    var type: TypeID
    var title: String?
    var text: String?
    /// The fields the catalogue declares for the type other than the title and the text, with a missing value and a
    /// null alike left out.
    var fields: [String: PropertyValue]
}

nonisolated extension ItemSnapshot {
    func content(in catalogue: Catalogue) -> VersionContent {
        VersionContent(type: type, title: title(in: catalogue), text: text(in: catalogue), fields: Self.comparable(properties, type: type, in: catalogue))
    }

    /// The properties the catalogue declares for `type`, except those that hold the title and the text.
    static func comparable(_ properties: [String: PropertyValue], type: TypeID, in catalogue: Catalogue) -> [String: PropertyValue] {
        guard let info = catalogue.itemTypes[type] else { return [:] }
        let hidden = Set([info.bodyKey, info.titleKey].compactMap { $0 })
        let declared = Set(info.fields.map(\.key))
        return properties.filter { declared.contains($0.key) && !hidden.contains($0.key) && $0.value != .null }
    }
}

nonisolated extension Item {
    /// The item as it stands now, in the form a version is read in. `text` is nil where the library has not read it.
    func versionContent(text: String?, in catalogue: Catalogue) -> VersionContent {
        var properties: [String: PropertyValue] = [:]
        for property in self.properties { properties[property.key] = property.value }
        return VersionContent(
            type: type, title: catalogue.itemTypes[type]?.titleKey == nil ? nil : title, text: text,
            fields: ItemSnapshot.comparable(properties, type: type, in: catalogue))
    }
}

/// One version in the thread: a version the server kept, or the one the item holds now.
nonisolated struct VersionEntry: Identifiable, Hashable, Sendable {
    /// The snapshot's identifier, or `current` for the item as it stands.
    let id: String
    let version: Int
    let content: VersionContent
    /// When this version was saved. Nil where nothing says.
    let written: Date?
    /// Whether `written` is the nearest time the history gives rather than the time of this version: the server thins
    /// old versions, and the time a version was saved is when its predecessor was replaced.
    let writtenIsApproximate: Bool
    /// Nil for the current version, which has no snapshot and so no record of who wrote it.
    let writer: ItemSnapshot.Writer?
    let snapshot: ItemSnapshot?

    static let currentID = "current"

    var isCurrent: Bool { snapshot == nil }
}

nonisolated enum VersionThread {
    /// The thread, newest first. `snapshots` are the versions read so far, in any order; the item now is the newest.
    static func entries(
        snapshots: [ItemSnapshot], current: Item, currentText: String?, in catalogue: Catalogue
    ) -> [VersionEntry] {
        let ascending = snapshots.sorted { $0.version < $1.version }
        var entries: [VersionEntry] = []
        var previous: ItemSnapshot?
        for snapshot in ascending {
            let written: (date: Date?, approximate: Bool)
            if let previous, previous.version == snapshot.version - 1 {
                written = (previous.replaced, previous.replaced == nil)
            } else if previous == nil, snapshot.version == 1 {
                written = (current.created, false)
            } else if let previous {
                written = (previous.replaced ?? snapshot.replaced, true)
            } else {
                written = (snapshot.replaced, true)
            }
            entries.append(VersionEntry(
                id: snapshot.id, version: snapshot.version, content: snapshot.content(in: catalogue), written: written.date,
                writtenIsApproximate: written.approximate && written.date != nil, writer: snapshot.writer, snapshot: snapshot))
            previous = snapshot
        }
        entries.append(VersionEntry(
            id: VersionEntry.currentID, version: Int(current.version.rawValue), content: current.versionContent(text: currentText, in: catalogue),
            written: current.modified, writtenIsApproximate: false, writer: nil, snapshot: nil))
        return entries.reversed()
    }
}

// MARK: Blocks

/// A run of the thread under one label: This Week, Last Week or a month.
nonisolated enum VersionBlockKind: Hashable, Sendable {
    case thisWeek, lastWeek
    case month(year: Int, month: Int)
}

nonisolated struct VersionBlock<Element>: Identifiable {
    let kind: VersionBlockKind
    let elements: [Element]

    var id: VersionBlockKind { kind }
}

extension VersionBlock: Sendable where Element: Sendable {}

nonisolated enum VersionBlocks {
    /// Groups `elements`, newest first, into This Week, Last Week and then a block for each month, by the weeks and
    /// months of `calendar`, so a Sunday or a Monday start and the person's time zone decide where a block ends. An
    /// element with no date goes with the element before it; one dated after this week is in This Week.
    static func group<Element>(
        _ elements: [Element], date: (Element) -> Date?, now: Date, calendar: Calendar
    ) -> [VersionBlock<Element>] {
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)
        let lastWeek = thisWeek.flatMap { interval in
            calendar.date(byAdding: .day, value: -1, to: interval.start).flatMap { calendar.dateInterval(of: .weekOfYear, for: $0) }
        }
        func kind(of date: Date) -> VersionBlockKind {
            if let thisWeek, date >= thisWeek.start { return .thisWeek }
            if let lastWeek, lastWeek.contains(date) { return .lastWeek }
            let parts = calendar.dateComponents([.year, .month], from: date)
            return .month(year: parts.year ?? 0, month: parts.month ?? 0)
        }
        var blocks: [VersionBlock<Element>] = []
        var last: VersionBlockKind?
        for element in elements {
            let kind = date(element).map(kind(of:)) ?? last ?? .thisWeek
            if kind == last, !blocks.isEmpty {
                blocks[blocks.count - 1] = VersionBlock(kind: kind, elements: blocks[blocks.count - 1].elements + [element])
            } else {
                blocks.append(VersionBlock(kind: kind, elements: [element]))
            }
            last = kind
        }
        return blocks
    }

    /// The label of a block: "This Week", "Last Week", or the month's name, with the year where it is not this one.
    static func title(
        of kind: VersionBlockKind, now: Date, calendar: Calendar, locale: Locale = .current
    ) -> String {
        switch kind {
        case .thisWeek: return String(localized: "This Week")
        case .lastWeek: return String(localized: "Last Week")
        case .month(let year, let month):
            let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? now
            var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone).month(.wide)
            if calendar.component(.year, from: now) != year { style = style.year() }
            return first.formatted(style)
        }
    }

    /// A version's time as the thread writes it: the day as the lists write it ("Today", a weekday this week, "29 Oct"),
    /// then the time. The date formats that spell a date out (short and long) are used whole.
    static func when(
        _ date: Date, format: DateFormat, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> String {
        switch format {
        case .automatic, .relative:
            let day = DateDisplay.text(of: date, hasTime: false, place: .table, format: .automatic, now: now, calendar: calendar, locale: locale)
            let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, calendar: calendar, timeZone: calendar.timeZone))
            return String(localized: "\(day), \(time)")
        case .short, .long:
            return DateDisplay.text(of: date, hasTime: true, place: .value, format: format, now: now, calendar: calendar, locale: locale)
        }
    }
}

// MARK: What changed

/// One field that differs between two versions.
nonisolated struct FieldChange: Identifiable, Hashable, Sendable {
    let key: String
    let label: String
    let field: ItemTypeInfo.Field?
    let from: PropertyValue?
    let to: PropertyValue?

    var id: String { key }
}

/// How two versions differ, from the older to the newer, in the title, the text and the other fields.
nonisolated struct VersionDelta: Hashable, Sendable {
    var typeChanged = false
    var titleChanged = false
    var textChanged = false
    var fields: [FieldChange] = []

    var isEmpty: Bool { !typeChanged && !titleChanged && !textChanged && fields.isEmpty }

    /// What `newer` changed from `older`. A title or a text that one side lacks (a type that keeps none) is not a
    /// change.
    static func between(_ older: VersionContent, _ newer: VersionContent, in catalogue: Catalogue) -> VersionDelta {
        var delta = VersionDelta()
        delta.typeChanged = older.type != newer.type
        if let a = older.title, let b = newer.title { delta.titleChanged = a != b }
        if let a = older.text, let b = newer.text { delta.textChanged = a != b }
        let info = catalogue.itemTypes[newer.type] ?? catalogue.itemTypes[older.type]
        let known = info?.fields.map(\.key) ?? []
        let keys = Set(older.fields.keys).union(newer.fields.keys)
        let ordered = known.filter(keys.contains) + keys.subtracting(known).sorted()
        delta.fields = ordered.compactMap { key in
            let a = older.fields[key], b = newer.fields[key]
            guard a != b else { return nil }
            let field = info?.fields.first { $0.key == key }
            return FieldChange(key: key, label: field?.label ?? key, field: field, from: a, to: b)
        }
        return delta
    }

    /// The change in a line, as the thread words it. `isCreation` is the first version ever, which the item was created as.
    func summary(isCreation: Bool) -> String {
        if isCreation { return String(localized: "Created") }
        var parts: [String] = []
        if titleChanged { parts.append(String(localized: "Title")) }
        if textChanged { parts.append(String(localized: "Text")) }
        if parts.isEmpty, fields.count == 1, let change = fields.first {
            if let to = change.to, let word = Self.optionWord(to, in: change.field) {
                return String(localized: "\(change.label) set to \(word)")
            }
            if change.to == nil { return String(localized: "\(change.label) cleared") }
        }
        parts += fields.map(\.label)
        if typeChanged { parts.append(String(localized: "Type")) }
        switch parts.count {
        case 0: return String(localized: "Changed")
        case 1: return String(localized: "\(parts[0]) changed")
        case 2, 3:
            let list = parts.formatted(.list(type: .and, width: .standard))
            return String(localized: "\(list) changed")
        default: return String(localized: "\(parts.count) things changed")
        }
    }

    static func optionWord(_ value: PropertyValue, in field: ItemTypeInfo.Field?) -> String? {
        guard let field, field.isPicked, let word = value.string, !word.isEmpty else { return nil }
        return ItemTypeInfo.Field.label(ofOption: word)
    }
}

nonisolated extension VersionEntry {
    /// The line the thread shows under the time. `older` is the version before this one, as far as the history gives it.
    func summary(after older: VersionEntry?, in catalogue: Catalogue) -> String {
        guard let older else {
            return version == 1 ? String(localized: "Created") : String(localized: "Changed")
        }
        return VersionDelta.between(older.content, content, in: catalogue).summary(isCreation: false)
    }
}

// MARK: The thread as a list

/// The versions listed, newest first, and whether the history was read to its end. A version is compared with the one
/// listed after it; while the history is still being read, or stopped short, the item as it stands has no version
/// listed next to it in the history, so it is compared with nothing rather than with a much older one.
nonisolated struct VersionList: Sendable {
    let entries: [VersionEntry]
    let isComplete: Bool

    init(snapshots: [ItemSnapshot], current: Item, currentText: String?, isComplete: Bool, in catalogue: Catalogue) {
        entries = VersionThread.entries(snapshots: snapshots, current: current, currentText: currentText, in: catalogue)
        self.isComplete = isComplete
    }

    var current: VersionEntry? { entries.first }

    func entry(_ id: String?) -> VersionEntry? { id.flatMap { id in entries.first { $0.id == id } } }

    func older(than entry: VersionEntry) -> VersionEntry? {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }), index + 1 < entries.count else { return nil }
        if entry.isCurrent && !isComplete { return nil }
        return entries[index + 1]
    }

    /// The entry above or below `id` in the thread, for the arrow keys.
    func neighbour(of id: String?, step: Int) -> VersionEntry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return step > 0 ? entries.first : entries.last }
        let target = index + step
        return entries.indices.contains(target) ? entries[target] : nil
    }

    func summary(of entry: VersionEntry, in catalogue: Catalogue) -> String {
        entry.summary(after: older(than: entry), in: catalogue)
    }

    /// The blocks the thread is drawn in.
    func blocks(now: Date, calendar: Calendar) -> [VersionBlock<VersionEntry>] {
        VersionBlocks.group(entries, date: \.written, now: now, calendar: calendar)
    }
}
