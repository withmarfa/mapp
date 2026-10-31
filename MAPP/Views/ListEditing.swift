import Foundation
import Observation

/// The person's work on one list of entries: which entry is which while the list changes under it, the entry being
/// added, and the text typed into each member that is not yet written. It belongs to the property's draft
/// (`ItemPropertyDraft.list`), so it lasts as long as the work does, not as long as the rows on screen.
///
/// An entry keeps its identity through the editor's own add, remove and move, and through a change made elsewhere
/// where it can be matched by content, so typed text never moves to another entry. A member's text is written against
/// the entry it began from: where that entry changed elsewhere meanwhile, the text is kept and the person chooses, as
/// a single property's row does. Text that can be neither written nor kept on screen goes back to the person through
/// `Notices.notKept`, which puts it on the clipboard.
///
/// A library may take a write later than it is made (`MarfaLibrary` queues it), so the editor shows the list it last
/// wrote, with the identities it gave, until the stored list shows it, and builds the next change on it. A write the
/// library refuses puts the stored list back on screen and what the person gave it back in its fields; a change made
/// elsewhere meanwhile is matched by content against the list the editor wrote.
@Observable
final class ListEditing {
    typealias Entry = ListEntries.Entry

    /// One member of one entry, the entry known by its identity in this editor rather than its place in the list.
    struct Slot: Hashable {
        let entry: UUID
        let member: String
    }

    /// An entry as the editor shows it.
    struct Row: Identifiable {
        let id: UUID
        let entry: PropertyValue
    }

    /// A list the editor wrote that the stored list may not show yet.
    private struct Flight {
        let entries: [PropertyValue]
        let ids: [UUID]
        /// What the person gave the write, which goes back to them if it is refused.
        let given: Given?
    }

    private enum Given {
        case text(Slot, base: String?, text: String)
        case entry(UUID, Entry)
    }

    /// The identity of each entry of `known`, in order. Matched to the stored list as the view draws, so neither is
    /// observed.
    @ObservationIgnored private var ids: [UUID] = []
    /// The entries as the editor last saw them, or last wrote them while a write is in flight.
    @ObservationIgnored private var known: [PropertyValue] = []
    /// The writes the stored list does not show yet, oldest first; `known` is the last one's list.
    @ObservationIgnored private var flights: [Flight] = []
    /// The stored list, and its identities, from before the oldest write in flight.
    @ObservationIgnored private var settled: (entries: [PropertyValue], ids: [UUID]) = ([], [])
    /// Whether the library still had a write of the item on its way when the view last drew.
    @ObservationIgnored private var writing = false
    /// Typed text whose entry went from the list elsewhere, waiting to go back to the person. Observed, as `drafts`
    /// is, so a view that tells of unsaved work follows it.
    private var orphans: [String] = []
    /// The text typed into each member and not yet written.
    private var drafts: [Slot: ItemPropertyDraft] = [:]
    /// The entry each member's text began from, to tell whether the entry changed under it.
    @ObservationIgnored private var entryBases: [Slot: Entry] = [:]
    /// The identity the entry being added takes once it is added, so its text stays with it.
    private(set) var pendingID = UUID()
    /// The settled members of the entry being added, kept until the entry holds what the list requires.
    private(set) var pending: Entry?
    /// Why the last change was not made, in the person's words.
    var notice: String?

    // MARK: Identity

    /// The entries of `value`, each with its identity in this editor. `writing` says whether the library still has a
    /// write of the item on its way (`ItemLibrary.isWritingProperties(of:)`), so a stored list that does not yet show
    /// the editor's last write is waited for while it is true and taken as a refusal once it is false.
    func rows(of value: PropertyValue?, writing: Bool = false) -> [Row] {
        self.writing = writing
        sync(ListEntries.entries(of: value))
        return zip(ids, known).map { Row(id: $0, entry: $1) }
    }

    /// Follows the stored list. While writes are in flight: a stored list that shows one of them settles it and those
    /// before it; one that still shows the list from before them, or an earlier write, waits while the library is
    /// writing and is a refusal of the rest once it is not; any other list was changed elsewhere and is matched
    /// against the list the editor wrote, then the one from before its writes.
    private func sync(_ entries: [PropertyValue]) {
        if !flights.isEmpty {
            if let landed = flights.lastIndex(where: { $0.entries == entries }) {
                settled = (flights[landed].entries, flights[landed].ids)
                flights.removeFirst(landed + 1)
                if !flights.isEmpty, !writing { fallBack() }
                return
            }
            if entries == settled.entries {
                if !writing { fallBack() }
                return
            }
            flights = []
            return match(entries, before: settled)
        }
        match(entries)
    }

