import Foundation

/// Each item moves through the working copy’s queue so these commands work offline.
extension MarfaLibrary {
    @discardableResult
    func setTier(_ ids: Set<ItemID>, to tier: Tier, undoManager: UndoManager?) -> CommandOutcome {
        let move: ItemMove = tier == .library ? .keep : .moveToFeed
        let plan = tierPlan(ids, to: tier)
        var changes: [ItemID: TierChange] = [:]
        for id in plan.changing { if let item = item(id) { changes[id] = (item.tier, tier) } }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: move.failing)
        setTiers(changes, name: move.name, undoManager: undoManager)
        return CommandOutcome(changes.keys, skips: plan.skips)
    }

    @discardableResult
    func archive(_ ids: Set<ItemID>, beneath: Bool, undoManager: UndoManager?) -> CommandOutcome {
        let plan = archivePlan(ids)
        let moving = beneath ? plan.archiving.union(plan.beneath) : plan.archiving
        var changes: [ItemID: StateChange] = [:]
        for id in moving { changes[id] = (.active, .archived) }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: ItemMove.archive.failing)
        setStates(changes, name: ItemMove.archive.name, undoManager: undoManager)
        return CommandOutcome(moving, skips: plan.skips)
    }

    @discardableResult
    func unarchive(_ ids: Set<ItemID>, undoManager: UndoManager?) -> CommandOutcome {
        let plan = unarchivePlan(ids)
        var changes: [ItemID: StateChange] = [:]
        for id in plan.changing { changes[id] = (.archived, .active) }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: ItemMove.unarchive.failing)
        setStates(changes, name: ItemMove.unarchive.name, undoManager: undoManager)
        return CommandOutcome(plan.changing, skips: plan.skips)
    }

    /// `tierLeft` includes writes the source has yet to show, so an undo can follow a pending move. An item already
    /// where an Undo or Redo would put it was put there elsewhere, so nothing is sent and the step registered in return
    /// leaves it alone too.
    func setTiers(_ changes: [ItemID: TierChange], name: String, undoManager: UndoManager?) {
        var changes = changes.filter { item($0.key) != nil }
        var changedSince = BatchSkips()
        var already = false
        if undoRun != nil {
            for (id, change) in changes {
                let left = tierLeft(id)
                guard left != change.from else { continue }
                changes[id] = nil
                if left == change.to { already = true } else { changedSince.skip(.changedSince) }
            }
            tellSkipped(changedSince, didChange: !changes.isEmpty, failing: name)
            if changes.isEmpty, !already, !changedSince.isEmpty { undoRun?.outcome.wasMade = false }
        }
        guard !changes.isEmpty || already || !changedSince.isEmpty else { return }
        let made = TierMoves()
        for (id, change) in changes {
            guard let item = item(id) else { continue }
            let write = submit(.retier(id, change.to, base: item.version), failing: name)
            guard isFollowed(write) else { continue }
            made.moves[id] = change
            tierMoving[id] = TierMoving(write: write, to: change.to)
            tierWrites[write] = TierWrite(item: id, notMade: { made.moves[id] = nil })
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            guard !made.moves.isEmpty else { return library.notices.tell(name, library.notMade) }
            library.setTiers(made.moves.mapValues { (from: $0.to, to: $0.from) }, name: name, undoManager: undoManager)
        }
    }

    /// The tier an item is in as this Mac left it: where a tier change on its way leaves it, or else what the copy shows.
    func tierLeft(_ id: ItemID) -> Tier? {
        tierMoving[id]?.to ?? item(id)?.tier
    }

    /// The copy shows the write, so the item stands where the copy says.
    func tierWriteTaken(_ write: WriteID) {
        guard let id = tierWrites[write]?.item, tierMoving[id]?.write == write else { return }
        tierMoving[id] = nil
    }

    /// A refused or conflicted tier write leaves the item where it was, so the step registered in return leaves it
    /// alone. A blocked or dead one may still be made once released.
    func tierWriteAnswered(_ write: WriteID, _ outcome: WriteOutcome) {
        guard let answered = tierWrites.removeValue(forKey: write) else { return }
        if tierMoving[answered.item]?.write == write { tierMoving[answered.item] = nil }
        if StateAnswer(outcome) == .notMade { answered.notMade() }
    }
}

/// An item's tier before and after a tier change.
typealias TierChange = (from: Tier, to: Tier)

/// A tier change of this Mac's on its way: the write sent and the tier it leaves the item in.
struct TierMoving {
    let write: WriteID
    let to: Tier
}

/// A tier write followed to its answer: the item it moves, and what follows if the server does not make it.
struct TierWrite {
    let item: ItemID
    let notMade: () -> Void
}

/// The tier moves a change made or may still make, kept as the server answers them, so the change registered in
/// return reverses only those.
final class TierMoves {
    var moves: [ItemID: TierChange] = [:]
}
