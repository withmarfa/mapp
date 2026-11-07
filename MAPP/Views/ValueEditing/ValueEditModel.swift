import Foundation
import Marfa
import Observation
import SwiftUI

/// What is edited, and how the edit is written. The sidebar's row and the page each make one; the panel, the menu and
/// the popover read only this, so nothing differs by caller.
struct ValueEditRequest {
    let kind: ValueEditKind
    let library: any ItemLibrary
    /// The item the value belongs to. A value no item holds yet (a new item's) has none, and is kept by the request.
    var item: ItemID?
    var heldValue: PropertyValue?
    var undoManager: UndoManager?
    /// Writes the field, and says whether it was taken. The parent is no field, so it has none.
    var write: (PropertyValue?) -> Bool = { _ in false }
    var calendar = Calendar.current
    /// Opens the item the parent row names, for the parent's panel.
    var open: (ItemID) -> Void = { _ in }

    /// One editor at a time is open; this says which value it is for.
    var target: String { (item?.rawValue ?? "new") + "#" + kind.rowID }
}

/// The state of one open editor: what is typed, which row the keyboard is on, and why a write was refused. Closing is
/// the presenter's, which gives the model a way to ask for it.
@MainActor @Observable
final class ValueEditModel {
    let request: ValueEditRequest
    var query = ""
    var notice: String?
    private var highlight: String?
    /// Whether the highlighted row was reached with the keyboard, which the list then scrolls to.
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
    /// What the panel last wrote to a date or a list that the library's copy may not show yet. Read as the value is
    /// (`value`), which settles it once the copy shows it, refuses it or has changed elsewhere.
    @ObservationIgnored private var pending: PendingValue?
    /// Counts the panel's writes, so a view that shows the value redraws when one is made, before the copy shows it.
    private var writes = 0
    @ObservationIgnored private var rowsCache: (key: RowsKey, rows: [ValueListRow])?
    /// How many times the rows were built, so a test can tell a cached read from a rebuild.
    @ObservationIgnored private(set) var rowsBuilt = 0
    @ObservationIgnored private let pool: [PeopleSuggestions.Person]
    @ObservationIgnored private var typedAhead = (text: "", at: Date.distantPast)
    @ObservationIgnored private let wordPool: [String]
    /// What is typed into a text or a number, with the value it began from, so a change made elsewhere meanwhile is
    /// never written over.
    @ObservationIgnored let draft = ItemPropertyDraft()
    /// Whether the value changed under what was typed, which the person then settles.
    private(set) var hasConflict = false
    /// A change to the parent that has not been answered yet.
    private(set) var isSaving = false
    @ObservationIgnored private var isFinished = false

    init(_ request: ValueEditRequest) {
        self.request = request
        let items = request.library.items(in: .allNotes)
        switch request.kind {
        case .people(let field, let shape):
            pool = PeopleSuggestions.pool(from: items.map { $0.value(of: field.key) }, shape: shape)
            wordPool = []
        case .words(let field):
            pool = []
            wordPool = WordSuggestions.pool(from: items.map { $0.value(of: field.key) })
        default:
            pool = []
            wordPool = []
        }
        if let field = request.kind.field, request.kind.isTyped {
            draft.field = field
            draft.text = Self.text(of: request.item.flatMap(request.library.item)?.value(of: field.key) ?? request.heldValue)
            draft.base = draft.text
        }
    }

    private static func text(of value: PropertyValue?) -> String { value.map(ItemValueText.editing) ?? "" }

    var kind: ValueEditKind { request.kind }
    private var library: any ItemLibrary { request.library }

    // MARK: Item

    /// The value the field holds now, read from the library so a change made elsewhere shows. For a date or a list it
    /// is the panel's own last write while the library still has it on its way, and, where the list changed elsewhere
    /// meanwhile, the list with both changes.
    var value: PropertyValue? {
        guard let key = kind.field?.key else { return nil }
        guard let id = request.item else { return hasLocal ? local : request.heldValue }
        _ = writes
        return settle(library.item(id)?.value(of: key), of: id)
    }