    /// Matches identities to `entries` after a change the editor did not make: the entries that stayed, in order (the
    /// longest run common to both lists, so an entry inserted before identical ones does not shift their identities),
    /// then the same entry anywhere, nearest its old place first, then, where as many entries changed as were left,
    /// each changed entry to the one in its place that shares a member value with it. An entry matched no other way
    /// is new, and the text typed into an entry that is gone waits in `orphans`.
    private func match(_ entries: [PropertyValue], before: (entries: [PropertyValue], ids: [UUID])? = nil) {
        guard entries != known || ids.count != entries.count else { return }
        var matched = Self.commonRun(known, entries)
        var unused = Set(known.indices).subtracting(matched.compactMap { $0 }).sorted()
        for (index, entry) in entries.enumerated() where matched[index] == nil {
            guard let old = unused.filter({ known[$0] == entry }).min(by: { abs($0 - index) < abs($1 - index) }) else { continue }
            matched[index] = old
            unused.removeAll { $0 == old }
        }
        // An entry the editor changed in a write that a change elsewhere overtook is still the entry it was before.
        if let before {
            for (index, entry) in entries.enumerated() where matched[index] == nil {
                guard let old = unused.first(where: { candidate in
                    zip(before.entries, before.ids).contains { $0.0 == entry && $0.1 == ids[candidate] }
                }) else { continue }
                matched[index] = old
                unused.removeAll { $0 == old }
            }
        }
        let changed = entries.indices.filter { matched[$0] == nil }
        if changed.count == unused.count {
            for (index, old) in zip(changed, unused) where Self.sharesAValue(known[old], entries[index]) {
                matched[index] = old
            }
            let paired = Set(matched.compactMap { $0 })
            unused.removeAll { paired.contains($0) }
        }
        let gone = Set(unused.map { ids[$0] })
        ids = entries.indices.map { matched[$0].map { ids[$0] } ?? UUID() }
        known = entries
        for slot in drafts.keys.sorted(by: { $0.member < $1.member }) where gone.contains(slot.entry) {
            if let draft = drafts[slot], draft.isDirty, draft.text != draft.base {
                orphans.append("\(Self.label(of: slot.member)): \(draft.text)")
            }
            drafts[slot] = nil
            entryBases[slot] = nil
        }
    }

