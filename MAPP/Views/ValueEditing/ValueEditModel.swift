import Foundation
import Marfa
import Observation

/// What is edited, and how the edit is written. The sidebar's row and the page each make one; the panel, the menu and
/// the popover read only this, so nothing differs by caller.
struct ValueEditRequest {
    let kind: ValueEditKind
    let library: any ItemLibrary
    /// The item the value belongs to. A value no item holds yet (a new item's) has none, and is kept by the request.
    var item: ItemID?
    var heldValue: PropertyValue?
    var undoManager: UndoManager?
    /// Writes the field, and says whether it was taken. The caller marks the value rejected when it was not.
    let write: (PropertyValue?) -> Bool
    var calendar = Calendar.current

    /// One editor at a time is open; this says which value it is for.
    var target: String { (item?.rawValue ?? "new") + "#" + (kind.field?.key ?? "tags") }
}

/// The state of one open editor: what is typed, which row the keyboard is on, and why a write was refused. Closing is
/// the presenter's, which gives the model a way to ask for it.
@MainActor @Observable
final class ValueEditModel {
    let request: ValueEditRequest
    var query = ""
    var notice: String?
    private var highlight: String?
    /// Whether the highlighted row was reached with the keyboard, which a designed panel draws in the accent color
    /// where a hovered one is quiet.
    private(set) var viaKeyboard = false
    /// The room the panel has, which a list taller than it scrolls within.
    var maxHeight = CGFloat.infinity
    private(set) var totalHeight: CGFloat = 0
    private(set) var rowsHeight: CGFloat = 0
    private(set) var listHeight: CGFloat = 0
    @ObservationIgnored var close: () -> Void = {}
    @ObservationIgnored var layoutChanged: () -> Void = {}
    @ObservationIgnored private var local: PropertyValue?
    @ObservationIgnored private var hasLocal = false
    @ObservationIgnored private let pool: [PeopleSuggestions.Person]
    @ObservationIgnored private var typedAhead = (text: "", at: Date.distantPast)

    init(_ request: ValueEditRequest) {
        self.request = request
        if case .people(let field, let shape) = request.kind {
            pool = PeopleSuggestions.pool(from: request.library.items(in: .allNotes).map { $0.value(of: field.key) }, shape: shape)
        } else {
            pool = []
        }
    }

    var kind: ValueEditKind { request.kind }
    private var library: any ItemLibrary { request.library }

    // MARK: Item

    /// The value the field holds now, read from the library so a change made elsewhere shows.
    var value: PropertyValue? {
        guard let key = kind.field?.key else { return nil }
        if let id = request.item { return library.item(id)?.value(of: key) }
        return hasLocal ? local : request.heldValue
    }

    /// Whether the item can still take the edit. An editor for an item that cannot closes itself.
    var isEditable: Bool {
        guard let id = request.item else { return true }
        guard let item = library.item(id) else { return false }
        return kind == .tags ? item.canEditTags : item.isEditable
    }

    var heldTags: [String] { request.item.flatMap(library.item).map(library.tags(of:)) ?? [] }

    private var isDate: Bool {
        if case .date = kind { true } else { false }
    }

    var hasSearch: Bool {
        switch kind {
        case .people, .tags: true
        case .status, .choice, .date: false
        }
    }

    // MARK: Rows

    var rows: [ValueListRow] {
        switch kind {
        case .status(let field): ValueEditOptions.statusRows(field: field, current: value?.string)
        case .choice(let field): ValueEditOptions.choiceRows(field: field, current: value?.string)
        case .date: quickRows
        case .people(_, let shape): peopleRows(shape)
        case .tags: tagRows
        }
    }

    var quickDates: [QuickDates.Entry] { QuickDates.entries(now: library.now(), calendar: request.calendar) }

    private var quickRows: [ValueListRow] {
        quickDates.map {
            ValueListRow(
                id: "quick:" + $0.id, role: .option, title: $0.title,
                detail: QuickDates.detail(of: $0, calendar: request.calendar, locale: .current), mark: .symbol($0.symbol))
        }
    }

