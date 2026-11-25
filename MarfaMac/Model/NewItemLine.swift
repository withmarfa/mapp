import Foundation
import Marfa

/// The rules of the new-item line, which works on the same draft as the text form (`QuickAdd.Draft`): what it reads
/// in the words typed (`NewItemText`), which kinds it can make whole, and what it offers before and while typing.
extension QuickAdd {
    /// Whether the line can make an item of the kind: one with no required field that only the item's own value panel
    /// fills (`unsettableRequired`), such as a table's columns. Such a kind opens the text form, which says why the
    /// library will refuse it, so the line never offers an Add that cannot work.
    static func lineOffers(_ typeID: String, in catalogue: Catalogue) -> Bool {
        unsettableRequired(of: typeID, in: catalogue).isEmpty
    }

    /// The kinds the line offers, as the kind menu orders them (`kindMenu`): those it can make whole.
    static func lineKindMenu(
        _ types: [ItemTypeOption], shown: [TypeID], chosen: String?, in catalogue: Catalogue
    ) -> (first: [ItemTypeOption], rest: [ItemTypeOption]) {
        let menu = kindMenu(types, shown: shown, chosen: chosen)
        return (menu.first.filter { lineOffers($0.id.rawValue, in: catalogue) }, menu.rest.filter { lineOffers($0.id.rawValue, in: catalogue) })
    }

    /// What the Kind row offers before anything is typed: the kinds last used, then the rest in the menu's order
    /// (`kinds`), `shown` of them, and the others for its More menu. The chosen kind is always among those shown.
    static func kindOffers(
        _ kinds: [ItemTypeOption], recents: [String], chosen: String, shown: Int
    ) -> (offered: [ItemTypeOption], more: [ItemTypeOption]) {
        let recent = recents.compactMap { id in kinds.first { $0.id.rawValue == id } }
        var ordered = recent + kinds.filter { !recent.contains($0) }
        if let index = ordered.firstIndex(where: { $0.id.rawValue == chosen }), index >= shown {
            ordered.insert(ordered.remove(at: index), at: 0)
        }
        return (Array(ordered.prefix(shown)), Array(ordered.dropFirst(shown)))
    }

    /// What a chip of the line says: what it sets, then its value as a person reads it, a day in its short form
    /// ("Due", "Fri 27 Nov") and a web address without its scheme. Nil value for a chip that holds none yet.
    static func lineChipWords(
        _ chip: Chip, in draft: Draft, library: any ItemLibrary, calendar: Calendar, locale: Locale
    ) -> (name: String, value: String?) {
        let catalogue = library.catalogue
        switch chip {
        case .tag(let tag):
            return (String(localized: "Tag"), tag)
        case .parent:
            let title = draft.parentID.map { library.item($0)?.displayTitle ?? String(localized: "Item not found") }
            return (String(localized: "Parent"), title)
        case .field(let key):
            guard let field = fields(of: draft.typeID, in: catalogue).first(where: { $0.key == key }) else { return (key, nil) }
            guard let value = draft.properties[key], value != .null else { return (field.label, nil) }
            if case .date = field.kind, let text = value.string, let date = ItemDate.parse(text, calendar: calendar) {
                var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
                    .weekday(.abbreviated).day().month(.abbreviated)
                if date.hasTime { style = style.hour().minute() }
                return (field.label, date.date.formatted(style))
            }
            if catalogue.bookmarkAddress(of: TypeID(draft.typeID))?.key == key, let text = value.string,
               let url = URL(string: text), let host = url.host() {
                let path = url.path(percentEncoded: false)
                return (field.label, host + (path == "/" ? "" : path))
            }
            return (field.label, valueText(value, in: field))
        }
    }

    /// The required fields the draft holds no value for, such as a message's sender. The line's Add hands the draft
    /// to the text form, which shows each as a token to fill, rather than send what the library would refuse.
    static func missingRequired(_ draft: Draft, in catalogue: Catalogue) -> [ItemTypeInfo.Field] {
        fields(of: draft.typeID, in: catalogue).filter { field in
            field.required && draft.properties[field.key].map { $0 == .null } != false
        }
    }

