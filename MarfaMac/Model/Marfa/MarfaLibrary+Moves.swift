import Foundation

/// Each item moves through the working copy’s queue so these commands work offline. Whether each write is made is the
/// engine’s to judge as it queues it (`MarfaEngine.judge`); the library follows the answers.
extension MarfaLibrary {
    func setTier(_ ids: Set<ItemID>, to tier: Tier, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let move: ItemMove = tier == .library ? .keep : .moveToFeed
        let plan = tierPlan(ids, to: tier)
        var changes: [ItemID: TierChange] = [:]
        for id in plan.changing { if let item = item(id) { changes[id] = (item.tier, tier) } }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: move.failing)
        gatheringSkips(failing: move.failing, answered: Self.outcome(plan.skips, moved)) {
            setTiers(changes, name: move.name, undoManager: undoManager)
        }
    }

    func archive(_ ids: Set<ItemID>, beneath: Bool, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let plan = archivePlan(ids)
        let moving = beneath ? plan.archiving.union(plan.beneath) : plan.archiving
        var changes: [ItemID: StateChange] = [:]
        for id in moving { changes[id] = (.active, .archived) }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: ItemMove.archive.failing)
        gatheringSkips(failing: ItemMove.archive.failing, answered: Self.outcome(plan.skips, moved)) {
            setStates(changes, name: ItemMove.archive.name, undoManager: undoManager)
        }
    }

    func unarchive(_ ids: Set<ItemID>, undoManager: UndoManager?, moved: ((CommandOutcome) -> Void)?) {
        let plan = unarchivePlan(ids)
        var changes: [ItemID: StateChange] = [:]
        for id in plan.changing { changes[id] = (.archived, .active) }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: ItemMove.unarchive.failing)
        gatheringSkips(failing: ItemMove.unarchive.failing, answered: Self.outcome(plan.skips, moved)) {
            setStates(changes, name: ItemMove.unarchive.name, undoManager: undoManager)
        }
    }

    /// What the command moved once the engine has judged each write: only the items it queued, and every item the
    /// plan or the engine skipped.
    private static func outcome(_ planned: BatchSkips, _ moved: ((CommandOutcome) -> Void)?) -> ((SkipNotice) -> Void)? {
        guard let moved else { return nil }
        return { notice in
            var skips = planned
            skips.add(notice.skips)
            moved(CommandOutcome(notice.queued, skips: skips))
        }
    }

    /// Sends each change on the version the library holds; the engine sends it only while the copy shows the item in
    /// the tier it leaves (`MarfaEngine.judge`). The step registered in return reverses only the moves the server made
    /// or may still make.
    func setTiers(_ changes: [ItemID: TierChange], name: String, undoManager: UndoManager?) {
        guard !changes.isEmpty else { return }
        let made = TierMoves()
        for (id, change) in changes {
            guard let item = item(id) else {
                skip(.gone)
                continue
            }
            let write = submit(.retier(id, change.to, base: item.version), failing: name)
            guard isFollowed(write) else { continue }
            gathering?.items[write] = id
            made.moves[id] = TierMove(change: change, write: write)
            tierWrites[write] = { made.moves[id] = nil }
        }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            library.reverse(made, name: name, undoManager: undoManager)
        }
    }

    /// The server's answer says whether the tier move is safe to reverse (`tierWriteAnswered`), so the step waits
    /// for it (`waitForEarlier`).
    private func reverse(_ made: TierMoves, name: String, undoManager: UndoManager?) {
        guard !made.moves.isEmpty else { return notices.tell(name, notMade) }
        if made.moves.values.contains(where: { tierWrites[$0.write] != nil }) { return waitForEarlier(name: name) }
        gatheringSkips(failing: name) {
            setTiers(made.moves.mapValues { (from: $0.change.to, to: $0.change.from) }, name: name, undoManager: undoManager)
        }
    }

    /// A refused, conflicted or skipped tier write leaves the item where it was, so the step registered in return
    /// leaves it alone. So does one merged over a tier another device set since (`versions/auto-last-writer`): that
    /// device moved the item too, and an Undo here would reverse its move. A blocked or dead one may still be made once
    /// released, or be withdrawn, so it is followed to its next answer.
    func tierWriteAnswered(_ write: WriteID, _ outcome: WriteOutcome) {
        guard let notMade = tierWrites[write] else { return }
        let answer: StateAnswer = if case .merged(let fields) = outcome, fields.contains(MarfaMapping.tierField) {
            .notMade
        } else {
            StateAnswer(outcome)
        }
        guard answer != .mayBeMade else { return }
        tierWrites[write] = nil
        if answer == .notMade { notMade() }
    }
}

/// An item's tier before and after a tier change.
typealias TierChange = (from: Tier, to: Tier)

/// A tier move a change made or may still make, and the write that makes it.
struct TierMove {
    let change: TierChange
    let write: WriteID
}

/// The tier moves a change made or may still make, kept as the server answers them, so the change registered in
/// return reverses only those.
final class TierMoves {
    var moves: [ItemID: TierMove] = [:]
}
