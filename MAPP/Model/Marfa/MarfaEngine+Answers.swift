import Foundation
import Marfa

/// Taking the answers the copy holds: telling each write its verdict, and the copy forgetting those taken.
extension MarfaEngine {
    /// The queue as the engine counts the person's text against: what the copy holds, and the answers taken from
    /// it that an item's text has not yet been counted past (`answeredHeld`).
    func queueWithAnswers() async throws -> [Marfa.QueuedWrite] {
        let queued = try await copy.queue.all()
        let ids = Set(queued.map(\.id))
        return queued + answeredHeld.values.filter { !ids.contains($0.id) }.sorted { $0.id < $1.id }
    }

    /// Takes the answers the copy recorded, from a drain of ours or one the copy ran itself, in the engine's own
    /// step. The copy clears and returns the answered writes (`Queue.takeAnswered`); a refused write that carried
    /// content, a blocked one and a dead one stay in the queue with their verdict, so each is told here once. An
    /// expired copy refuses the take, and a later update takes them once it is hydrated again.
    func takeAnswers() async {
        let taken: [Marfa.QueuedWrite]
        do {
            taken = try await Self.asking { try await copy.queue.takeAnswered() }
        } catch {
            return
        }
        var answers = taken
        if let queued = try? await copy.queue.all() {
            answers += queued.filter { $0.verdict != nil && !told.contains($0.id) }
            // A released write has no verdict, so a later refusal of it is told again.
            told = Set(queued.filter { $0.verdict != nil }.map(\.id))
        }
        guard !answers.isEmpty else { return }
        await answer(answers)
    }

    /// Tells each verdict to the app's write and shows it on its item. A refusal or conflict stays shown after
    /// that through `remembered`, and refused writes that carried content stay queued until discarded.
    func answer(_ writes: [Marfa.QueuedWrite]) async {
        #if DEBUG
        await hooks.answering.current?()
        #endif
        var ids: Set<String> = []
        // The copy lets an item go once its delete is answered.
        var leaving: Set<String> = []
        for answer in writes {
            if let itemID = answer.itemId, [.deleteItem, .restoreItem].contains(answer.kind) { leaving.insert(itemID) }
            guard let verdict = answer.verdict else { continue }
            if [.createItem, .updateItem].contains(answer.kind), answer.itemId != nil { answeredHeld[answer.id] = answer }
            let outcome = MarfaMapping.outcome(verdict)
            ids.formUnion(movedEnds.removeValue(forKey: answer.id) ?? [])
            if let itemID = answer.itemId {
                ids.insert(itemID)
                remember(outcome, of: answer.kind, for: ItemID(itemID))
                if answer.kind == .restoreItem, let row = restoring.removeValue(forKey: itemID) {
                    // Taken, the item arrives in the copy; otherwise it is still in the bin.
                    switch outcome {
                    case .accepted, .merged: break
                    default: binned[itemID] = row
                    }
                }
            }
            if case .conflicted(let sibling, _) = outcome {
                ids.insert(sibling.rawValue)
                if let itemID = answer.itemId { originals[sibling.rawValue] = itemID }
            }
            answered(answer.id, outcome)
        }
        await reread(ids.union(await settledLinks()))
        // An answer the person's text cannot yet be moved past is held, to be counted by the next save or the next
        // answer, since dropping it would leave the text on a version it has passed.
        if let queued = try? await queueWithAnswers() {
            for raw in Set(queued.compactMap(\.itemId)) where ownText[ItemID(raw)] != nil {
                do {
                    try await count(answers: queued, for: ItemID(raw))
                } catch {
                    // An item the copy has let go, as when its delete was answered in this drain, has no version to
                    // count against and never will, so its text is forgotten rather than holding every answer back.
                    if await hasLeft(raw) {
                        ownText[ItemID(raw)] = nil
                        counted.formUnion(queued.filter { $0.itemId == raw }.map(\.id))
                    }
                }
            }
        }
        pruneAnswers()
        if !leaving.isEmpty { await reread(leaving) }
        await readQueue()
        publish([])
    }

    /// Lets go of an answer once its item's text has been counted past it, or the item has no text of the person's
    /// to count.
    private func pruneAnswers() {
        for (id, write) in answeredHeld where counted.contains(id) || write.itemId.map({ ownText[ItemID($0)] == nil }) ?? true {
            answeredHeld[id] = nil
        }
    }

    func remember(_ outcome: WriteOutcome, of kind: WriteKind, for item: ItemID) {
        switch outcome {
        case .refused, .conflicted:
            remembered[item] = (outcome.syncState, kind)
        case .accepted, .merged:
            if let held = remembered[item], held.kind == kind || kind == .updateItem { remembered[item] = nil }
            let queued = Set(queue.map(\.id))
            refusals = refusals.filter { id, write in
                queued.contains(id) || write.itemId != item.rawValue || (write.kind != kind && kind != .updateItem)
            }
        case .blocked, .dead:
            // The queue keeps these until they are released or withdrawn.
            break
        }
    }

    /// A write the app made as several queued writes is answered once, when the last of them is (`MarfaWriteRecord`).
    func answered(_ queued: String, _ outcome: WriteOutcome) {
        guard let (id, outcome) = writes.answer(queued, outcome) else { return }
        hub.publish(.answered(id, outcome))
    }

    private func hasLeft(_ raw: String) async -> Bool {
        guard rows[raw] == nil else { return false }
        return (try? await copy.items.get(raw)) == nil
    }
}