    /// What the library's copy holds for the field, whatever the panel wrote.
    private var stored: PropertyValue? {
        guard let id = request.item, let key = kind.field?.key else { return nil }
        return library.item(id)?.value(of: key)
    }

    private var keepsPending: Bool {
        switch kind {
        case .date, .people, .words: true
        default: false
        }
    }

    private func pendingState(stored: PropertyValue?, of id: ItemID) -> PendingValue.State? {
        pending?.state(stored: stored, isWriting: library.isWritingProperties(of: id), took: { library.tookPropertyWrite($0) })
    }

    private func settle(_ stored: PropertyValue?, of id: ItemID) -> PropertyValue? {
        guard keepsPending, let held = pending, let state = pendingState(stored: stored, of: id) else { return stored }
        switch state {
        case .waiting:
            return held.value
        case .landed, .refused:
            pending = nil
            return stored
        case .elsewhere:
            guard isList else {
                pending = nil
                return stored
            }
            return ListRebase.merge(base: held.base, mine: held.value, theirs: stored, same: sameEntry)
        }
    }

    private var isList: Bool {
        switch kind {
        case .people, .words: true
        default: false
        }
    }

    /// Whether two entries of the list are one: a person is one by their identity, a word by its text.
    private var sameEntry: (PropertyValue, PropertyValue) -> Bool {
        guard case .people(_, let shape) = kind else { return { $0 == $1 } }
        func identity(_ entry: PropertyValue) -> String? {
            ListEntries.object(entry).flatMap { PeopleSuggestions.Person(entry: $0, shape: shape)?.identity }
        }
        return { first, second in
            if let first = identity(first), let second = identity(second) { return first == second }
            return first == second
        }
    }

    /// Whether the item can still take the edit. An editor for an item that cannot closes itself.
    var isEditable: Bool {
        guard let id = request.item else { return true }
        guard let item = library.item(id) else { return false }
        return kind == .tags ? item.canEditTags : item.isEditable
    }

    /// What the field in a text or a number panel holds, as the person types it.
    var typed: String {
        get { draft.text }
        set {
            guard newValue != draft.text else { return }
            if !draft.isDirty { draft.base = currentText }
            draft.text = newValue
            draft.isDirty = true
            draft.rejected = false
            hasConflict = false
            notice = nil
        }
    }

    private var currentText: String { Self.text(of: value) }

    /// The tags or the words the panel shows as removable tokens above its search field.
    var heldTokens: [String] {
        switch kind {
        case .tags: request.item.flatMap(library.item).map(library.tags(of:)) ?? []
        case .words: heldWords
        default: []
        }
    }

    private var heldWords: [String] { ListEntries.entries(of: value).compactMap(\.string) }

    /// The parent the item has now, if any.
    private var parentTarget: ItemRelationshipTarget? {
        request.item.flatMap { library.relationships(for: $0).first { $0.field == PagePlacement.parent }?.targets.first }
    }

    private var isDate: Bool {
        if case .date = kind { true } else { false }
    }

    var hasSearch: Bool {
        switch kind {
        case .people, .tags, .words, .parent: true
        case .status, .choice, .date, .text, .number: false
        }
    }

    /// What the search field asks for.
    var searchPrompt: LocalizedStringKey {
        switch kind {
        case .tags: "Add or Find a Tag"
        case .words: "Add or Find a Word"
        case .parent: "Find an Item"
        default: "Find or Add a Person"
        }
    }

    // MARK: Rows

    /// What decides the rows, so a read that finds them unchanged builds nothing: the rows are read once for each row
    /// drawn and for each key pressed.
    private struct RowsKey: Equatable {
        let query: String
        let value: PropertyValue?
        let revision: Int
        let day: Date?
        let parent: [String]
    }

    var rows: [ValueListRow] {
        let key = RowsKey(
            query: query, value: value, revision: library.contentRevision,
            day: isDate ? request.calendar.startOfDay(for: library.now()) : nil,
            parent: kind == .parent ? parentTarget.map { [$0.id, $0.displayTitle] } ?? [] : [])
        if let rowsCache, rowsCache.key == key { return rowsCache.rows }
        rowsBuilt += 1
        let built = buildRows()
        rowsCache = (key, built)
        return built
    }