    /// For each entry of `new`, the place in `old` of the same entry where both lists keep it in the same order: the
    /// longest common subsequence, which keeps the earlier of equal choices so identical entries keep their order.
    private static func commonRun(_ old: [PropertyValue], _ new: [PropertyValue]) -> [Int?] {
        var lengths = [[Int]](repeating: [Int](repeating: 0, count: new.count + 1), count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                lengths[i][j] = old[i] == new[j] ? lengths[i + 1][j + 1] + 1 : max(lengths[i + 1][j], lengths[i][j + 1])
            }
        }
        var matched = [Int?](repeating: nil, count: new.count)
        var i = 0, j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                matched[j] = i
                i += 1
                j += 1
            } else if lengths[i + 1][j] >= lengths[i][j + 1] {
                i += 1
            } else {
                j += 1
            }
        }
        return matched
    }

    /// The writes in flight were refused: the stored list is shown again with the identities it had, and what the
    /// person gave the writes goes back where they gave it, or back to them through `orphans` where that place is
    /// gone. Text typed again since is kept over what was given.
    private func fallBack() {
        let refused = flights
        flights = []
        known = settled.entries
        ids = settled.ids
        for flight in refused {
            switch flight.given {
            case .entry(let id, let entry):
                if pending?.isEmpty != false, !drafts.contains(where: { $0.key.entry == pendingID && $0.value.isDirty }) {
                    for slot in drafts.keys where slot.entry == pendingID { drafts[slot] = nil }
                    pendingID = id
                    pending = entry
                } else {
                    orphans.append(String(localized: "New entry: \(Self.text(of: entry))"))
                }
            case .text(let slot, let base, let text):
                if let draft = drafts[slot], draft.isDirty { continue }
                guard slot.entry == pendingID || ids.contains(slot.entry) else {
                    orphans.append("\(Self.label(of: slot.member)): \(text)")
                    continue
                }
                let draft = draft(slot)
                draft.base = base
                draft.text = text
                draft.isDirty = true
                draft.rejected = true
                if let index = ids.firstIndex(of: slot.entry) { entryBases[slot] = ListEntries.object(known[index]) }
            case nil:
                break
            }
        }
        // Text typed into an entry that only a refused write held has no field to show it in.
        for slot in drafts.keys.sorted(by: { $0.member < $1.member }) where slot.entry != pendingID && !ids.contains(slot.entry) {
            if let draft = drafts[slot], draft.isDirty, draft.text != draft.base { orphans.append("\(Self.label(of: slot.member)): \(draft.text)") }
            drafts[slot] = nil
            entryBases[slot] = nil
        }
        notice = String(localized: "The list could not be saved.")
    }

    private static func label(of member: String) -> String {
        ItemTypeInfo.Field.displayLabel(MarfaMapping.label(forField: member))
    }

    private static func text(of entry: Entry) -> String {
        entry.sorted { $0.key < $1.key }.map { "\(label(of: $0.key)): \(ListShape.editing($0.value))" }.joined(separator: ", ")
    }

    private static func sharesAValue(_ old: PropertyValue, _ new: PropertyValue) -> Bool {
        guard let old = ListEntries.object(old), let new = ListEntries.object(new) else { return false }
        return old.contains { new[$0.key] == $0.value }
    }

    /// The entry with identity `id` in `value`, and its place, or nil where it is gone.
    private func entry(_ id: UUID, in value: PropertyValue?) -> (index: Int, fields: Entry?)? {
        sync(ListEntries.entries(of: value))
        guard let index = ids.firstIndex(of: id) else { return nil }
        return (index, ListEntries.object(known[index]))
    }

    // MARK: Typing

    /// The text typed into a member, made on first use.
    func draft(_ slot: Slot) -> ItemPropertyDraft {
        if let draft = drafts[slot] { return draft }
        let draft = ItemPropertyDraft()
        drafts[slot] = draft
        return draft
    }

    /// The text a member shows: what was typed, or else what the entry holds.
    func text(_ slot: Slot, in value: PropertyValue?) -> String {
        if let draft = drafts[slot], draft.isDirty { return draft.text }
        return ListShape.editing(stored(slot, in: value))
    }

    /// The person typed `text` into a member. The first keystroke records what the member and its entry held, which a
    /// later write is checked against.
    func type(_ text: String, into slot: Slot, in value: PropertyValue?) {
        let draft = draft(slot)
        guard text != self.text(slot, in: value) else { return }
        if !draft.isDirty {
            draft.base = ListShape.editing(stored(slot, in: value))
            if slot.entry != pendingID { entryBases[slot] = entry(slot.entry, in: value)?.fields }
        }
        draft.text = text
        draft.isDirty = true
        draft.rejected = false
    }

    /// Whether the entry changed elsewhere since the member's text began, so writing it would replace a change the
    /// person has not seen.
    func conflicts(_ slot: Slot, in value: PropertyValue?) -> Bool {
        guard let draft = drafts[slot], draft.isDirty, let base = entryBases[slot],
              let current = entry(slot.entry, in: value) else { return false }
        let typed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        return typed != ListShape.editing(current.fields?[slot.member]) && draft.text != draft.base && current.fields != base
    }

    /// Drops what was typed into a member, which shows what the entry holds again.
    func discard(_ slot: Slot, in value: PropertyValue?) {
        drafts[slot]?.discard(toMatch: ListShape.editing(stored(slot, in: value)))
        entryBases[slot] = nil
        notice = nil
    }

    private func stored(_ slot: Slot, in value: PropertyValue?) -> PropertyValue? {
        if slot.entry == pendingID { return pending?[slot.member] }
        return entry(slot.entry, in: value)?.fields?[slot.member]
    }

    // MARK: Writing

    /// Writes the text typed into `member` of entry `id` (`pendingID` for the entry being added). Returns whether the
    /// text is settled; false keeps it as typed, with `notice` saying why, or the conflict for the person to answer.
    @discardableResult
    func commit(
        _ member: ListShape.Member, of id: UUID, in shape: ListShape, value: PropertyValue?, overwriting: Bool = false,
        write: (PropertyValue?) -> Bool
    ) -> Bool {
        let slot = Slot(entry: id, member: member.key)
        guard let draft = drafts[slot], draft.isDirty else { return true }
        let typed = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed == ListShape.editing(stored(slot, in: value)) {
            discard(slot, in: value)
            return true
        }
        if !overwriting, conflicts(slot, in: value) { return false }
        let new: PropertyValue?
        if typed.isEmpty {
            new = nil
        } else if case .number(let rule) = member.kind {
            guard let number = PropertyNumber.parse(typed, integer: rule.integer) else {
                return refuse(draft, PropertyLoss.notANumber.reason)
            }
            guard rule.allows(number) else { return refuse(draft, rule.requirement ?? PropertyLoss.outOfRange.reason) }
            new = .number(number)
        } else {
            new = .string(typed)
        }
        let given = Given.text(slot, base: draft.base, text: draft.text)
        guard apply(member.key, to: new, of: id, in: shape, value: value, giving: given, write: write) else {
            draft.rejected = true
            return false
        }
        draft.discard(toMatch: ListShape.editing(new))
        entryBases[slot] = nil
        return true
    }

    private func refuse(_ draft: ItemPropertyDraft, _ reason: String) -> Bool {
        draft.rejected = true
        notice = reason
        return false
    }

    /// Sets one member of entry `id`, or of the entry being added, to `new` (nil removes it); whether it was set. The
    /// entry being added is written once it holds what the list requires, and kept as it is where the write is
    /// refused.
    @discardableResult
    func set(
        _ member: String, to new: PropertyValue?, of id: UUID, in shape: ListShape, value: PropertyValue?,
        write: (PropertyValue?) -> Bool
    ) -> Bool {
        apply(member, to: new, of: id, in: shape, value: value, giving: nil, write: write)
    }

    private func apply(
        _ member: String, to new: PropertyValue?, of id: UUID, in shape: ListShape, value: PropertyValue?, giving given: Given?,
        write: (PropertyValue?) -> Bool
    ) -> Bool {
        notice = nil
        if id == pendingID {
            var entry = pending ?? [:]
            entry[member] = new
            if let refusal = shape.refusal(of: entry, ignoringMissingRequired: true) {
                notice = refusal
                return false
            }
            pending = entry
            guard shape.refusal(of: entry) == nil else { return true }
            let base = base(value)
            // The entry keeps the identity it was typed under, so text still being typed into it stays with it.
            if send(ListEntries.appending(entry, to: base), over: base, ids: ids + [pendingID], giving: .entry(pendingID, entry), in: shape, write: write) {
                pending = nil
                pendingID = UUID()
            }
            return true
        }
        guard let current = entry(id, in: value), var fields = current.fields else {
            notice = String(localized: "The entry was removed while you were editing it.")
            return false
        }
        fields[member] = new
        if let refusal = shape.refusal(of: fields), shape.faults(in: [.object(fields)]) >= shape.faults(in: [known[current.index]]) {
            notice = refusal
            return false
        }
        let base = base(value)
        guard send(ListEntries.setting(member, to: new, at: current.index, in: base), over: base, ids: ids, giving: given, in: shape, write: write)
        else { return false }
        // Text still typed into the entry's other members began before this change, which was the person's own.
        for slot in entryBases.keys where slot.entry == id { entryBases[slot] = fields }
        return true
    }

    /// The list a change builds on: the one the editor last wrote while that is in flight, else the stored one.
    private func base(_ value: PropertyValue?) -> PropertyValue? {
        sync(ListEntries.entries(of: value))
        return flights.isEmpty ? value : .array(known)
    }

    /// Writes `new`, whose entries have identities `newIDs`, in place of `current`, unless it holds faults Marfa
    /// refuses the whole list for and is no nearer a list Marfa takes: a repair (removing an entry or a member the
    /// list does not take) is written, a change beside a fault is not. The editor shows `new` from here on, until the
    /// stored list settles it.
    private func send(
        _ new: PropertyValue?, over current: PropertyValue?, ids newIDs: [UUID], giving given: Given?, in shape: ListShape,
        write: (PropertyValue?) -> Bool
    ) -> Bool {
        let faults = shape.faults(in: ListEntries.entries(of: new))
        if faults > 0, faults >= shape.faults(in: ListEntries.entries(of: current)) {
            notice = String(localized: "The list can’t be saved while it holds an entry it doesn’t take. Correct or remove the entries marked in this list.")
            return false
        }
        guard write(new) else {
            notice = String(localized: "The list could not be saved.")
            return false
        }
        if flights.isEmpty { settled = (known, ids) }
        known = ListEntries.entries(of: new)
        ids = newIDs
        flights.append(Flight(entries: known, ids: newIDs, given: given))
        // Until the view draws again with the library's own word, a stored list without the write is not a refusal.
        writing = true
        return true
    }

    /// Starts an entry to add.
    func startEntry() {
        pending = [:]
        notice = nil
    }

    /// Drops the entry being added and what was typed into it, at the person's word.
    func cancelEntry() {
        pending = nil
        for slot in drafts.keys where slot.entry == pendingID { drafts[slot] = nil }
        notice = nil
    }

    /// Removes entry `id`, at the person's word, with anything typed into it.
    func remove(_ id: UUID, in shape: ListShape, value: PropertyValue?, write: (PropertyValue?) -> Bool) {
        notice = nil
        guard let index = entry(id, in: value)?.index else { return }
        let base = base(value)
        var newIDs = ids
        newIDs.remove(at: index)
        guard send(ListEntries.removing(at: index, from: base), over: base, ids: newIDs, giving: nil, in: shape, write: write) else { return }
        for slot in drafts.keys where slot.entry == id {
            drafts[slot] = nil
            entryBases[slot] = nil
        }
    }

    /// Moves entry `id` to `destination`, its place in the list after the move.
    func move(_ id: UUID, to destination: Int, in shape: ListShape, value: PropertyValue?, write: (PropertyValue?) -> Bool) {
        notice = nil
        guard let index = entry(id, in: value)?.index, ids.indices.contains(destination), index != destination else { return }
        let base = base(value)
        var newIDs = ids
        newIDs.insert(newIDs.remove(at: index), at: destination)
        _ = send(ListEntries.moving(from: index, to: destination, in: base), over: base, ids: newIDs, giving: nil, in: shape, write: write)
    }

    // MARK: Leaving

    /// Whether anything the person typed into the list is not yet written.
    var holdsUnsavedWork: Bool {
        pending?.isEmpty == false || !orphans.isEmpty || drafts.values.contains { $0.isDirty && $0.text != $0.base }
    }

    /// What the person typed that is not yet written, as text for the clipboard, or nil where there is none.
    func unsavedText(in shape: ListShape) -> String? {
        func dirty(_ slot: Slot) -> String? {
            guard let draft = drafts[slot], draft.isDirty, draft.text != draft.base else { return nil }
            return draft.text
        }
        var parts: [String] = []
        for id in ids {
            for member in shape.members {
                if let text = dirty(Slot(entry: id, member: member.key)) { parts.append("\(member.label): \(text)") }
            }
        }
        parts += orphans
        let added = shape.members.compactMap { member -> String? in
            guard let text = dirty(Slot(entry: pendingID, member: member.key)) ?? pending.flatMap({ shape.text(of: member, in: $0) })
            else { return nil }
            return "\(member.label): \(text)"
        }
        if !added.isEmpty { parts.append(String(localized: "New entry: \(added.joined(separator: ", "))")) }
        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    /// Gives back text typed into entries that went from the list elsewhere.
    func handBackOrphans(label: String, to notices: Notices) {
        guard !orphans.isEmpty else { return }
        notices.notKept(
            String(localized: "Property Not Saved"), text: "\(label): \(orphans.joined(separator: "; "))",
            reason: String(localized: "The entry changed or was removed while you were editing it."))
        orphans = []
    }

    /// Leaves nothing the person typed behind, since the list's editor is gone for good: what can be written is
    /// written, and the rest goes back through `notices`, which puts it on the clipboard. The editor starts again from
    /// the stored list; a write still in flight is the library's to keep or give back from here.
    func leave(
        _ shape: ListShape, label: String, value: PropertyValue?, isEditable: Bool, write: (PropertyValue?) -> Bool,
        to notices: Notices
    ) {
        var current = value
        let writing: (PropertyValue?) -> Bool = { new in
            guard write(new) else { return false }
            current = new
            return true
        }
        var conflicted = false
        if isEditable {
            for id in ids + [pendingID] {
                for member in shape.members where drafts[Slot(entry: id, member: member.key)]?.isDirty == true {
                    conflicted = conflicts(Slot(entry: id, member: member.key), in: current) || conflicted
                    commit(member, of: id, in: shape, value: current, write: writing)
                }
            }
        }
        if let text = unsavedText(in: shape) {
            let reason = if !isEditable { PropertyLoss.notEditable.reason }
                else if conflicted { PropertyLoss.conflict.reason }
                else if pending?.isEmpty == false, shape.refusal(of: pending ?? [:]) != nil { String(localized: "The new entry wasn’t finished, so it wasn’t added.") }
                else { notice ?? PropertyLoss.notSaved.reason }
            notices.notKept(String(localized: "Property Not Saved"), text: "\(label): \(text)", reason: reason)
        }
        drafts = [:]
        entryBases = [:]
        orphans = []
        flights = []
        pending = nil
        notice = nil
    }
}
