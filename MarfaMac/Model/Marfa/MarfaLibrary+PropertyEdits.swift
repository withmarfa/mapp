import Foundation

/// An Undo or Redo of a property edit is made only if, for every key it sets, the item as it stands holds exactly the
/// value the step before it left; otherwise none of it is written and the person is told, as for a state (`setStates`).
/// The item as it stands is the copy, with this Mac's edits it has not yet taken laid over it, which is what the person
/// has on screen; an Undo puts back what they had on screen when they made the edit.
///
/// Where that value came from an earlier edit of this Mac's that the server had not answered for certain, the Undo is
/// made only once that edit is known to be made. One that was not made, or whose answer can't be read, refuses the
/// Undo for good; one with no final answer yet refuses it for now and puts it back on the undo stack. Nothing waits.
extension MarfaLibrary {
    /// One property edit this Mac made, followed until its final answer.
    final class PropertyEdit {
        /// What the server's final answer left of one key.
        enum Kept: Equatable {
            /// The item holds this value after the edit.
            case set(PropertyValue?)
            /// The edit was refused or withdrawn.
            case notMade
            /// The server named the key in a merge or conflict, and its answer could not be read.
            case unknown
        }

        /// What is known of whether the server kept what the edit set of one key.
        enum Standing {
            case kept, notKept, unknown, unanswered
        }

        let item: ItemID
        let changes: [String: PropertyValue?]
        /// What the person had on screen for each key when they made the edit.
        let before: [String: PropertyValue?]
        /// For each key, the edit of this Mac's that `before` came from, where the server had not answered it for certain.
        let builtOn: [String: PropertyEdit]
        /// Whether the copy has taken it, after which the copy shows it.
        var taken = false
        /// Nil until the final answer: a blocked or dead write is sent again once released.
        var kept: [String: Kept]?

        init(item: ItemID, changes: [String: PropertyValue?], before: [String: PropertyValue?], builtOn: [String: PropertyEdit]) {
            self.item = item
            self.changes = changes
            self.before = before
            self.builtOn = builtOn
        }

        func standing(_ key: String) -> Standing {
            guard let kept else { return .unanswered }
            switch kept[key] {
            case .set(let value)? where value == changes[key] ?? nil: return .kept
            case .unknown?: return .unknown
            default: return .notKept
            }
        }

        /// A key the verdict names was resolved by the server, so only the answer's item says what it holds.
        static func kept(_ changes: [String: PropertyValue?], after outcome: WriteOutcome) -> [String: Kept]? {
            switch outcome {
            case .accepted:
                return changes.mapValues { .set($0) }
            case .merged(let fields, let resolved), .conflicted(_, let fields, let resolved):
                return Dictionary(uniqueKeysWithValues: changes.map { key, value in
                    guard fields.contains(key) else { return (key, Kept.set(value)) }
                    guard let held = resolved?[key] else { return (key, Kept.unknown) }
                    return (key, Kept.set(held))
                })
            case .refused:
                return changes.mapValues { _ in .notMade }
            case .blocked, .dead:
                return nil
            }
        }
    }

    nonisolated static var earlierNotAnswered: String {
        String(localized: "An earlier change to this item hasn’t reached the server yet.")
    }

    nonisolated static var earlierNotMade: String {
        String(localized: "An earlier change to this item wasn’t made, so this change can’t be undone.")
    }

    nonisolated static var earlierUnknown: String {
        String(localized: "The server’s answer to an earlier change to this item couldn’t be read, so this change can’t be undone.")
    }

    nonisolated static func changedSince(undoing: Bool) -> String {
        undoing
            ? String(localized: "This item has changed since, so this change can’t be undone.")
            : String(localized: "This item has changed since, so this change can’t be redone.")
    }

    /// What the person has on screen for `key`: this Mac's newest edit of it while the copy has not taken it, otherwise
    /// the copy. An older edit the copy has not taken, such as a held Undo, is behind a newer one it has.
    func onScreen(_ id: ItemID, _ key: String) -> PropertyValue? {
        if let newest = newestEdits[id]?[key], !newest.taken, newest.kept == nil { return newest.changes[key] ?? nil }
        return item(id)?.value(of: key)
    }