    private func buildRows() -> [ValueListRow] {
        switch kind {
        case .status(let field): ValueEditOptions.statusRows(field: field, current: value?.string)
        case .choice(let field): ValueEditOptions.choiceRows(field: field, current: value?.string)
        case .date: quickRows
        case .people(_, let shape): peopleRows(shape)
        case .tags: tagRows
        case .words: wordRows
        case .parent: parentRows
        case .text, .number: []
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
        // Two people can share a name; their address then tells them apart.
        let names = Dictionary(grouping: held.map(\.person) + matching, by: { $0.name.lowercased() }).mapValues(\.count)
        func detail(_ person: PeopleSuggestions.Person) -> String? { names[person.name.lowercased(), default: 0] > 1 ? person.address : nil }
        var rows: [ValueListRow] = []
        if !held.isEmpty {
            rows.append(.header(String(localized: "Assigned"), id: "header:held"))
            rows += held.map {
                ValueListRow(id: $0.id, role: .option, title: $0.person.name, detail: detail($0.person), mark: mark($0.person), isCurrent: true)
            }
        }
        if !matching.isEmpty {
            rows.append(.header(String(localized: "Matching"), id: "header:matching"))
            rows += matching.prefix(30).map {
                ValueListRow(id: "person:" + $0.identity, role: .option, title: $0.name, detail: detail($0), mark: mark($0))
            }
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let known = (held.map(\.person) + pool).contains { $0.isNamed(typed) }
        if !typed.isEmpty, !known {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    private var tagRows: [ValueListRow] {
        let held = heldTokens
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

    private var wordRows: [ValueListRow] {
        let held = Set(heldWords.map { $0.lowercased() })
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = wordPool.filter { word in
            !held.contains(word.lowercased()) && (typed.isEmpty || word.localizedStandardContains(typed))
        }
        var rows: [ValueListRow] = []
        if !matching.isEmpty {
            rows.append(.header(String(localized: "Matching"), id: "header:matching"))
            rows += matching.prefix(30).map { ValueListRow(id: "word:" + $0, role: .option, title: $0, mark: .tag) }
        }
        let known = held.contains(typed.lowercased()) || wordPool.contains { $0.lowercased() == typed.lowercased() }
        if !typed.isEmpty, !known {
            rows.append(ValueListRow(id: "create", role: .create, title: String(localized: "Add “\(typed)”"), detail: "↩", mark: .symbol("plus")))
        }
        return rows
    }

    /// The most items the parent's list shows before the person narrows it by typing.
    static let parentLimit = 50
    static let openID = "open"
    static let removeID = "remove"

    private var parentRows: [ValueListRow] {
        var rows: [ValueListRow] = []
        let current = parentTarget
        if let current, let id = current.itemID, current.isOpenable {
            rows.append(ValueListRow(id: Self.openID, role: .option, title: String(localized: "Open “\(current.displayTitle)”"), mark: .symbol("arrow.up.right")))
            rows.append(.separator)
            rows.append(ValueListRow(id: "parent:" + id.rawValue, role: .option, title: current.displayTitle, isCurrent: true))
        }
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentID = current?.itemID
        let matching = parentCandidates.filter { $0.id != currentID && (typed.isEmpty || $0.title.localizedStandardContains(typed)) }
        if !matching.isEmpty {
            rows.append(.header(String(localized: "Items"), id: "header:items"))
            rows += matching.prefix(Self.parentLimit).map {
                ValueListRow(id: "parent:" + $0.id.rawValue, role: .option, title: $0.displayTitle, detail: library.catalogue.label(for: $0.type))
            }
            if matching.count > Self.parentLimit {
                rows.append(.header(String(localized: "Type to narrow the list"), id: "header:more"))
            }
        }
        if current != nil {
            rows.append(.separator)
            rows.append(ValueListRow(id: Self.removeID, role: .option, title: String(localized: "Remove Parent"), mark: .symbol("xmark")))
        }
        return rows
    }

    /// The items the parent could be, read once for the panel.
    @ObservationIgnored private lazy var parentCandidates: [Item] =
        request.item.map { library.relationshipCandidates(for: $0, field: PagePlacement.parent) } ?? []

    // MARK: Keyboard

    private var navigable: [ValueListRow] { rows.filter { $0.role == .option || $0.role == .create } }

    /// The row the keyboard is on: the one it moved to, else, once something is typed, the row Return would take.
    var activeRow: String? {
        let rows = navigable
        if let highlight, rows.contains(where: { $0.id == highlight }) { return highlight }
        guard hasSearch, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        switch kind {
        case .tags, .words: return rows.first { $0.role == .create }?.id ?? rows.first?.id
        case .people: return rows.first { $0.id.hasPrefix("person:") }?.id ?? rows.first?.id
        default: return rows.first { $0.id.hasPrefix("parent:") }?.id ?? rows.first?.id
        }
    }

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
        guard let current = activeRow.flatMap({ id in rows.firstIndex { $0.id == id } }) ?? Self.onlyCurrent(in: rows) else {
            highlight = (step > 0 ? rows.first : rows.last)?.id
            return
        }
        highlight = rows[min(max(current + step, 0), rows.count - 1)].id
    }

    /// Where the keyboard starts when nothing is highlighted yet: the row of the one value the item holds, as a menu
    /// opens on its checked item. With none, or several (tags, people), or with only Not Set marked because nothing is
    /// set, the first or last row.
    static func onlyCurrent(in rows: [ValueListRow]) -> Int? {
        let held = rows.indices.filter { rows[$0].isCurrent && rows[$0].id != ValueEditOptions.notSetID }
        return held.count == 1 ? held[0] : nil
    }

    func activateHighlighted() {
        if let id = activeRow { activate(id) }
    }

    /// Typing in a plain list jumps to the option that starts with it, as a menu does.
    func typeAhead(_ characters: String, now: Date = .now) {
        guard !hasSearch, !isDate, !kind.isTyped else { return }
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
            chooseDay(entry.date)
            if notice == nil { close() }
        case .people(_, let shape): activatePerson(id, shape)
        case .tags: activateTag(id)
        case .words: activateWord(id)
        case .parent: activateParent(id)
        case .text, .number: break
        }
    }

    private func activatePerson(_ id: String, _ shape: ListShape) {
        let held = PeopleSuggestions.held(in: value, shape: shape)
        if id.hasPrefix(PeopleSuggestions.Held.prefix) {
            // The index is the entry's place in the stored list, which holds entries `held` cannot read too.
            guard let person = held.first(where: { $0.id == id }) else { return }
            _ = commit(ListEntries.removing(at: person.index, from: value), failure: String(localized: "The list could not be saved."))
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
        // A tap on a row that was held by the last one is not a second person.
        if let person = PeopleSuggestions.Person(entry: entry, shape: shape), held.contains(where: { $0.person.identity == person.identity }) {
            query = ""
            return
        }
        if let reason = limitReason(holding: ListEntries.entries(of: value).count + 1) {
            notice = reason
            return
        }
        if commit(ListEntries.appending(entry, to: value), failure: String(localized: "The list could not be saved.")) {
            query = ""
            highlight = nil
        }
    }

    /// Why the list cannot take `count` entries, in the person's words, or nil where its field takes them. Only a
    /// limit the catalogue declares is judged here; the server judges each entry's form (a web or mail address) and
    /// the library tells its reason when it refuses the write, as it does for any queued edit.
    private func limitReason(holding count: Int) -> String? {
        guard let field = kind.field, !field.holds(count), let limit = field.maxItems else { return nil }
        return String(localized: "\(field.label) can hold \(limit) at most.")
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

    private func activateWord(_ id: String) {
        let word = id == "create" ? query.trimmingCharacters(in: .whitespacesAndNewlines) : String(id.dropFirst("word:".count))
        guard !word.isEmpty else { return }
        let held = heldWords
        guard !held.contains(where: { $0.lowercased() == word.lowercased() }) else {
            query = ""
            return
        }
        if let reason = limitReason(holding: held.count + 1) {
            notice = reason
            return
        }
        if commitWords(held + [word]) {
            query = ""
            highlight = nil
        }
    }

    private func activateParent(_ id: String) {
        guard !isSaving, let item = request.item else { return }
        let current = parentTarget
        switch id {
        case Self.openID:
            if let target = current?.itemID { request.open(target) }
            close()
        case Self.removeID:
            changeParent(of: item, adding: nil, removing: current?.itemID)
        default:
            let target = ItemID(String(id.dropFirst("parent:".count)))
            if target == current?.itemID { close() } else { changeParent(of: item, adding: target, removing: current?.itemID) }
        }
    }

    /// Replaces the parent. The library judges the link, and may have to ask the server, so the panel waits without
    /// holding anything up and says why when the change is refused. A change that is answered after the panel has
    /// closed is told as a notice instead.
    private func changeParent(of item: ItemID, adding: ItemID?, removing: ItemID?) {
        isSaving = true
        notice = nil
        let (library, undoManager) = (library, request.undoManager)
        let label = adding.flatMap(library.item)?.displayTitle ?? parentTarget?.displayTitle ?? ""
        Task { [weak self] in
            var refusal: String?
            if let adding, case .refused(let message) = await library.relationshipVerdict(for: item, field: PagePlacement.parent, to: adding) {
                refusal = message
            }
            let taken: Bool
            if refusal == nil {
                taken = await library.changeItemRelationship(
                    item, field: PagePlacement.parent, adding: adding.map { [$0] } ?? [], removing: removing.map { [$0] } ?? [], undoManager: undoManager)
            } else {
                taken = false
            }
            guard let self else {
                if !taken { library.notices.notKept(String(localized: "Parent Not Saved"), text: label, reason: refusal ?? String(localized: "The parent could not be saved.")) }
                return
            }
            isSaving = false
            if taken {
                close()
            } else if isFinished {
                library.notices.notKept(String(localized: "Parent Not Saved"), text: label, reason: refusal ?? String(localized: "The parent could not be saved."))
            } else {
                notice = refusal ?? String(localized: "The parent could not be saved.")
            }
        }
    }

    /// Removes one tag or word from the tokens above the field.
    func removeToken(_ token: String) {
        guard isEditable else { return }
        switch kind {
        case .tags:
            if let item = request.item { library.removeTag(token, from: [item], undoManager: request.undoManager) }
        case .words:
            commitWords(heldWords.filter { $0 != token })
        default:
            break
        }
    }

    /// Return in a tag or word field with nothing highlighted adds what was typed, as the tag field always has. In a
    /// text or a number it writes what was typed.
    func submitTyped() {
        if kind.isTyped {
            commitText()
        } else if activeRow != nil {
            activateHighlighted()
        } else if kind == .tags, !ItemTag.normalized(query).isEmpty {
            activate("create")
        } else if case .words = kind, !query.trimmingCharacters(in: .whitespaces).isEmpty {
            activate("create")
        }
    }

    // MARK: Typed values

    /// Writes what was typed, and closes on success. A refusal keeps the text and the panel and says why; a value that
    /// changed under the text waits for the person to say which they mean.
    func commitText(overwriting: Bool = false) {
        guard let field = kind.field else { return }
        guard isEditable else {
            close()
            return
        }
        switch draft.commit(as: field.kind, rule: field.numberRule, current: currentText, overwriting: overwriting) {
        case .unchanged:
            close()
        case .alreadyCurrent:
            draft.discard(toMatch: currentText)
            close()
        case .conflict:
            hasConflict = true
            notice = String(localized: "This value changed while you were editing. Your edit hasn’t been saved.")
        case .invalid:
            draft.rejected = true
            notice = field.numberRule.requirement ?? String(localized: "The value isn’t a number.")
        case .outOfRange:
            draft.rejected = true
            notice = field.numberRule.requirement ?? PropertyLoss.outOfRange.reason
        case .write(let new):
            if request.write(new) {
                draft.isDirty = false
                draft.base = Self.text(of: new)
                close()
            } else {
                draft.rejected = true
                notice = refusalReason(String(localized: "The value could not be saved. Your input has been kept."))
            }
        }
    }

    /// The person chose to keep their text over the value that changed.
    func keepEdit() { commitText(overwriting: true) }

    /// The person chose the value that changed over their text.
    func useCurrentValue() {
        draft.discard(toMatch: currentText)
        hasConflict = false
        notice = nil
    }

    /// Why a write was refused: the item is gone or can no longer be edited, else `fallback`.
    private func refusalReason(_ fallback: String) -> String {
        guard let id = request.item else { return fallback }
        guard let item = library.item(id) else { return String(localized: "This item is no longer available.") }
        return (kind == .tags ? item.canEditTags : item.isEditable) ? fallback : PropertyLoss.notEditable.reason
    }

    /// The editor is ending. A text or number the person typed is written or handed back unless they cancelled it
    /// themselves; ending the panel any other way (a click elsewhere, a resized window, another item) never loses it.
    func finish(cancelled: Bool) {
        isFinished = true
        guard !cancelled else { return }
        guard kind.isTyped, let field = kind.field else { return }
        draft.handOff(
            label: field.label, as: field.kind, rule: field.numberRule, current: currentText, isEditable: isEditable,
            write: request.write, to: library.notices)
    }

    // MARK: Dates

    var storedDate: ItemDate? { value?.string.flatMap { ItemDate.parse($0) } }

    /// A `datetime` field may hold a day or a moment; a `date` field never holds a time.
    var allowsTime: Bool {
        if case .date(let field) = kind, case .date(let includesTime) = field.kind { includesTime } else { false }
    }

    var hasTime: Bool { allowsTime && (storedDate?.hasTime ?? false) }

    /// The person chose a date and, where the value has a time, a time in the picker: what it shows is what is written.
    func setDate(_ selected: Date) { write(selected, withTime: hasTime) }

    /// The person chose a day from the quick dates, which keeps the time the value already has.
    func chooseDay(_ day: Date) {
        write(hasTime ? QuickDates.moment(on: day, keepingTimeOf: storedDate?.date, calendar: request.calendar) : day, withTime: hasTime)
    }

    /// The person turned the time on or off. Turning it on keeps the day, and gives a value with none today.
    func setIncludesTime(_ included: Bool) {
        guard allowsTime else { return }
        write(storedDate?.date ?? library.now(), withTime: included)
    }

    private func write(_ date: Date, withTime: Bool) {
        let text = withTime ? ItemDate.instant(date) : ItemDate.day(date, calendar: request.calendar)
        _ = commit(.string(text), failure: String(localized: "The date couldn’t be saved."))
    }

    func clearDate() {
        if commit(nil, failure: String(localized: "The date couldn’t be saved.")) { close() }
    }

    // MARK: Writing

    @discardableResult
    private func commitWords(_ words: [String]) -> Bool {
        commit(words.isEmpty ? nil : .array(words.map { .string($0) }), failure: String(localized: "The list could not be saved."))
    }

    @discardableResult
    private func commit(_ new: PropertyValue?, failure: String = String(localized: "The value could not be saved.")) -> Bool {
        guard isEditable else {
            close()
            return false
        }
        // The write goes on top of one still on its way, so the value from before the first of them stays the base.
        let before = stored
        let onTop = request.item.flatMap { keepsPending ? pendingState(stored: before, of: $0) : nil } == .waiting
        let base = onTop ? pending?.base : before
        let earlier = onTop ? (pending?.earlier ?? []) + [pending?.value] : []
        let taken = request.write(new)
        if taken {
            notice = nil
            if request.item == nil {
                local = new
                hasLocal = true
            } else if keepsPending {
                pending = PendingValue(value: new, base: base, earlier: earlier, mark: library.lastPropertyWrite)
                writes += 1
            }
        } else {
            // What was typed stays where it is, and the panel stays open.
            notice = refusalReason(failure)
        }
        return taken
    }
}
