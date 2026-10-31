import Foundation
import Marfa

/// Taking a drain's answers: telling each write its verdict, then forgetting the answers taken.
extension MarfaEngine {
    /// Tells each verdict to the app's write and shows it on its item while the queue still holds it, and only
    /// then forgets the answered writes. A refusal or conflict stays shown after that through `remembered`, and
    /// refused writes that carried content stay queued until discarded.
    func answer(_ report: DrainReport) async {
        #if DEBUG
        await hooks.answering.current?()
        #endif
        var ids: Set<String> = []
        // The copy lets an item go once its delete is answered, which may be only as the answers are forgotten.
        var leaving: Set<String> = []
        for answer in report.verdicts {
            if let itemID = answer.itemId, [.deleteItem, .restoreItem].contains(answer.kind) { leaving.insert(itemID) }
            guard let verdict = answer.verdict else { continue }
            if Self.canForget(verdict) { takenAnswers.insert(answer.id) }
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
        // An answer the person's text cannot yet be moved past stays in the queue, to be counted by the next save
        // or the next answer, since forgetting it would leave the text on a version it has passed.
        var uncounted = false
        if let queued = try? await copy.queue.all() {
            for raw in Set(queued.compactMap(\.itemId)) where ownText[ItemID(raw)] != nil {
                do {
                    try await count(answers: queued, for: ItemID(raw))
                } catch {
                    // An item the copy has let go, as when its delete was answered in this drain, has no version to
                    // count against and never will, so its text is forgotten rather than holding every answer back.
                    if await hasLeft(raw) {
                        ownText[ItemID(raw)] = nil
                        counted.formUnion(queued.filter { $0.itemId == raw }.map(\.id))
                    } else {
                        uncounted = true
                    }
                }
            }
        } else {
            uncounted = true
        }
        if !uncounted {
            do {
                let ids = Array(takenAnswers)
                #if DEBUG
                await hooks.forgetting.current?()
                #endif
                _ = try await Self.asking(hub) { try await copy.queue.forgetAnswered(ids: ids) }
            } catch {
                readFailed(error)
            }
        }
        if !leaving.isEmpty { await reread(leaving) }
        await readQueue()
        publish([])
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
