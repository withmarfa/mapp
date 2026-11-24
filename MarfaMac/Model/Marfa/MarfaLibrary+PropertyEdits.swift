import Foundation

/// An Undo or Redo of a property edit is made only if, for every key it sets, the item as it stands holds exactly the
/// value the step before it left; otherwise none of it is written and the person is told, as for a state (`setStates`).
/// The item as it stands is the copy, with this Mac's edits it has not yet taken laid over it, which is what the person
/// has on screen; an Undo puts back what they had on screen when they made the edit. What a step left is what the copy
/// stores once it takes the edit, which may differ from what was sent (a trimmed address, a number as the nearest
/// double, a cleared key for a null).
///
/// Where that value came from an earlier edit of this Mac's that the server had not answered for certain, the Undo is
/// made only once that edit is known to have left it. One that did not, or whose answer can't be read, refuses the
/// Undo for good; one with no final answer yet refuses it for now and puts it back on the undo stack. Nothing waits.
extension MarfaLibrary {
    /// One property edit this Mac made, followed until its final answer.
    final class PropertyEdit {
        /// What the server's final answer left of one key.
        enum Kept: Equatable {
            /// The server's answer says the item holds this value after the edit.
            case set(PropertyValue?)
            /// The edit was refused or withdrawn.
            case notMade
            /// The server's answer does not say what the item holds.
            case unknown
        }

        /// What is known of whether the server kept what the edit left of one key.
        enum Standing {
            case kept, notKept, unknown, unanswered
        }

        let item: ItemID
        let changes: [String: PropertyValue?]
        /// What the person had on screen for each key when they made the edit.
        let before: [String: PropertyValue?]
        /// For each key, the edit of this Mac's that `before` came from, where the server had not answered it for certain.
        let builtOn: [String: PropertyEdit]
        /// What the edit left of each key: what was sent, until the copy takes it, then what the copy stores.
        private(set) var left: [String: PropertyValue?]
        /// Whether the copy has taken it, after which the copy shows it.
        private(set) var taken = false
        /// Nil until the final answer: a blocked or dead write is sent again once released.
        var kept: [String: Kept]?

        init(item: ItemID, changes: [String: PropertyValue?], before: [String: PropertyValue?], builtOn: [String: PropertyEdit]) {
            self.item = item
            self.changes = changes
            self.before = before
            self.builtOn = builtOn
            left = changes
        }

        /// The copy took the edit: `stored` is what it holds of each key now.
        func take(holding stored: (String) -> PropertyValue?) {
            taken = true
            for key in changes.keys { left.updateValue(stored(key), forKey: key) }
        }

        func standing(_ key: String) -> Standing {
            guard let kept else { return .unanswered }
            switch kept[key] {
            case .set(let value)? where MarfaLibrary.same(value, left[key] ?? nil): return .kept
            case .unknown?: return .unknown
            default: return .notKept
            }
        }

        /// What a final answer left of each key: the server's answer alone says what a merge, a conflict or an edit
        /// it moved onto a newer version left, so each key is read from the item it answers with.
        static func kept(_ keys: some Collection<String>, after outcome: WriteOutcome, holding: [String: PropertyValue]?) -> [String: Kept]? {
            switch outcome {
            case .accepted, .merged, .conflicted:
                return Dictionary(uniqueKeysWithValues: keys.map { key in (key, holding.map { Kept.set($0[key]) } ?? .unknown) })
            case .refused:
                return Dictionary(uniqueKeysWithValues: keys.map { ($0, Kept.notMade) })
            case .blocked, .dead:
                return nil
            }
        }
    }

