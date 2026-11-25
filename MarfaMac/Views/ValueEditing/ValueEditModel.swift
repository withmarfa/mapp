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
    var calendar = Calendar.chosenWeekStart
    /// Opens the item the parent row names, for the parent's panel.
    var open: (ItemID) -> Void = { _ in }
    /// The items a panel changes where the window has several chosen, which `item` cannot name. Empty otherwise.
    var items: Set<ItemID> = []
    /// Asks for the values a type needs that the items lack, for the type panel. The panel takes none itself.
    var needsValues: (TypeID) -> Void = { _ in }
    /// Opens the panel at the middle of `rect`, where the value has no place of its own to open under.
    var isCentered = false

    /// The items the panel changes: those chosen where there are several, else the one it is for.
    var targets: Set<ItemID> { items.isEmpty ? item.map { [$0] } ?? [] : items }

    /// One editor at a time is open; this says which value it is for.
    var target: String { (item?.rawValue ?? "new") + "#" + kind.rowID }
}

/// The state of one open editor: what is typed, which row the keyboard is on, and why a write was refused. Closing is
/// the presenter's, which gives the model a way to ask for it.
/// Row selection, keyboard navigation, and writes stay together because they share the same pending edit.
@MainActor @Observable
final class ValueEditModel {
    let request: ValueEditRequest
    var query = "" {
        // A refused entry stays the person's while they go on typing it, and goes once the field is emptied.
        didSet {
            guard takesNewEntries, unsaved != nil else { return }
            if query.isEmpty { unsaved = nil } else { unsaved?.text = query }
        }
    }
    var notice: String?
    /// What the person typed that is not saved yet: a time, or a tag, word or person typed in full that the list
    /// refused. It is cleared only when that input is written, when the person cancels with Escape or empties the
    /// search field, or when it is handed back, so ending the panel any other way never loses it, and a search that
    /// only finds a held value is never kept.
    struct UnsavedInput {
        var text: String
        /// The value the time field showed when the person began typing (`shownValue`). The time is written only
        /// while the value still holds it, so a change the person did not see is never written over.
        var base: PropertyValue?
        /// Why the list refused the entry.
        var reason: String?
    }
    var unsaved: UnsavedInput? {
        didSet { if isDate, unsaved == nil { shownValue = value } }
    }
    /// The value the time field last showed as stored: when the panel opened, when the field took focus, or when
    /// what was typed in it was settled. A field being typed in may not show a change that arrives meanwhile.
    @ObservationIgnored var shownValue: PropertyValue?
    var highlight: String?
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
    @ObservationIgnored let pool: [PeopleSuggestions.Person]
    @ObservationIgnored private var typedAhead = (text: "", at: Date.distantPast)
    @ObservationIgnored let wordPool: [String]
    /// What is typed into a text or a number, with the value it began from, so a change made elsewhere meanwhile is
    /// never written over.
    @ObservationIgnored let draft = ItemPropertyDraft()
    /// Whether the value changed under what was typed, which the person then settles.
    var hasConflict = false
    /// A change to the parent that has not been answered yet.
    var isSaving = false
    @ObservationIgnored private(set) var isFinished = false
    /// The Location panel's own state, for a request of that kind.
    @ObservationIgnored private(set) var location: LocationPanelModel?

    init(_ request: ValueEditRequest) {
        self.request = request
        if case .location(let spec) = request.kind, let item = request.item {
            location = LocationPanelModel(spec: spec, item: item, library: request.library, undoManager: request.undoManager)
        }
        let items = request.library.items(in: .allItems)
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
        if isDate { shownValue = value }
    }

    var kind: ValueEditKind { request.kind }

    /// The type whose words a status panel edits: the item's own, since a status panel is for one item.
    var typeToEditStatuses: TypeID? {
        guard case .status = kind, let id = request.item else { return nil }
        return library.item(id)?.type
    }

    /// Closes the panel and opens the type in Settings > Types.
    func editStatuses(of type: TypeID) {
        close()
        ValueEditPresenter.shared.editType?(type)
    }
    var library: any ItemLibrary { request.library }

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