    private func peopleRows(_ shape: ListShape) -> [ValueListRow] {
        let held = PeopleSuggestions.held(in: value, shape: shape)
        let matching = PeopleSuggestions.matching(query, in: pool, excluding: held)
        func mark(_ person: PeopleSuggestions.Person) -> ValueListRow.Mark { .person(initials: PersonInitials.of(person.name) ?? "") }
        var rows: [ValueListRow] = []
        if !held.isEmpty {
            rows.append(.header(String(localized: "Assigned"), id: "header:held"))
            rows += held.map { ValueListRow(id: "held:" + $0.identity, role: .option, title: $0.name, mark: mark($0), isCurrent: true) }
        }
        if !matching.isEmpty {
            rows.append(.header(String(localized: "Matching"), id: "header:matching"))
            rows += matching.prefix(30).map { ValueListRow(id: "person:" + $0.identity, role: .option, title: $0.name, mark: mark($0)) }
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = (held + pool).contains { $0.identity == typed.lowercased() }
        if !typed.isEmpty, !known {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    private var tagRows: [ValueListRow] {
        let held = heldTags
        let matching = library.tagSuggestions(matching: query, excluding: held)
        var rows: [ValueListRow] = []
        if !matching.isEmpty {
            rows.append(.header(String(localized: "Matching"), id: "header:matching"))
            rows += matching.prefix(30).map { ValueListRow(id: "tag:" + $0, role: .option, title: $0, mark: .tag) }
        }
        let typed = ItemTag.normalized(query)
        if !typed.isEmpty, !held.contains(typed), !library.knownTags.contains(typed) {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Create “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    // MARK: Keyboard

    private var navigable: [ValueListRow] { rows.filter { $0.role == .option || $0.role == .create } }

    /// The row the keyboard is on: the one it moved to, else, once something is typed, the row Return would take.
    var activeRow: String? {
        let rows = navigable
        if let highlight, rows.contains(where: { $0.id == highlight }) { return highlight }
        guard hasSearch, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        if kind == .tags { return rows.first { $0.role == .create }?.id ?? rows.first?.id }
        return rows.first { $0.id.hasPrefix("person:") }?.id ?? rows.first?.id
    }

    /// Whether the active row is the keyboard's: the one Return takes when nothing has been hovered.
    var activeIsKeyboard: Bool { viaKeyboard || highlight == nil }

    func hover(_ id: String?) {
        highlight = id
        viaKeyboard = false
    }

    enum Measure { case total, rows, list }

    /// What the content measured: all of it, the rows before any scrolling, and the part of them shown.
    func measure(_ part: Measure, _ height: CGFloat) {
        let before = (totalHeight, rowsHeight, listHeight)
        switch part {
        case .total: totalHeight = height
        case .rows: rowsHeight = height
        case .list: listHeight = height
        }
        if abs(before.0 - totalHeight) > 0.5 || abs(before.1 - rowsHeight) > 0.5 || abs(before.2 - listHeight) > 0.5 { layoutChanged() }
    }

    /// The height the content wants with nothing scrolled.
    var naturalHeight: CGFloat { totalHeight + max(0, rowsHeight - listHeight) }

    func move(by step: Int) {
        let rows = navigable
        guard !rows.isEmpty else { return }
        viaKeyboard = true
        guard let current = activeRow.flatMap({ id in rows.firstIndex { $0.id == id } }) else {
            highlight = (step > 0 ? rows.first : rows.last)?.id
            return
        }
        highlight = rows[min(max(current + step, 0), rows.count - 1)].id
    }

    func activateHighlighted() {
        if let id = activeRow { activate(id) }
    }

    /// Typing in a plain list jumps to the option that starts with it, as a menu does.
    func typeAhead(_ characters: String, now: Date = .now) {
        guard !hasSearch, !isDate else { return }
        let text = (now.timeIntervalSince(typedAhead.at) < 1 ? typedAhead.text : "") + characters.lowercased()
        typedAhead = (text, now)
        if let match = navigable.first(where: { $0.role == .option && $0.title.lowercased().hasPrefix(text) }) {
            highlight = match.id
            viaKeyboard = true
        }
    }

    // MARK: Choosing

    func activate(_ id: String) {
        guard isEditable else { close(); return }
        switch kind {
        case .status, .choice:
            let new: PropertyValue? = ValueEditOptions.word(of: id).map { .string($0) }
            if id == ValueEditOptions.notSetID || new != nil, commit(new), kind.closesOnChoice { close() }
        case .date:
            guard let entry = quickDates.first(where: { "quick:" + $0.id == id }) else { return }
            setDate(entry.date)
            if notice == nil { close() }
        case .people(_, let shape): activatePerson(id, shape)
        case .tags: activateTag(id)
        }
    }

    private func activatePerson(_ id: String, _ shape: ListShape) {
        let held = PeopleSuggestions.held(in: value, shape: shape)
        if id.hasPrefix("held:") {
            // The index is the entry's place in the stored list, which holds entries `held` cannot read too.
            guard let person = held.first(where: { "held:" + $0.identity == id }),
                  let index = ListEntries.entries(of: value).firstIndex(where: {
                      ListEntries.object($0).flatMap(shape.personName(of:))?.lowercased() == person.identity
                  }) else { return }
            _ = commit(ListEntries.removing(at: index, from: value), failure: String(localized: "The list could not be saved."))
            return
        }
        let entry: ListEntries.Entry?
        if id == "create" {
            entry = PeopleSuggestions.entry(from: query, shape: shape)
        } else {
            entry = pool.first { "person:" + $0.identity == id }?.entry
        }
        guard let entry else { return }
        if let refusal = shape.refusal(of: entry) {
            notice = refusal
            return
        }
        if commit(ListEntries.appending(entry, to: value), failure: String(localized: "The list could not be saved.")) {
            query = ""
            highlight = nil
        }
    }

    private func activateTag(_ id: String) {
        guard let item = request.item else { return }
        let tag = id == "create" ? ItemTag.normalized(query) : String(id.dropFirst("tag:".count))
        if let refusal = library.addTag(tag, to: [item], undoManager: request.undoManager) {
            notice = refusal.message
        } else {
            notice = nil
            query = ""
            highlight = nil
        }
    }

    func removeTag(_ tag: String) {
        guard let item = request.item, isEditable else { return }
        library.removeTag(tag, from: [item], undoManager: request.undoManager)
    }

    /// Return in the tag field with nothing highlighted adds what was typed, as the tag field always has.
    func submitTyped() {
        if activeRow != nil { activateHighlighted() } else if kind == .tags, !ItemTag.normalized(query).isEmpty { activate("create") }
    }

    // MARK: Dates

    var storedDate: ItemDate? { value?.string.flatMap { ItemDate.parse($0) } }

    /// A `datetime` field may hold a day or a moment; a `date` field never holds a time.
    var allowsTime: Bool {
        if case .date(let field) = kind, case .date(let includesTime) = field.kind { includesTime } else { false }
    }

    var hasTime: Bool { allowsTime && (storedDate?.hasTime ?? false) }

    func setDate(_ selected: Date, includingTime: Bool? = nil) {
        let withTime = includingTime ?? hasTime
        let day = withTime ? QuickDates.moment(on: selected, keepingTimeOf: storedDate?.date, calendar: request.calendar) : selected
        _ = commit(.string(withTime ? ItemDate.instant(day) : ItemDate.day(day)), failure: String(localized: "The date couldn’t be saved."))
    }

    func clearDate() {
        if commit(nil, failure: String(localized: "The date couldn’t be saved.")) { close() }
    }

    // MARK: Writing

    @discardableResult
    private func commit(_ new: PropertyValue?, failure: String = String(localized: "The value could not be saved.")) -> Bool {
        guard isEditable else {
            close()
            return false
        }
        let taken = request.write(new)
        if taken {
            notice = nil
            if request.item == nil {
                local = new
                hasLocal = true
            }
        } else {
            // What was typed stays where it is, and the panel stays open.
            notice = failure
        }
        return taken
    }
}
