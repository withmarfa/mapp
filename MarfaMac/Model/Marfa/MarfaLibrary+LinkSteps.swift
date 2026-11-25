import Foundation

/// What one change of links wrote, kept as the copy takes each write, so its undo reverses only that: it removes only
/// the edges it added, puts back only the ones it removed, and moves back only the ends it moved.
final class LinkStep {
    /// What one write of the step does.
    enum Piece {
        /// A new edge, under the id the library minted.
        case added(EdgeDraft)
        /// An edge removed, with its ends and position.
        case removed(EdgeDraft)
        case moved(MarfaLibrary.RelationshipChange.Move)
    }

    /// Each write the step sent, in the order sent.
    var pieces: [(write: WriteID, piece: Piece)] = []
    /// The writes the engine has not yet judged.
    var judging: Set<WriteID> = []
    /// The writes the copy took and the server has not refused.
    var made: Set<WriteID> = []
    /// The removals held back until the new links are answered (`MarfaLibrary.awaitLinks`).
    var heldBack: UUID?
    /// The writes sent at once that the source took (`MarfaLibrary.relink`).
    var sent: Set<WriteID> = []
    /// The writes answered before the copy took them, as one the engine skipped, with why.
    var refusals: [WriteID: SyncProblem] = [:]

    /// What the writes sent at once came to, once each is taken or answered: `incomplete` where the copy refused one
    /// for not being whole, `refused` where it refused or skipped one, or the source closed before it took or answered
    /// one, and `taken` where it took them all.
    var verdict: EdgeVerdict {
        let refused = sent.compactMap { refusals[$0] }
        if refused.contains(where: { MarfaEngine.isNotCurrent($0.code) }) { return .incomplete }
        if let problem = refused.first {
            return .refused(problem.message ?? String(localized: "The Marfa server refused this change."))
        }
        if !sent.isDisjoint(with: judging) { return .refused(MarfaEngine.closedLibrary) }
        return .taken
    }
}

extension MarfaLibrary {
    /// The step records `write` once the engine has judged and queued it (`linkWriteTaken`).
    func follow(_ write: WriteID, _ piece: LinkStep.Piece, in step: LinkStep) {
        guard isFollowed(write) else { return }
        step.pieces.append((write, piece))
        step.judging.insert(write)
        linkSteps[write] = step
    }

    func linkWriteTaken(_ write: WriteID) {
        guard let step = linkSteps[write], step.judging.remove(write) != nil else { return }
        step.made.insert(write)
    }

    /// A write answered before the copy took it queued nothing, as one the engine skipped. One the copy took and the
    /// server refused is not made, so the undo leaves it. A blocked or dead one may still be made, so it is followed.
    func linkWriteAnswered(_ write: WriteID, _ outcome: WriteOutcome) {
        guard let step = linkSteps[write] else { return }
        if step.judging.remove(write) != nil {
            if case .refused(let problem) = outcome { step.refusals[write] = problem }
            linkSteps[write] = nil
            return
        }
        switch StateAnswer(outcome) {
        case .made: linkSteps[write] = nil
        case .notMade:
            step.made.remove(write)
            linkSteps[write] = nil
        case .mayBeMade: break
        }
    }

    /// An inverse sent before the engine judged the step's own writes could undo a link the engine then skipped, so
    /// the step waits: an Undo goes back on its stack and a Redo tells the person why it did not run. Removals still
    /// held back for the new links are dropped, since undoing the new links leaves the old ones in place.
    func reverse(_ step: LinkStep, name: String, failing title: String, undoManager: UndoManager?) {
        guard step.judging.isEmpty else { return waitForEarlier(name: name) }
        if let group = step.heldBack { dropReplacement(group) }
        var inverse = RelationshipChange()
        for (write, piece) in step.pieces where step.made.contains(write) {
            switch piece {
            case .added(let draft): inverse.removing.append(draft)
            case .removed(let draft): inverse.adding.append(draft)
            case .moved(let move): inverse.moving.append(move.reversed)
            }
        }
        guard !inverse.isEmpty else { return notices.tell(name, notMade) }
        gatheringSkips(failing: title) {
            relink(inverse, name: name, failing: title, undoManager: undoManager)
        }
    }
}