    /// Whether the item can still take the edit. An editor for an item that cannot closes itself, except a Location
    /// panel, which an item that cannot be edited still opens to show its point.
    var isEditable: Bool {
        if kind == .type { return library.offersTypeChange(for: request.targets) }
        if kind == .collections { return !library.collectionMembers(request.targets).isEmpty }
        if kind == .tags, !request.items.isEmpty { return request.items.contains { library.item($0)?.allows(.tags) == true } }
        guard let id = request.item else { return true }
        guard let item = library.item(id) else { return false }
        if case .location(let spec) = kind { return item.allows(.fields) || spec.hasPoint(item) }
        return item.allows(kind.change)
    }

    /// The tags or the words the panel holds, which its search field shows as chips.
    var heldTokens: [String] {
        switch kind {
        case .tags:
            // With several items, only the tags every one that can take tags holds: a tag that some lack is not held by
            // the selection.
            let held = request.targets.compactMap(library.item).filter { $0.allows(.tags) }.map { Set(library.tags(of: $0)) }
            guard let first = held.first else { return [] }
            return held.dropFirst().reduce(first) { $0.intersection($1) }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        case .words: return heldWords
        default: return []
        }
    }

    var hasSearch: Bool {
        switch kind {
        case .people, .tags, .collections, .words, .parent, .status, .choice, .type: true
        case .date, .text, .number, .location: false
        }
    }

    /// Whether the panel adds to what the value holds, which then shows one chip for each thing held.
    var holdsMany: Bool {
        switch kind {
        case .people, .tags, .collections, .words: true
        default: false
        }
    }

    /// What the search field asks for.
    var searchPrompt: LocalizedStringKey {
        switch kind {
        case .tags: "Add or Find a Tag"
        case .collections: "Find a Collection"
        case .words: "Add or Find a Word"
        case .parent: "Find an Item"
        case .type: "Find a Type"
        case .status, .choice: "Find an Option"
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
        /// What else the rows read that the library's revision does not say: the parent, or the collections held.
        let held: [String]
    }

    var rows: [ValueListRow] {
        let key = RowsKey(
            query: query, value: value, revision: library.contentRevision,
            day: isDate ? request.calendar.startOfDay(for: library.now()) : nil,
            held: kind == .parent ? parentTarget.map { [$0.id, $0.displayTitle] } ?? []
                : kind == .collections ? heldCollections.map(\.id.rawValue) : [])
        if let rowsCache, rowsCache.key == key { return rowsCache.rows }
        rowsBuilt += 1
        let built = buildRows()
        rowsCache = (key, built)
        return built
    }

    /// Whether `field` is a task's priority, whose options are colored by rank.
    private func isPriority(_ field: ItemTypeInfo.Field) -> Bool {
        library.catalogue.isPriority(field, of: field.declaredBy)
    }

    private func buildRows() -> [ValueListRow] {
        switch kind {
        case .status(let field): narrowed(ValueEditOptions.statusRows(field: field, current: value?.string))
        case .choice(let field): narrowed(ValueEditOptions.choiceRows(field: field, current: value?.string, isPriority: isPriority(field)))
        case .type: typeRows
        case .date: quickRows
        case .people(_, let shape): peopleRows(shape)
        case .tags: tagRows
        case .collections: collectionRows
        case .words: wordRows
        case .parent: parentRows
        case .text, .number, .location: []
        }
    }

    /// The rows whose title holds what is typed, under the headings that still have one, and no separator while
    /// something is typed.
    private func narrowed(_ rows: [ValueListRow]) -> [ValueListRow] {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return rows }
        var result: [ValueListRow] = []
        var heading: ValueListRow?
        for row in rows {
            switch row.role {
            case .header:
                heading = row
            case .separator:
                continue
            case .option, .create:
                guard row.title.localizedStandardContains(typed) else { continue }
                if let heading { result.append(heading) }
                heading = nil
                result.append(row)
            }
        }
        return result
    }

    private var typeRows: [ValueListRow] {
        let options = library.typeChangeOptions(for: request.targets).map {
            ValueListRow(id: Self.typePrefix + $0.id.rawValue, role: .option, title: $0.label, mark: .type(icon: $0.icon))
        }
        return narrowed(options)
    }

    static let typePrefix = "type:"