    /// The field a day typed on the line goes in: a task's due date, else a start date, as an event's. Nil for a kind
    /// with neither, whose day stays text.
    static func dayField(of typeID: String, in catalogue: Catalogue) -> ItemTypeInfo.Field? {
        let type = TypeID(typeID)
        let fields = fields(of: typeID, in: catalogue)
        return fields.first { catalogue.isDueDate($0, of: type) } ?? fields.first { catalogue.isStartDate($0, of: type) }
    }

    /// Something the line reads in its words as a chip: a tag, a day or a web address, where it stands in the title.
    struct ReadWord: Equatable {
        let chip: Chip
        /// Where the words stand in the title, in characters.
        let range: Range<Int>
        let words: String
        /// The value it gives its field; nil for a tag.
        let value: PropertyValue?
    }

    /// What the line reads in the draft's title, which stays as typed: each tag finished (or, with `finishing`, at
    /// the very end too), a bookmark's web address, and the day for the kind's day field (`dayField`). Words the
    /// person declined, words a chosen chip stands for (`Draft.marks`), a tag the library would refuse, and a field
    /// holding a value of the person's are not read.
    static func lineReads(
        _ draft: Draft, finishing: Bool, in library: any ItemLibrary, now: Date, calendar: Calendar, locale: Locale
    ) -> [ReadWord] {
        let catalogue = library.catalogue
        let title = draft.title
        let characters = Array(title)
        var taken = draft.marks.map(\.range)
        func isFree(_ range: Range<Int>, _ words: String) -> Bool {
            !draft.declined.contains(words) && !taken.contains { $0.overlaps(range) }
        }
        var reads: [ReadWord] = []
        for found in NewItemText.tags(in: title, finishing: finishing, refuses: { !takesTag($0, in: library) }) {
            let words = String(characters[found.range])
            guard isFree(found.range, words) else { continue }
            reads.append(ReadWord(chip: .tag(found.tag), range: found.range, words: words, value: nil))
            taken.append(found.range)
        }
        if let field = catalogue.bookmarkAddress(of: TypeID(draft.typeID)), draft.typedProperties[field.key] == nil,
           let address = NewItemText.firstWebAddress(in: title) {
            let words = String(characters[address.range])
            if isFree(address.range, words) {
                reads.append(ReadWord(chip: .field(field.key), range: address.range, words: words, value: .string(address.url.absoluteString)))
                taken.append(address.range)
            }
        }
        if let field = dayField(of: draft.typeID, in: catalogue), draft.typedProperties[field.key] == nil,
           let day = NewItemText.day(in: title, now: now, calendar: calendar, locale: locale), isFree(day.range, day.phrase) {
            reads.append(ReadWord(
                chip: .field(field.key), range: day.range, words: day.phrase,
                value: NewItemText.value(of: day, in: field, calendar: calendar)))
        }
        return reads
    }

    /// The draft with what the line reads set as its values and tags, and its title as typed, as its chips show it.
    static func withReads(_ draft: Draft, _ reads: [ReadWord]) -> Draft {
        var read = draft
        for word in reads { apply(word, to: &read) }
        return read
    }

    private static func apply(_ word: ReadWord, to draft: inout Draft) {
        switch word.chip {
        case .tag(let tag): draft.addTag(tag)
        case .field(let key):
            draft.properties[key] = word.value
            draft.add(.field(key))
        case .parent: break
        }
    }

    /// The chips the line shows after its title: those read from its words and those chosen for a word, in the
    /// order their words stand; then the chips chosen from a row, in the order chosen. A field the kind does not have
    /// is never shown.
    static func lineChips(_ draft: Draft, reads: [ReadWord], in catalogue: Catalogue) -> [Chip] {
        var placed = reads.map { (chip: $0.chip, at: $0.range.lowerBound) }
        for mark in draft.marks where draft.holds(mark.chip, in: catalogue) { placed.append((mark.chip, mark.range.lowerBound)) }
        var shown: [Chip] = []
        for entry in placed.sorted(by: { $0.at < $1.at }) where !shown.contains(entry.chip) { shown.append(entry.chip) }
        let keys = Set(fields(of: draft.typeID, in: catalogue).map(\.key))
        for chip in draft.chips where !shown.contains(chip) {
            switch chip {
            case .parent: if draft.parentID != nil { shown.append(chip) }
            case .field(let key): if keys.contains(key) { shown.append(chip) }
            case .tag(let tag): if draft.tags.contains(tag) { shown.append(chip) }
            }
        }
        for tag in draft.tags where !shown.contains(.tag(tag)) { shown.append(.tag(tag)) }
        if draft.parentID != nil, !shown.contains(.parent) { shown.append(.parent) }
        return shown
    }

