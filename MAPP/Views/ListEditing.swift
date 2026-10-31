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

    /// The identity of each entry of `known`, in order. Matched to the stored list as the view draws, so neither is
    /// observed.
    @ObservationIgnored private var ids: [UUID] = []
    /// The entries as the editor last saw them.
    @ObservationIgnored private var known: [PropertyValue] = []
    /// Typed text whose entry went from the list elsewhere, waiting to go back to the person.
    @ObservationIgnored private var orphans: [String] = []
    /// The text typed into each member and not yet written.
    @ObservationIgnored private var drafts: [Slot: ItemPropertyDraft] = [:]
    /// The entry each member's text began from, to tell whether the entry changed under it.
    @ObservationIgnored private var entryBases: [Slot: Entry] = [:]
    /// The identity the entry being added takes once it is added, so its text stays with it.
    private(set) var pendingID = UUID()
    /// The settled members of the entry being added, kept until the entry holds what the list requires.
    private(set) var pending: Entry?
    /// Why the last change was not made, in the person's words.
    var notice: String?

    // MARK: Identity

    /// The entries of `value`, each with its identity in this editor.
    func rows(of value: PropertyValue?) -> [Row] {
        sync(ListEntries.entries(of: value))
        return zip(ids, known).map { Row(id: $0, entry: $1) }
    }

    /// Matches identities to `entries` after a change the editor did not make: the same entry where it was, then the
    /// same entry anywhere, then, where as many entries changed as were left, each changed entry to the one in its
    /// place that shares a member value with it. An entry matched no other way is new, and the text typed into an
    /// entry that is gone waits in `orphans`.
    private func sync(_ entries: [PropertyValue]) {
        guard entries != known || ids.count != entries.count else { return }
        var unused = Array(known.indices)
        var matched = [Int?](repeating: nil, count: entries.count)
        for (index, entry) in entries.enumerated() where known.indices.contains(index) && known[index] == entry {
            matched[index] = index
            unused.removeAll { $0 == index }
        }
        for (index, entry) in entries.enumerated() where matched[index] == nil {
            guard let old = unused.first(where: { known[$0] == entry }) else { continue }
            matched[index] = old
            unused.removeAll { $0 == old }
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
                orphans.append("\(ItemTypeInfo.Field.displayLabel(MarfaMapping.label(forField: slot.member))): \(draft.text)")
            }
            drafts[slot] = nil
            entryBases[slot] = nil
        }
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
        guard set(member.key, to: new, of: id, in: shape, value: value, write: write) else {
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
        notice = nil
        if id == pendingID {
            var entry = pending ?? [:]
            entry[member] = new
            if let refusal = shape.refusal(of: entry, ignoringMissingRequired: true) {
                notice = refusal
                return false
            }
            pending = entry
            if shape.refusal(of: entry) == nil, send(ListEntries.appending(entry, to: value), over: value, in: shape, write: write) {
                // The entry keeps the identity it was typed under, so text still being typed into it stays with it.
                ids.append(pendingID)
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
        guard send(ListEntries.setting(member, to: new, at: current.index, in: value), over: value, in: shape, write: write) else { return false }
        // Text still typed into the entry's other members began before this change, which was the person's own.
        for slot in entryBases.keys where slot.entry == id { entryBases[slot] = fields }
        return true
    }

    /// Writes `new` in place of `current`, unless it holds faults Marfa refuses the whole list for and is no nearer a
    /// list Marfa takes: a repair (removing an entry or a member the list does not take) is written, a change beside a
    /// fault is not.
    private func send(_ new: PropertyValue?, over current: PropertyValue?, in shape: ListShape, write: (PropertyValue?) -> Bool) -> Bool {
        let faults = shape.faults(in: ListEntries.entries(of: new))
        if faults > 0, faults >= shape.faults(in: ListEntries.entries(of: current)) {
            notice = String(localized: "The list can’t be saved while it holds an entry it doesn’t take. Correct or remove the entries marked in this list.")
            return false
        }
        guard write(new) else {
            notice = String(localized: "The list could not be saved.")
            return false
        }
        known = ListEntries.entries(of: new)
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
        guard let index = entry(id, in: value)?.index,
              send(ListEntries.removing(at: index, from: value), over: value, in: shape, write: write) else { return }
        ids.remove(at: index)
        for slot in drafts.keys where slot.entry == id {
            drafts[slot] = nil
            entryBases[slot] = nil
        }
    }

    /// Moves entry `id` to `destination`, its place in the list after the move.
    func move(_ id: UUID, to destination: Int, in shape: ListShape, value: PropertyValue?, write: (PropertyValue?) -> Bool) {
        notice = nil
        guard let index = entry(id, in: value)?.index, ids.indices.contains(destination),
              send(ListEntries.moving(from: index, to: destination, in: value), over: value, in: shape, write: write) else { return }
        ids.insert(ids.remove(at: index), at: destination)
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
    /// the stored list.
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
        pending = nil
        notice = nil
    }
}
