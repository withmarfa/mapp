import Foundation

/// An Undo of a property edit puts back what the server's answers say the item held before the edit, never what the
/// copy showed: the copy shows an edit as soon as it takes it, and the server may still refuse it, or keep its own
/// value. Each edit keeps what it was built on (`PropertyEdit`), and an Undo built on an edit with no final answer
/// waits for it, for as long as a held undo waits for the copy (`MarfaEngine.standardHoldLimit`). An Undo that cannot
/// wait, because the answer does not come in time or the person changes what it sets meanwhile, goes back on the undo
/// stack. Steps of one item are made in the order they were pressed. Before either direction is made, the item is
/// checked again: a key that became the item's text, or that its type no longer has, is never written.
extension MarfaLibrary {
    /// One property edit this Mac made, from when it is submitted until the server's final answer.
    final class PropertyEdit {
        /// What the server's final answer left of one key.
        enum Kept: Equatable {
            /// The item holds this value after the edit.
            case set(PropertyValue?)
            /// The edit was refused, so the key holds what it held before it.
            case notMade
            /// The server named the key in a merge or conflict, and its answer could not be read.
            case unknown
        }

        /// What one key held before the edit, as far as the server's answers say.
        enum Before: Equatable {
            case value(PropertyValue?)
            /// An earlier edit that set the key has no final answer yet.
            case waiting
            case unknown
        }

        let item: ItemID
        /// Its place among this Mac's property edits, in the order they were submitted.
        let mark: Int
        let changes: [String: PropertyValue?]
        /// The copy's value of each key when the edit was submitted.
        let shown: [String: PropertyValue?]
        /// For each key, the newest of this Mac's edits of the item that set it and whose final answer the copy had
        /// not yet read when this one was submitted, which `shown` therefore cannot be trusted for.
        let earlier: [String: PropertyEdit]
        /// Nil until the final answer: a blocked or dead write is sent again once released.
        var kept: [String: Kept]?

        init(item: ItemID, mark: Int, changes: [String: PropertyValue?], shown: [String: PropertyValue?], earlier: [String: PropertyEdit]) {
            self.item = item
            self.mark = mark
            self.changes = changes
            self.shown = shown
            self.earlier = earlier
        }

        /// Walks back past edits that were not made to the value the server last held.
        func before(_ key: String) -> Before {
            guard let edit = earlier[key] else { return .value(shown[key] ?? nil) }
            guard let kept = edit.kept else { return .waiting }
            switch kept[key] ?? .unknown {
            case .set(let value): return .value(value)
            case .notMade: return edit.before(key)
            case .unknown: return .unknown
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

    /// The edit a step made, filled in once a Redo waiting behind an earlier step is made.
    final class MadeEdit {
        var edit: PropertyEdit?

        init(_ edit: PropertyEdit? = nil) {
            self.edit = edit
        }
    }

    enum ReplayAttempt {
        case made
        case waiting
        /// Not made, for the reason given, and not given back, since the item no longer allows it.
        case refused(String)
        /// Given back, since what the edit was built on cannot be known.
        case unknown
    }

    /// One Undo or Redo of a property edit, waiting behind an earlier answer or an earlier step of the item.
    final class PropertyReplay {
        let keys: Set<String>
        let run: UndoRun
        /// A Redo's values, which the person typed and gets back if it is not made.
        let text: String?
        let attempt: (MarfaLibrary) -> ReplayAttempt

        init(keys: Set<String>, run: UndoRun, text: String?, attempt: @escaping (MarfaLibrary) -> ReplayAttempt) {
            self.keys = keys
            self.run = run
            self.text = text
            self.attempt = attempt
        }
    }

    nonisolated static var earlierNotAnswered: String {
        String(localized: "An earlier change to this item hasn’t reached the server yet.")
    }

    nonisolated static var earlierUnknown: String {
        String(localized: "The server’s answer to an earlier change to this item couldn’t be read.")
    }

    struct ReplayRefused: Error {
        let reason: String
    }

    /// The version a step writes `keys` on, or why the item no longer allows it.
    func replayBase(_ id: ItemID, _ keys: Set<String>, undoing: Bool) -> Result<ItemVersion, ReplayRefused> {
        if let item = item(id), item.isEditable, let type = catalogue.itemTypes[item.type],
            keys.allSatisfy({ key in
                key != MarfaMapping.bodyField(of: type) && (type.fields.contains { $0.key == key } || item.titleRule == .property(key))
            }) {
            return .success(item.version)
        }
        return .failure(ReplayRefused(reason: undoing
            ? String(localized: "This item has changed since, so this change can’t be undone.")
            : String(localized: "This item has changed since, so this change can’t be redone.")))
    }

    /// Made now where nothing of the item waits; otherwise queued behind what does.
    func replay(_ item: ItemID, keys: Set<String>, text: String?, _ attempt: @escaping (MarfaLibrary) -> ReplayAttempt) {
        guard let run = undoRun else { return }
        let step = PropertyReplay(keys: keys, run: run, text: text, attempt: attempt)
        if replays[item]?.isEmpty == false {
            replays[item]?.append(step)
            return
        }
        switch attempt(self) {
        case .made:
            return
        case .refused(let reason):
            return refuse(step, reason)
        case .waiting:
            replays[item] = [step]
            armReplays(of: item)
        case .unknown:
            // The undo manager is still running the step, so anything registered now would go on the wrong stack.
            replays[item] = [step]
            Task { [weak self] in self?.continueReplays(of: item) }
        }
    }

    /// Makes the waiting steps of the item that can be made now, in order.
    func continueReplays(of item: ItemID) {
        while let step = replays[item]?.first {
            var result = ReplayAttempt.waiting
            within(step.run) { result = step.attempt(self) }
            switch result {
            case .made:
                replays[item]?.removeFirst()
            case .refused(let reason):
                replays[item]?.removeFirst()
                refuse(step, reason)
            case .waiting:
                return armReplays(of: item)
            case .unknown:
                return giveBackReplays(of: item, reason: Self.earlierUnknown)
            }
        }
        replays[item] = nil
        replayDeadlines.removeValue(forKey: item)?.cancel()
    }

    /// The person changed what a waiting step sets, so making it later would write over that change.
    func giveBackReplays(of item: ItemID, touching keys: Set<String>) {
        guard replays[item]?.contains(where: { !$0.keys.isDisjoint(with: keys) }) == true else { return }
        giveBackReplays(of: item, reason: Self.earlierNotAnswered)
    }

    /// Every step behind the first was built on it, so all go back, the last pressed first, which keeps their order
    /// on the undo stack.
    private func giveBackReplays(of item: ItemID, reason: String) {
        guard let steps = replays.removeValue(forKey: item) else { return }
        replayDeadlines.removeValue(forKey: item)?.cancel()
        for step in steps.reversed() {
            giveBack(step.run, SyncProblem(code: "undo_waiting", message: reason), title: nil, text: step.text)
        }
    }

    private func refuse(_ step: PropertyReplay, _ reason: String) {
        step.run.outcome.wasMade = false
        notices.tell(step.run.step.name, reason)
    }

    private func armReplays(of item: ItemID) {
        guard replayDeadlines[item] == nil else { return }
        replayDeadlines[item] = Task { [weak self, answerWait] in
            try? await Task.sleep(for: answerWait)
            guard !Task.isCancelled else { return }
            self?.giveBackReplays(of: item, reason: Self.earlierNotAnswered)
        }
    }
}