    /// The marked word being typed at the end of the title, unless a chip was chosen for it or the person declined it.
    static func lineTyping(_ draft: Draft) -> NewItemText.Typing? {
        guard let typing = NewItemText.typing(in: draft.title) else { return nil }
        let range = typing.before.count..<draft.title.count
        let words = String(draft.title.dropFirst(typing.before.count))
        guard !draft.declined.contains(words), !draft.marks.contains(where: { $0.range.overlaps(range) }) else { return nil }
        return typing
    }

    /// Keeps Favorite and tags set by the library out of parsing and suggestions.
    static func takesTag(_ word: String, in library: any ItemLibrary) -> Bool {
        NewItemText.isTag(word) && word != ItemTag.favorite && !library.reservedTags.contains(word)
    }

    /// What the tag row offers for the word after `#`: up to six tags the library knows, the one typed exactly first,
    /// then the recent, and the word itself as a new tag, only where the line would take it.
    static func tagOffers(
        _ query: String, draft: Draft, recents: [String], in library: any ItemLibrary
    ) -> (known: [String], new: String?) {
        let all = recents + library.knownTags.filter { !recents.contains($0) }
        var known = all.filter { tag in
            (query.isEmpty || tag.localizedStandardContains(query)) && !draft.tags.contains(tag) && takesTag(tag, in: library)
        }
        if let exact = known.firstIndex(of: query), exact > 0 { known.insert(known.remove(at: exact), at: 0) }
        let new = !query.isEmpty && !known.contains(query) && !draft.tags.contains(query) && takesTag(query, in: library) ? query : nil
        return (Array(known.prefix(6)), new)
    }

    /// The best `limit` of `candidates` whose name holds `query`: those in `first` in its order, then the rest by name,
    /// or with `newest`, the most recently changed first. One pass that keeps only the best so far, so a library of any
    /// size is never sorted whole.
    static func bestParents(
        _ candidates: some Sequence<Item>, matching query: String, first: [ItemID], limit: Int, newest: Bool = false
    ) -> [Item] {
        guard limit > 0 else { return [] }
        func before(_ item: Item, _ other: Item) -> Bool {
            newest ? item.modified > other.modified : item.displayTitle.localizedStandardCompare(other.displayTitle) == .orderedAscending
        }
        let rank = Dictionary(first.enumerated().map { ($1, $0) }) { earlier, _ in earlier }
        var leading: [(rank: Int, item: Item)] = []
        var rest: [Item] = []
        for item in candidates {
            let name = item.displayTitle
            guard query.isEmpty || name.localizedStandardContains(query) else { continue }
            if let place = rank[item.id] {
                leading.append((place, item))
                continue
            }
            if rest.count == limit, let last = rest.last, !before(item, last) { continue }
            let at = rest.firstIndex { before(item, $0) } ?? rest.endIndex
            rest.insert(item, at: at)
            if rest.count > limit { rest.removeLast() }
        }
        return Array((leading.sorted { $0.rank < $1.rank }.map(\.item) + rest).prefix(limit))
    }

    /// The draft as it leaves the line, at Add or for the text form: what the line reads set as values and tags,
    /// and those words, and the words of each chip chosen for a word that the draft still holds, taken out of the
    /// title where they stand now. A word whose chip the kind cannot hold stays.
    static func finishLine(_ draft: inout Draft, in library: any ItemLibrary, now: Date, calendar: Calendar, locale: Locale) {
        let reads = lineReads(draft, finishing: true, in: library, now: now, calendar: calendar, locale: locale)
        let characters = Array(draft.title)
        var ranges = reads.map(\.range)
        for mark in draft.marks where draft.holds(mark.chip, in: library.catalogue) && mark.range.upperBound <= characters.count
            && String(characters[mark.range]) == mark.words {
            ranges.append(mark.range)
        }
        for word in reads { apply(word, to: &draft) }
        draft.title = NameText.trimmed(NewItemText.removing(ranges, from: draft.title))
        draft.marks = []
    }