    /// An edit about to be submitted, with what the person has on screen of each key and the edit each came from.
    func newEdit(of item: ItemID, _ changes: [String: PropertyValue?]) -> PropertyEdit {
        var before: [String: PropertyValue?] = [:]
        var builtOn: [String: PropertyEdit] = [:]
        for key in changes.keys {
            let shown = onScreen(item, key)
            before.updateValue(shown, forKey: key)
            if let newest = newestEdits[item]?[key], newest.changes[key] ?? nil == shown { builtOn[key] = newest }
        }
        return PropertyEdit(item: item, changes: changes, before: before, builtOn: builtOn)
    }

    func registerUndo(of edit: PropertyEdit, name: String, undoManager: UndoManager?) {
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.undo(edit, name: name, undoManager: undoManager)
        }
    }

    private func undo(_ edit: PropertyEdit, name: String, undoManager: UndoManager?) {
        guard let version = stepVersion(of: edit) else { return refuseStep(name, Self.changedSince(undoing: true), text: nil) }
        for (key, earlier) in edit.builtOn {
            switch earlier.standing(key) {
            case .kept: continue
            case .notKept: return refuseStep(name, Self.earlierNotMade, text: nil)
            case .unknown: return refuseStep(name, Self.earlierUnknown, text: nil)
            case .unanswered: return putBack(Self.earlierNotAnswered)
            }
        }
        guard let undone = submitPropertyEdit(edit.item, edit.before, base: version, failing: String(localized: "Can’t Edit This Property"))
        else {
            undoRun?.outcome.wasMade = false
            return
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.redo(edit.changes, over: undone, name: name, undoManager: undoManager)
        }
    }

    /// Writes the person's own values again, as a new edit whose Undo puts back what the item held when the Redo ran.
    private func redo(_ changes: [String: PropertyValue?], over undone: PropertyEdit, name: String, undoManager: UndoManager?) {
        guard let version = stepVersion(of: undone) else {
            return refuseStep(name, Self.changedSince(undoing: false), text: Self.typedText(changes))
        }
        guard let edit = submitPropertyEdit(undone.item, changes, base: version, failing: String(localized: "Can’t Edit This Property"))
        else {
            undoRun?.outcome.wasMade = false
            return
        }
        registerUndo(of: edit, name: name, undoManager: undoManager)
    }

    /// The version to write the step on, where the item still holds exactly what `edit` set, the server has not
    /// answered otherwise, and each key is still a field of the item's type that does not hold its text.
    private func stepVersion(of edit: PropertyEdit) -> ItemVersion? {
        guard let item = item(edit.item), item.isEditable, let type = catalogue.itemTypes[item.type] else { return nil }
        for (key, value) in edit.changes {
            guard key != MarfaMapping.bodyField(of: type), type.fields.contains(where: { $0.key == key }) || item.titleRule == .property(key),
                onScreen(edit.item, key) == value, [.kept, .unanswered].contains(edit.standing(key))
            else { return nil }
        }
        return item.version
    }

    /// The step is not made and cannot be, so it is not put back. A Redo's values are the only copy of what the person
    /// typed, so they are kept where the person can get them back.
    private func refuseStep(_ name: String, _ reason: String, text: String?) {
        undoRun?.outcome.wasMade = false
        if let text, !text.isEmpty {
            notices.notKept(name, text: text, reason: reason)
        } else {
            notices.tell(name, reason)
        }
    }

    /// The Undo can be made once an earlier edit is answered, so it goes back on the undo stack.
    private func putBack(_ reason: String) {
        guard let run = undoRun else { return }
        run.outcome.wasMade = false
        // The undo manager is still running the step, so anything registered now would go on the redo stack.
        Task { [weak self] in self?.giveBack(run, SyncProblem(code: "undo_earlier_unanswered", message: reason), title: nil, text: nil) }
    }
}
