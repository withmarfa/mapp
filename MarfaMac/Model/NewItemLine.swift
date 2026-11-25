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

    /// The day the line's words name for the draft's kind, while the person has not put its words back and its field
    /// holds no value of their own.
    static func foundDay(
        in draft: Draft, catalogue: Catalogue, now: Date, calendar: Calendar, locale: Locale
    ) -> (field: ItemTypeInfo.Field, day: NewItemText.FoundDay)? {
        guard let field = dayField(of: draft.typeID, in: catalogue), draft.typedProperties[field.key] == nil,
              let day = NewItemText.day(in: draft.title, now: now, calendar: calendar, locale: locale),
              !draft.declined.contains(day.phrase)
        else { return nil }
        return (field, day)
    }

    /// Takes the finished tags out of the line's words into the draft's tags, each a chip that remembers its words.
    /// `finishing` (Add) takes a tag at the very end too. A word the library would refuse as a tag stays text, as does
    /// one the person put back.
    static func takeTags(_ draft: inout Draft, finishing: Bool, in library: any ItemLibrary) {
        let declined = draft.declined
        let text = draft.title
        let taken = NewItemText.takeTags(from: text, finishing: finishing) { !takesTag($0, in: library) || declined.contains("#" + $0) }
        guard !taken.tags.isEmpty else { return }
        draft.title = taken.text
        // Where each tag stood in the text left, counting what the tags before it took out.
        var removed = 0
        var searchFrom = text.startIndex
        for tag in taken.tags {
            let words = "#" + tag
            var offset = taken.text.count
            if let range = wordRange(of: words, in: text, from: searchFrom) {
                offset = text.distance(from: text.startIndex, to: range.lowerBound) - removed
                removed += words.count + (range.upperBound < text.endIndex && text[range.upperBound].isWhitespace ? 1 : 0)
                searchFrom = range.upperBound
            }
            if !draft.tags.contains(tag) { draft.sources[.tag(tag)] = Source(words: words, offset: max(0, offset)) }
            draft.addTag(tag)
        }
    }

    /// Where `words` first stand as a word of their own in `text`, from `start`.
    private static func wordRange(of words: String, in text: String, from start: String.Index) -> Range<String.Index>? {
        var from = start
        while let range = text.range(of: words, range: from..<text.endIndex) {
            if range.lowerBound == text.startIndex || text[text.index(before: range.lowerBound)].isWhitespace { return range }
            from = range.upperBound
        }
        return nil
    }

    /// Takes a day the words name out of the title into its field, as a chip that remembers its words, once the
    /// person has typed a whole word after it, so a day still being typed (`Fri 27`) is not cut short. `finishing`
    /// (Add) takes it wherever it stands.
    static func takeDay(_ draft: inout Draft, finishing: Bool, in catalogue: Catalogue, now: Date, calendar: Calendar, locale: Locale) {
        guard let found = foundDay(in: draft, catalogue: catalogue, now: now, calendar: calendar, locale: locale) else { return }
        if !finishing {
            let after = draft.title.dropFirst(found.day.range.upperBound)
            guard after.first?.isWhitespace == true else { return }
            let next = after.drop { $0.isWhitespace }
            guard let end = next.firstIndex(where: \.isWhitespace), end > next.startIndex else { return }
        }
        let removed = NewItemText.removing(found.day, from: draft.title)
        guard removed != draft.title else { return }
        draft.title = removed
        draft.properties[found.field.key] = NewItemText.value(of: found.day, in: found.field, calendar: calendar)
        draft.sources[.field(found.field.key)] = Source(words: found.day.phrase, offset: found.day.range.lowerBound)
        draft.add(.field(found.field.key))
    }

    /// The chips the line shows after its title, in the order they were made: the tags, the parent and the fields
    /// the person added or the line read. A field the kind does not have is never shown.
    static func lineChips(_ draft: Draft, in catalogue: Catalogue) -> [Chip] {
        let keys = Set(fields(of: draft.typeID, in: catalogue).map(\.key))
        var shown = draft.chips.filter { chip in
            switch chip {
            case .parent: draft.parentID != nil
            case .field(let key): keys.contains(key)
            case .tag(let tag): draft.tags.contains(tag)
            }
        }
        for tag in draft.tags where !shown.contains(.tag(tag)) { shown.append(.tag(tag)) }
        if draft.parentID != nil, !shown.contains(.parent) { shown.append(.parent) }
        return shown
    }

    /// Whether the line makes `word` a tag, as typed and as offered in its tag row: a tag as the line reads one that
    /// is neither Favorite's nor one the library sets itself.
    static func takesTag(_ word: String, in library: any ItemLibrary) -> Bool {
        NewItemText.isTag(word) && word != ItemTag.favorite && !library.reservedTags.contains(word)
    }

    /// What the tag row offers for the word after `#`: up to six tags the library knows, the recent first, and the word
    /// itself as a new tag, only where the line would take it.
    static func tagOffers(
        _ query: String, draft: Draft, recents: [String], in library: any ItemLibrary
    ) -> (known: [String], new: String?) {
        let all = recents + library.knownTags.filter { !recents.contains($0) }
        let known = all.filter { tag in
            (query.isEmpty || tag.localizedStandardContains(query)) && !draft.tags.contains(tag) && takesTag(tag, in: library)
        }
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

    /// The draft as the line's Add sends it: the last tag taken, and a day found written to its field with its words
    /// taken out of the title.
    static func finishLine(_ draft: inout Draft, in library: any ItemLibrary, now: Date, calendar: Calendar, locale: Locale) {
        takeTags(&draft, finishing: true, in: library)
        takeDay(&draft, finishing: true, in: library.catalogue, now: now, calendar: calendar, locale: locale)
        draft.title = NameText.trimmed(draft.title)
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
    /// What the line does with the words as they change. A web address pasted into an empty line makes the item a
    /// bookmark of it; each finished tag, and a day once a word follows it, leave the words for a chip after them.
    /// Emptying the title in one edit, as Select All and Delete does, takes out the chips read from it; a single
    /// Delete that empties it does not, so the next Delete can put the last chip's words back (`putBackLineChip`).
    func lineTextChanged(
        from old: String, in library: any ItemLibrary, now: Date = .now, calendar: Calendar = .current, locale: Locale = .current
    ) {
        guard var draft = quickAdd.draft else { return }
        if NameText.trimmed(draft.title).isEmpty, old.count > 1 { draft.dropReadChips() }
        let pasted = NameText.trimmed(draft.title)
        if NameText.trimmed(old).isEmpty, let address = NewItemText.webAddress(draft.title), let bookmark = QuickAdd.bookmarkKind(in: library),
           draft.properties[bookmark.field.key] == nil, !draft.declined.contains(pasted) {
            if draft.typeID != bookmark.typeID {
                quickAdd.draft = draft
                chooseQuickAddType(bookmark.typeID, in: library)
                draft = quickAdd.draft ?? draft
            }
            draft.properties[bookmark.field.key] = .string(address.absoluteString)
            draft.sources[.field(bookmark.field.key)] = QuickAdd.Source(words: pasted, offset: 0)
            draft.add(.field(bookmark.field.key))
            draft.title = ""
        }
        QuickAdd.takeDay(&draft, finishing: false, in: library.catalogue, now: now, calendar: calendar, locale: locale)
        QuickAdd.takeTags(&draft, finishing: false, in: library)
        if draft != quickAdd.draft { quickAdd.draft = draft }
    }

    /// Delete on a chip of the line, or at the start of its title on the last chip: the chip goes, and the words it
    /// was read from go back into the title (`QuickAdd.Draft.putBack`). Returns whether a chip went.
    @discardableResult
    func putBackLineChip(_ chip: QuickAdd.Chip? = nil, in library: any ItemLibrary) -> Bool {
        guard var draft = quickAdd.draft,
              let chip = chip ?? QuickAdd.lineChips(draft, in: library.catalogue).last,
              draft.putBack(chip)
        else { return false }
        quickAdd.draft = draft
        return true
    }

    /// Puts a tag, a parent or a property chosen from the line's rows in place of the marked word being typed.
    func chooseLineMatch(_ choice: LineChoice, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        if let typing = NewItemText.typing(in: draft.title) { draft.title = typing.before }
        switch choice {
        case .tag(let tag):
            guard QuickAdd.takesTag(tag, in: library) else { return }
            draft.addTag(tag)
        case .parent(let id): draft.setParent(id)
        case .field(let key): draft.add(.field(key))
        case .kind(let typeID):
            quickAdd.draft = draft
            chooseQuickAddType(typeID, in: library)
            return
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