    /// The bookmark kind a pasted web address makes, among the kinds the line offers, and its address field.
    static func bookmarkKind(in library: any ItemLibrary) -> (typeID: String, field: ItemTypeInfo.Field)? {
        let catalogue = library.catalogue
        for type in types(in: library) {
            if let field = catalogue.bookmarkAddress(of: type.id), lineOffers(type.id.rawValue, in: catalogue) {
                return (type.id.rawValue, field)
            }
        }
        return nil
    }

    /// What a title placeholder says for the kind: "New Task", or "Title (optional)" where Marfa lets the kind leave
    /// its title out and the draft holds something else.
    static func linePlaceholder(_ draft: Draft, in catalogue: Catalogue) -> String {
        if !titleRequired(draft.typeID, in: catalogue), !draft.typedProperties.isEmpty { return String(localized: "Title (optional)") }
        return String(localized: "New \(catalogue.label(for: TypeID(draft.typeID)))")
    }

    /// Whether the kind's title must be given: a title field the type requires, or any kind with no other value set.
    static func titleRequired(_ typeID: String, in catalogue: Catalogue) -> Bool {
        guard let info = catalogue.itemTypes[TypeID(typeID)] else { return true }
        return info.fields.contains { $0.key == info.titleKey && $0.required }
    }
}

extension Browser {
    /// What the line does with the words as they change: they stay as typed, and the chips follow what they read.
    /// Each chosen chip's word moves with the edit, or is text again where the edit reached it. A web address pasted
    /// into an empty line makes the item a bookmark of it.
    func lineTextChanged(from old: String, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        draft.followMarks(from: old)
        if NameText.trimmed(old).isEmpty, NewItemText.webAddress(draft.title) != nil, let bookmark = QuickAdd.bookmarkKind(in: library),
           draft.typeID != bookmark.typeID, draft.typedProperties[bookmark.field.key] == nil,
           !draft.declined.contains(NameText.trimmed(draft.title)) {
            quickAdd.draft = draft
            chooseQuickAddType(bookmark.typeID, in: library)
            return
        }
        if draft != quickAdd.draft { quickAdd.draft = draft }
    }

    /// Delete on a chip of the line: the line stops reading its words, which stay in the title, and a chosen chip
    /// goes (`QuickAdd.Draft.decline`). Returns whether anything changed.
    @discardableResult
    func declineLineChip(
        _ chip: QuickAdd.Chip, in library: any ItemLibrary, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) -> Bool {
        guard var draft = quickAdd.draft else { return false }
        let reads = QuickAdd.lineReads(draft, finishing: false, in: library, now: now, calendar: calendar, locale: locale)
        guard draft.decline(chip, readFrom: reads.filter { $0.chip == chip }.map(\.words)) else { return false }
        quickAdd.draft = draft
        return true
    }

    /// Adds a tag, a parent or a property chosen from the line's rows. Chosen for the marked word being typed, the
    /// chip stands for that word, which stays in the title until Add.
    func chooseLineMatch(_ choice: LineChoice, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        let typing = QuickAdd.lineTyping(draft)
        let chip: QuickAdd.Chip
        let mark: NewItemText.Mark
        switch choice {
        case .tag(let tag):
            guard QuickAdd.takesTag(tag, in: library) else { return }
            draft.addTag(tag)
            (chip, mark) = (.tag(tag), .tag)
        case .parent(let id):
            draft.setParent(id)
            (chip, mark) = (.parent, .parent)
        case .field(let key):
            draft.add(.field(key))
            (chip, mark) = (.field(key), .property)
        case .kind(let typeID):
            chooseQuickAddType(typeID, in: library)
            return
        }
        if let typing, typing.mark == mark {
            let range = typing.before.count..<draft.title.count
            draft.marks.append(QuickAdd.Mark(range: range, words: String(draft.title.dropFirst(typing.before.count)), chip: chip))
        }
        quickAdd.draft = draft
    }

    /// What can be chosen in the line's rows.
    enum LineChoice: Hashable {
        case kind(String)
        case tag(String)
        case parent(ItemID)
        case field(String)
    }
}
