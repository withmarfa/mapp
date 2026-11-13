import Foundation
import Marfa

/// Which date a list's rows show at their trailing edge. A list sorted by a date shows that date, so the order reads from
/// the rows; any other list shows the date its type's look names (`TypeLook.date`).
nonisolated enum RowDateSource: Hashable, Sendable {
    /// The look's own date for each item's type.
    case look
    case created
    case edited
    /// A date field of the items, by key. An item with no value in it shows no date.
    case field(String)

    /// The date the list is sorted by: the first key of a column sort that is a date field, Created or Edited, else the
    /// date of the list's own order, else (a list ordered by title, by relevance or by its place) the look's.
    static func of(sort: ItemTableComparator?, order: NoteOrder, ordersItself: Bool) -> RowDateSource {
        if let sort {
            switch sort.column.content {
            case .created: return .created
            case .edited: return .edited
            case .field(let field) where sort.column.style == .date: return .field(field.key)
            default: return .look
            }
        }
        guard !ordersItself else { return .look }
        switch order.sort {
        case .dateEdited: return .edited
        case .dateCreated: return .created
        case .title: return .look
        }
    }
}

/// What a list tells each of its rows about itself, which every row of the list shares.
nonisolated struct RowList: Hashable, Sendable {
    /// Whether the list holds several types, so a row names its own.
    var mixesTypes = false
    var date = RowDateSource.look
    var format = DateFormat.standard
    /// The start of today, which is all a row's dates need of the moment.
    var day: Date
}

