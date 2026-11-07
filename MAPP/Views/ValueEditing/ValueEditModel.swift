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

    var rows: [ValueListRow] {
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
            setDate(entry.date)
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

    private func activateWord(_ id: String) {
        let word = id == "create" ? query.trimmingCharacters(in: .whitespacesAndNewlines) : String(id.dropFirst("word:".count))
        guard !word.isEmpty else { return }
        guard !heldWords.contains(where: { $0.lowercased() == word.lowercased() }) else {
            query = ""
            return
        }
        if commitWords(heldWords + [word]) {
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
    private func commitWords(_ words: [String]) -> Bool {
        commit(words.isEmpty ? nil : .array(words.map { .string($0) }), failure: String(localized: "The list could not be saved."))
    }

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
            notice = refusalReason(failure)
        }
        return taken
    }
}