    /// The items the parent could be, read once for the panel.
    @ObservationIgnored private(set) lazy var parentCandidates: [Item] =
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
        default: return rows.first { $0.id != Self.openID }?.id ?? rows.first?.id
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

    /// The most a list is tall: ten rows, past which it scrolls. A status list, which is grouped under headings, is as tall
    /// as its groups.
    func listLimit(scale: CGFloat) -> CGFloat {
        if case .status = kind { return .infinity }
        return CGFloat(ValueEditMetrics.visibleRows) * ValueEditMetrics.rowHeight * scale
    }

    /// The height the content wants with nothing scrolled past `listLimit`.
    func naturalHeight(scale: CGFloat) -> CGFloat { totalHeight + max(0, min(rowsHeight, listLimit(scale: scale)) - listHeight) }

    func move(by step: Int) {
        let rows = navigable
        guard !rows.isEmpty else { return }
        viaKeyboard = true
        // The first arrow starts from the value the field holds, as a menu opens on its checked item.
        guard let current = activeRow.flatMap({ id in rows.firstIndex { $0.id == id } }) ?? Self.onlyCurrent(in: rows) else {
            highlight = (step > 0 ? rows.first : rows.last)?.id
            return
        }
        highlight = rows[min(max(current + step, 0), rows.count - 1)].id
    }

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
        guard isEditable else {
            // What was typed has nowhere to go now, so it goes back to the person before the panel ends.
            if unsaved == nil, isTypedEntry(id) { unsaved = UnsavedInput(text: query) }
            handBackUnsaved()
            query = ""
            close()
            return
        }
        switch kind {
        case .status, .choice:
            guard let word = ValueEditOptions.word(of: id), commit(.string(word)), kind.closesOnChoice else { return }
            close()
        case .date:
            if id == ValueEditOptions.notSetID {
                if value != nil { clearDate() }
                return
            }
            guard let entry = quickDates.first(where: { "quick:" + $0.id == id }) else { return }
            chooseDay(entry.date)
            if notice == nil { close() }
        case .people(_, let shape): activatePerson(id, shape)
        case .tags: activateTag(id)
        case .collections: activateCollection(id)
        case .words: activateWord(id)
        case .parent: activateParent(id)
        case .type: activateType(id)
        case .text, .number, .location: break
        }
    }

    /// Changes the type once every open page has handed over its last edit. A type that needs a value the items lack is
    /// asked for in the window, since the panel holds no field for it. A change the library refuses is told in a notice,
    /// and the panel stays.
    private func activateType(_ id: String) {
        guard id.hasPrefix(Self.typePrefix) else { return }
        let type = TypeID(String(id.dropFirst(Self.typePrefix.count)))
        let targets = request.targets
        guard library.typeChangePlan(targets, to: type).missing.isEmpty else {
            request.needsValues(type)
            close()
            return
        }
        library.changeTypeAfterSaving(targets, to: type, filling: [:], undoManager: request.undoManager) { [weak self] sent in
            if sent { self?.close() }
        }
    }

    /// Why the list cannot take `count` entries, in the person's words, or nil where its field takes them. Only a
    /// limit the catalogue declares is judged here; the server judges each entry's form (a web or mail address) and
    /// the library tells its reason when it refuses the write, as it does for any queued edit.
    func limitReason(holding count: Int) -> String? {
        guard let field = kind.field, !field.holds(count), let limit = field.maxItems else { return nil }
        return String(localized: "\(field.label) can hold \(limit) at most.")
    }

    /// What the value holds, as the chips in the search field: one for each tag, word or person, and the one value of a
    /// panel that closes on choosing.
    var chips: [ValueChip] {
        switch kind {
        case .tags:
            return heldTokens.map { ValueChip(id: "tag:" + $0, title: $0, mark: .tag) }
        case .collections:
            return heldCollections.map {
                ValueChip(id: Self.collectionPrefix + $0.id.rawValue, title: $0.displayTitle, mark: .type(icon: library.catalogue.icon(for: $0.type)))
            }
        case .words:
            return heldTokens.map { ValueChip(id: "word:" + $0, title: $0, mark: .tag) }
        case .people(_, let shape):
            return PeopleSuggestions.held(in: value, shape: shape).map {
                ValueChip(id: $0.id, title: $0.person.name, mark: .person(initials: PersonInitials.of($0.person.name) ?? ""))
            }
        case .status(let field):
            guard let word = value?.string, !word.isEmpty, case .status(let words) = field.kind else { return [] }
            let group = words.first { $0.value == word }?.group
            return [ValueChip(id: ValueEditOptions.optionID(word), title: ItemTypeInfo.Field.label(ofOption: word), mark: .status(group), isRemovable: !field.required)]
        case .choice(let field):
            guard let word = value?.string, !word.isEmpty else { return [] }
            return [ValueChip(id: ValueEditOptions.optionID(word), title: ItemTypeInfo.Field.label(ofOption: word), mark: .dot(OptionTone.tone(of: word, in: field, isPriority: isPriority(field))), isRemovable: !field.required)]
        case .parent:
            guard let current = parentTarget else { return [] }
            return [ValueChip(id: "parent:" + current.id, title: current.displayTitle)]
        case .type:
            let types = Set(request.targets.compactMap { library.item($0)?.type })
            guard types.count == 1, let type = types.first else { return [] }
            return [ValueChip(id: Self.typePrefix + type.rawValue, title: library.catalogue.label(for: type), mark: .type(icon: library.catalogue.icon(for: type)), isRemovable: false, givesType: true)]
        case .date, .text, .number, .location:
            return []
        }
    }

    /// Takes one chip's value away: a tag, word or person from the list it is in, or the one value of a status, a choice
    /// or a parent.
    func remove(_ chip: ValueChip) {
        guard isEditable, chip.isRemovable else { return }
        switch kind {
        case .tags, .words: removeToken(chip.title)
        case .people: activate(chip.id)
        case .collections:
            guard chip.id.hasPrefix(Self.collectionPrefix) else { return }
            library.removeFromCollection(request.targets, ItemID(String(chip.id.dropFirst(Self.collectionPrefix.count))), undoManager: request.undoManager)
        case .status, .choice: commit(nil)
        case .parent:
            guard !isSaving, let item = request.item else { return }
            changeParent(of: item, adding: nil, removing: parentTarget?.itemID)
        default: break
        }
    }

    /// Backspace in an empty search field takes the last chip away, as the field of a tag list always has.
    @discardableResult
    func removeLastChip() -> Bool {
        guard query.isEmpty, let chip = chips.last(where: \.isRemovable) else { return false }
        remove(chip)
        return true
    }

    /// Removes one tag or word from the tokens above the field.
    func removeToken(_ token: String) {
        guard isEditable else { return }
        switch kind {
        case .tags:
            if !request.targets.isEmpty { library.removeTag(token, from: request.targets, undoManager: request.undoManager) }
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

    /// Why a write was refused: the item is gone or can no longer be edited, else `fallback`.
    func refusalReason(_ fallback: String) -> String {
        guard let id = request.item else { return fallback }
        guard let item = library.item(id) else { return String(localized: "This item is no longer available.") }
        return item.allows(kind.change) ? fallback : PropertyLoss.notEditable.reason
    }

    /// The editor is ending. A text or number the person typed is written or handed back unless they cancelled it
    /// themselves; ending the panel any other way (a click elsewhere, a resized window, another item) never loses it.
    func finish(cancelled: Bool) {
        isFinished = true
        location?.finish(cancelled: cancelled)
        guard !cancelled else {
            // The time field loses focus as the panel goes, which would otherwise write what was cancelled.
            unsaved = nil
            return
        }
        commitTime(isEnding: true)
        handBackUnsaved()
        guard kind.isTyped, let field = kind.field else { return }
        draft.handOff(
            label: field.label, as: field.kind, rule: field.numberRule, current: currentText, isEditable: isEditable,
            write: request.write, to: library.notices)
    }

    /// What the time field is showing while the person types in it, nil while it shows the value's own time.
    var timeDraft: String? {
        get { isDate ? unsaved?.text : nil }
        set {
            guard let newValue else { return unsaved = nil }
            if unsaved == nil { unsaved = UnsavedInput(text: newValue, base: shownValue) } else { unsaved?.text = newValue }
        }
    }

    // MARK: Writing

    @discardableResult
    func commit(_ new: PropertyValue?, failure: String = String(localized: "The value could not be saved.")) -> Bool {
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