/// What one row of a list says, worked out from an item and the look of its type. It is plain values, so a row whose
/// content is the same is not drawn again, and a list works it out once for each item value rather than each time a row
/// is drawn (`RowContents`).
nonisolated struct RowContent: Hashable, Sendable {
    /// One thing on the row's bottom line.
    enum Chip: Hashable, Sendable {
        case type(icon: String?, label: String)
        case status(StatusSymbol, label: String)
        /// A choice or a word of a list, with a dot in its color.
        case option(label: String, tone: TypeTone)
        case person(initials: String?, name: String)
        case tag(String)
        /// A plain fact in secondary text, led by its field's label ("Location 1712") unless it is a flag, which is the
        /// label alone ("Archived").
        case text(String)
    }

    var title: String
    var date: String?
    /// The line under the title, in secondary color.
    var secondary: String?
    /// The type's icon and label, for the type chip of a Standard row and the mark of a Compact one.
    var typeIcon: String?
    var typeLabel: String
    var mixesTypes: Bool
    /// The bottom line: the type, where the list mixes types, the status, and up to two facts.
    var chips: [Chip] = []
    /// How many values the bottom line leaves out, as "+N".
    var more = 0

    /// The most facts a row shows after the status; the rest are counted.
    static let shownFacts = 2
    /// The most tags a row shows; the rest are counted.
    static let shownTags = 3

    /// The words a row reads aloud: its title, date and line, and the words of its chips.
    var spoken: String {
        let chipWords = chips.map { chip -> String in
            switch chip {
            case .type(_, let label), .status(_, let label), .option(let label, _), .tag(let label), .text(let label): label
            case .person(_, let name): name
            }
        }
        return ([title, date, secondary].compactMap { $0 } + chipWords).joined(separator: ", ")
    }

    // MARK: Making

    static func make(
        for item: Item, look: TypeLook, catalogue: Catalogue, list: RowList, showsTime: Bool = false,
        calendar: Calendar = .current, locale: Locale = .current
    ) -> RowContent {
        let maker = Maker(item: item, info: catalogue.itemTypes[item.type], catalogue: catalogue, list: list, calendar: calendar, locale: locale)
        var content = RowContent(
            title: item.displayTitle, date: maker.date(of: look, showsTime: showsTime), secondary: maker.secondary(of: look),
            typeIcon: catalogue.icon(for: item.type), typeLabel: catalogue.label(for: item.type), mixesTypes: list.mixesTypes)
        maker.addBottomLine(of: look, to: &content)
        return content
    }

    /// The pieces of one item's row, which share what the item, its type and the list say.
    private struct Maker {
        let item: Item
        let info: ItemTypeInfo?
        let catalogue: Catalogue
        let list: RowList
        let calendar: Calendar
        let locale: Locale

        // MARK: Date

        /// A moment and whether it names a time, rather than a whole day.
        private typealias Moment = (date: Date, hasTime: Bool)

        func date(of look: TypeLook, showsTime: Bool) -> String? {
            guard let moment = moment(of: look) else { return nil }
            if showsTime, moment.hasTime { return DateDisplay.timeOfDay(of: moment.date, calendar: calendar, locale: locale) }
            return text(of: moment)
        }

        private func moment(of look: TypeLook) -> Moment? {
            switch list.date {
            case .created: return (item.created, true)
            case .edited: return (item.trashed ?? item.modified, true)
            case .field(let key): return fieldMoment(key)
            case .look:
                switch look.date {
                case .off: return nil
                case .created: return (item.created, true)
                case .edited: return (item.trashed ?? item.modified, true)
                case .occurred: return (item.occurred ?? item.created, true)
                // An item with no value in the field shows when it was last changed.
                case .field(let key): return fieldMoment(key) ?? (item.trashed ?? item.modified, true)
                }
            }
        }

        private func fieldMoment(_ key: String) -> Moment? {
            guard let stored = item.value(of: key)?.string, let parsed = ItemDate.parse(stored, calendar: calendar) else { return nil }
            return (parsed.date, parsed.hasTime)
        }

        /// A day alone is a day as people say it, since the list's own label gives the time of a moment today.
        private func text(of moment: Moment) -> String {
            DateDisplay.text(
                of: moment.date, hasTime: moment.hasTime, place: moment.hasTime ? .list : .table, format: list.format,
                now: list.day, calendar: calendar, locale: locale)
        }

        // MARK: Secondary

        func secondary(of look: TypeLook) -> String? {
            let parts = look.secondary.compactMap(part)
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }

        private func part(_ part: LookPart) -> String? {
            switch part {
            case .field(let key):
                guard let field = field(key) else { return nil }
                return isBody(field) ? Self.line(item.preview) : fieldText(field)
            case .time(let key):
                guard case .date(includesTime: true)? = field(key)?.kind, let moment = fieldMoment(key), moment.hasTime else { return nil }
                return DateDisplay.timeOfDay(of: moment.date, calendar: calendar, locale: locale)
            case .opening:
                return Self.line(item.preview)
            case .site:
                return item.value(of: MarfaMapping.urlField)?.string
                    .flatMap { ReadingHeader.webAddress($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    .flatMap { $0.host() }.map(Self.withoutWWW)
            case .file:
                return item.isFile ? Self.line(item.preview) : nil
            }
        }

        private static func withoutWWW(_ host: String) -> String {
            host.hasPrefix("www.") && host.count > 4 ? String(host.dropFirst(4)) : host
        }

        private static func line(_ text: String) -> String? {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        private func field(_ key: String) -> ItemTypeInfo.Field? {
            info?.fields.first { $0.key == key }
        }

        /// Whether the field holds the item's text. An item keeps that apart from its properties, so a look that names it
        /// reads the item's preview, its opening line.
        private func isBody(_ field: ItemTypeInfo.Field) -> Bool {
            field.key == info?.bodyKey
        }

        /// A field's value as one piece of text: a list's first entry, a date as the list writes it.
        private func fieldText(_ field: ItemTypeInfo.Field) -> String? {
            if field.isStatus { return statusWord(of: field).map { ItemTypeInfo.Field.label(ofOption: $0) } }
            if case .date = field.kind { return fieldMoment(field.key).map(text(of:)) }
            guard let value = PropertyRow.value(of: field, in: item, format: list.format) else { return nil }
            switch value {
            case .people(let words), .options(let words): return words.first
            case .text(let text), .url(let text), .email(let text), .phone(let text), .date(let text): return Self.line(text)
            case .boolean, .status, .parent, .type, .source, .items, .tags, .when, .empty: return nil
            }
        }

        private func statusWord(of field: ItemTypeInfo.Field) -> String? {
            item.value(of: field.key)?.string.flatMap { $0.isEmpty ? nil : $0 }
        }

        // MARK: Bottom line

        func addBottomLine(of look: TypeLook, to content: inout RowContent) {
            if list.mixesTypes { content.chips.append(.type(icon: content.typeIcon, label: content.typeLabel)) }
            let status = info?.statusField
            if let status, let word = statusWord(of: status) {
                content.chips.append(.status(StatusSymbol(group: status.statusGroup(of: word)), label: ItemTypeInfo.Field.label(ofOption: word)))
            }
            var facts = 0
            for fact in look.facts {
                let (chips, left) = chips(of: fact, skipping: status?.key)
                guard !chips.isEmpty else { continue }
                facts += 1
                // A fact's leftover counts whether it shows or not; one that does not show counts what it would have shown too.
                content.more += left
                if facts <= RowContent.shownFacts { content.chips += chips } else { content.more += chips.count }
            }
        }

        /// The chips of one fact and how many of its values they leave out. A fact the item has no value for has none.
        private func chips(of fact: LookFact, skipping status: String?) -> (chips: [Chip], left: Int) {
            switch fact {
            case .tags:
                let tags = item.tags.subtracting([ItemTag.favorite]).sorted()
                return (tags.prefix(RowContent.shownTags).map(Chip.tag), max(0, tags.count - RowContent.shownTags))
            case .field(let key):
                guard key != status, let field = field(key), !field.isStatus else { return ([], 0) }
                if isBody(field) { return Self.fact(field.label, Self.line(item.preview)) }
                guard let value = PropertyRow.value(of: field, in: item, format: list.format) else { return ([], 0) }
                return chips(of: value, field: field)
            }
        }

        /// A plain fact: the field's label, then its value, and nothing where there is no value.
        private static func fact(_ label: String, _ value: String?) -> (chips: [Chip], left: Int) {
            value.map { ([.text("\(label) \($0)")], 0) } ?? ([], 0)
        }

        private func chips(of value: PropertyRow.Value, field: ItemTypeInfo.Field) -> (chips: [Chip], left: Int) {
            switch value {
            case .people(let names):
                guard let first = names.first else { return ([], 0) }
                return ([.person(initials: PersonInitials.of(first), name: first)], names.count - 1)
            case .options(let words):
                guard let first = words.first else { return ([], 0) }
                let tones = PropertyRow.optionTones(of: field, in: item, isPriority: catalogue.isPriority(field, of: field.declaredBy))
                return ([.option(label: first, tone: tones.first ?? OptionTone.tone(for: first))], words.count - 1)
            case .text(let text), .url(let text), .email(let text), .phone(let text):
                return Self.fact(field.label, Self.line(text))
            case .date:
                return Self.fact(field.label, fieldMoment(field.key).map(text(of:)))
            case .boolean(let flag):
                return flag ? ([.text(field.label)], 0) : ([], 0)
            case .status, .parent, .type, .source, .items, .tags, .when, .empty:
                return ([], 0)
            }
        }
    }
}
