import Foundation

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
    static func lineKinds(_ types: [ItemTypeOption], shown: [TypeID], chosen: String?, in catalogue: Catalogue) -> [ItemTypeOption] {
        let menu = kindMenu(types, shown: shown, chosen: chosen)
        return (menu.first + menu.rest).filter { lineOffers($0.id.rawValue, in: catalogue) }
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

    /// The day the line's words name for the draft's kind, while the person has not taken it back and its field holds
    /// no value of their own.
    static func foundDay(
        in draft: Draft, catalogue: Catalogue, now: Date, calendar: Calendar, locale: Locale
    ) -> (field: ItemTypeInfo.Field, day: NewItemText.FoundDay)? {
        guard let field = dayField(of: draft.typeID, in: catalogue), draft.typedProperties[field.key] == nil,
              let day = NewItemText.day(in: draft.title, now: now, calendar: calendar, locale: locale),
              day.phrase != draft.declinedDay
        else { return nil }
        return (field, day)
    }

    /// Takes the finished tags out of the line's words into the draft's tags. `finishing` (Add) takes a tag at the
    /// very end too. A word the library would refuse as a tag stays text.
    static func takeTags(_ draft: inout Draft, finishing: Bool, in library: any ItemLibrary) {
        let taken = NewItemText.takeTags(from: draft.title, finishing: finishing) { word in
            word == ItemTag.favorite || library.reservedTags.contains(word)
        }
        guard !taken.tags.isEmpty else { return }
        draft.title = taken.text
        for tag in taken.tags where !draft.tags.contains(tag) { draft.tags.append(tag) }
    }

    /// The draft as the line's Add sends it: the last tag taken, and a day found written to its field with its words
    /// taken out of the title.
    static func finishLine(_ draft: inout Draft, in library: any ItemLibrary, now: Date, calendar: Calendar, locale: Locale) {
        takeTags(&draft, finishing: true, in: library)
        if let found = foundDay(in: draft, catalogue: library.catalogue, now: now, calendar: calendar, locale: locale) {
            draft.properties[found.field.key] = NewItemText.value(of: found.day, in: found.field, calendar: calendar)
            draft.title = NewItemText.removing(found.day.phrase, from: draft.title)
        }
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
    /// What the line does with the words as they change: a web address pasted into an empty line makes the item a
    /// bookmark of it, and each finished tag becomes a token.
    func lineTextChanged(from old: String, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        if NameText.trimmed(old).isEmpty, let address = NewItemText.webAddress(draft.title), let bookmark = QuickAdd.bookmarkKind(in: library),
           draft.properties[bookmark.field.key] == nil {
            if draft.typeID != bookmark.typeID {
                chooseQuickAddType(bookmark.typeID, in: library)
                draft = quickAdd.draft ?? draft
            }
            draft.properties[bookmark.field.key] = .string(address.absoluteString)
            draft.add(.field(bookmark.field.key))
            draft.title = ""
        }
        QuickAdd.takeTags(&draft, finishing: false, in: library)
        if draft != quickAdd.draft { quickAdd.draft = draft }
    }

    /// Puts a tag, a parent or a property chosen from the line's rows in place of the marked word being typed.
    func chooseLineMatch(_ choice: LineChoice, in library: any ItemLibrary) {
        guard var draft = quickAdd.draft else { return }
        if let typing = NewItemText.typing(in: draft.title) { draft.title = typing.before }
        switch choice {
        case .tag(let tag): if !draft.tags.contains(tag) { draft.tags.append(tag) }
        case .parent(let id): draft.setParent(id)
        case .field(let key): draft.add(.field(key))
        case .kind(let typeID):
            quickAdd.draft = draft
            chooseQuickAddType(typeID, in: library)
            return
        }
        quickAdd.draft = draft
    }

    /// The person took back the day the line found, so its words stay text.
    func declineLineDay(_ phrase: String) {
        quickAdd.draft?.declinedDay = phrase
    }

    /// What can be chosen in the line's rows.
    enum LineChoice: Hashable {
        case kind(String)
        case tag(String)
        case parent(ItemID)
        case field(String)
    }
}