    /// Whether two values are the same as the server stores them: strings by their bytes, since Swift's `==` takes
    /// composed and decomposed accents for one, and a null as no value, which is how the copy stores it.
    nonisolated static func same(_ one: PropertyValue?, _ other: PropertyValue?) -> Bool {
        switch (one, other) {
        case (nil, nil), (nil, .null?), (.null?, nil), (.null?, .null?):
            return true
        case (.string(let one)?, .string(let other)?):
            return one.utf8.elementsEqual(other.utf8)
        case (.array(let one)?, .array(let other)?):
            return one.count == other.count && zip(one, other).allSatisfy { same($0, $1) }
        case (.object(let one)?, .object(let other)?):
            let keys = Set(one.keys).union(other.keys)
            return keys.allSatisfy { same(one[$0], other[$0]) }
        case (let one?, let other?):
            return one == other
        default:
            return false
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

    nonisolated static func answerUnread(undoing: Bool) -> String {
        undoing
            ? String(localized: "The server’s answer to this change couldn’t be read, so it can’t be undone.")
            : String(localized: "The server’s answer to the undo couldn’t be read, so this change can’t be redone.")
    }

    /// What the person has on screen for `key`: this Mac's newest edit of it while the copy has not taken it, otherwise
    /// the copy. An older edit the copy has not taken, such as a held Undo, is behind a newer one it has.
    func onScreen(_ id: ItemID, _ key: String) -> PropertyValue? {
        if let newest = newestEdits[id]?[key], !newest.taken, newest.kept == nil { return newest.left[key] ?? nil }
        return item(id)?.value(of: key)
    }

    /// An edit about to be submitted, with what the person has on screen of each key and the edit each came from.
    func newEdit(of item: ItemID, _ changes: [String: PropertyValue?]) -> PropertyEdit {
        var before: [String: PropertyValue?] = [:]
        var builtOn: [String: PropertyEdit] = [:]
        for key in changes.keys {
            let shown = onScreen(item, key)
            before.updateValue(shown, forKey: key)
            if let newest = newestEdits[item]?[key], Self.same(newest.left[key] ?? nil, shown) { builtOn[key] = newest }
        }
        return PropertyEdit(item: item, changes: changes, before: before, builtOn: builtOn)
    }

    func registerUndo(of edit: PropertyEdit, name: String, undoManager: UndoManager?) {
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.undo(edit, name: name, undoManager: undoManager)
        }
    }

    /// Whether a step can be made now.
    private enum StepVerdict {
        case go(ItemVersion)
        /// Not made, and it cannot be, for the reason given.
        case refused(String)
        /// Not made until an earlier edit is answered.
        case later
    }

    private func undo(_ edit: PropertyEdit, name: String, undoManager: UndoManager?) {
        var verdict = stepVerdict(of: edit, undoing: true)
        // Every earlier edit is judged before any is acted on, so one with no answer yet never puts back a step that
        // another has already ruled out.
        if case .go = verdict {
            var waits = false
            for key in edit.builtOn.keys.sorted() {
                switch edit.builtOn[key]?.standing(key) {
                case .notKept?: verdict = .refused(Self.earlierNotMade)
                case .unknown?: verdict = .refused(Self.earlierUnknown)
                case .unanswered?: waits = true
                case .kept?, nil: continue
                }
                if case .refused = verdict { break }
            }
            if waits, case .go = verdict { verdict = .later }
        }
        switch verdict {
        case .refused(let reason):
            refuseStep(name, reason, text: nil)
        case .later:
            if let run = undoRun { putBack(run, reason: Self.earlierNotAnswered) }
        case .go(let version):
            guard let undone = submitPropertyEdit(edit.item, edit.before, base: version, failing: String(localized: "Can’t Edit This Property"))
            else {
                undoRun?.outcome.wasMade = false
                return
            }
            registerUndo(undoManager, name: name) { [weak undoManager] library in
                library.redo(edit.changes, over: undone, name: name, undoManager: undoManager)
            }
        }
    }

    /// Writes the person's own values again, as a new edit whose Undo puts back what the item held when the Redo ran.
    private func redo(_ changes: [String: PropertyValue?], over undone: PropertyEdit, name: String, undoManager: UndoManager?) {
        let verdict = stepVerdict(of: undone, undoing: false)
        if case .refused(let reason) = verdict { return refuseStep(name, reason, text: Self.valuesText(changes)) }
        guard case .go(let version) = verdict else { return }
        guard let edit = submitPropertyEdit(undone.item, changes, base: version, failing: String(localized: "Can’t Edit This Property"))
        else {
            undoRun?.outcome.wasMade = false
            return
        }
        registerUndo(of: edit, name: name, undoManager: undoManager)
    }

    /// The version to write the step on, where the item can be changed, still holds exactly what `edit` left, the
    /// server has not answered otherwise, and each key is still a field of the item's type that does not hold its text.
    private func stepVerdict(of edit: PropertyEdit, undoing: Bool) -> StepVerdict {
        guard let item = item(edit.item) else { return .refused(BatchSkips.sentence(.gone, count: 1)) }
        guard item.isEditable else {
            return .refused(item.problem?.message ?? item.writeObstacle.map { BatchSkips.sentence($0, count: 1) } ?? Self.cantChange)
        }
        guard let type = catalogue.itemTypes[item.type] else { return .refused(Self.changedSince(undoing: undoing)) }
        var unread = false
        for key in edit.changes.keys.sorted() {
            guard key != MarfaMapping.bodyField(of: type), type.fields.contains(where: { $0.key == key }) || item.titleRule == .property(key),
                Self.same(onScreen(edit.item, key), edit.left[key] ?? nil)
            else { return .refused(Self.changedSince(undoing: undoing)) }
            switch edit.standing(key) {
            case .kept, .unanswered: continue
            case .notKept: return .refused(Self.changedSince(undoing: undoing))
            case .unknown: unread = true
            }
        }
        return unread ? .refused(Self.answerUnread(undoing: undoing)) : .go(item.version)
    }

    /// Each value as the app shows it, so a Redo that can't be made gives back all the person set, numbers and
    /// entries as well as text.
    static func valuesText(_ changes: [String: PropertyValue?]) -> String? {
        let texts = changes.sorted { $0.key < $1.key }.compactMap { $0.value.map(ItemValueText.string) }.filter { !$0.isEmpty }
        return texts.isEmpty ? nil : texts.joined(separator: "\n\n")
    }

    /// The step is not made and cannot be, so it is not put back. A Redo's values are the only copy of what the person
    /// set, so they are kept where the person can get them back.
    private func refuseStep(_ name: String, _ reason: String, text: String?) {
        undoRun?.outcome.wasMade = false
        if let text, !text.isEmpty {
            notices.notKept(name, text: text, reason: reason)
        } else {
            notices.tell(name, reason)
        }
    }
}
