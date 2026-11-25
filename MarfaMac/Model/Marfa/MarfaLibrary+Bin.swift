import Foundation

extension MarfaLibrary {
    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        let plan = deletePlan(ids)
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in plan.moving { if let item = item(id) { changes[id] = (item.state, .trashed) } }
        let failing = String(localized: "Can’t Delete")
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: failing)
        let name = changes.count == 1 ? String(localized: "Delete Item") : String(localized: "Delete Items")
        gatheringSkips(failing: failing) { setStates(changes, name: name, undoManager: undoManager) }
    }

    /// The server reads what moving `ids` takes only for 2 to `DeletionWords.previewLimit` items and only online; asking
    /// it never moves anything.
    func moreItemsTaken(with ids: Set<ItemID>) async -> Int? {
        guard reachesServer, (2...DeletionWords.previewLimit).contains(ids.count) else { return nil }
        return await source.moreItemsTaken(with: ids.sorted { $0.rawValue < $1.rawValue })
    }

    /// The copy holds the bin, so an item binned here or elsewhere is restored like any other.
    func recover(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in ids { if item(id)?.state == .trashed { changes[id] = (.trashed, .active) } }
        gatheringSkips(failing: String(localized: "Can’t Recover")) {
            setStates(changes, name: String(localized: "Recover"), undoManager: undoManager)
        }
    }

    /// The engine sends each write only while the copy shows the item in the state it leaves (`MarfaEngine.judge`).
    /// The step registered in return reverses only the moves the server made or may still make.
    func setStates(_ changes: [ItemID: StateChange], name: String, undoManager: UndoManager?) {
        guard !changes.isEmpty else { return }
        let made = StateMoves()
        for (id, change) in changes { move(id, change, recordingIn: made, name: name) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            guard !made.moves.isEmpty else { return library.notices.tell(name, library.notMade) }
            library.gatheringSkips(failing: name) {
                library.setStates(made.moves.mapValues { (from: $0.to, to: $0.from) }, name: name, undoManager: undoManager)
            }
        }
    }

    /// The server takes an item out of the bin only to active (`items/transition`), so a move from the bin to the
    /// archive restores it, then archives it once the server has accepted the restore. Queued together, the archive
    /// would be sent after a refused restore (`queue-and-verdicts/answer-frees-follower`) and archive an item another
    /// device had restored meanwhile. Where the archive does not follow, the item ends active and the step registered
    /// in return records that move.
    private func move(_ id: ItemID, _ change: StateChange, recordingIn made: StateMoves, name: String) {
        guard item(id) != nil else { return skip(.gone) }
        let throughActive = change.from == .trashed && change.to == .archived
        let title = change.from == .trashed ? String(localized: "Can’t Recover") : String(localized: "Couldn’t Make This Change")
        let write = change.from == .trashed ? ItemWrite.restore(id) : .transition(id, change.to, from: change.from)
        let restore = submit(write, failing: title)
        guard isFollowed(restore) else { return }
        made.moves[id] = change
        if throughActive { awaitingArchive[restore] = id }
        let run = undoRun
        stateAnswers[restore] = { [weak self] answer in
            switch answer {
            case .notMade:
                made.moves[id] = nil
            case .mayBeMade:
                if throughActive { made.moves[id] = (from: change.from, to: .active) }
            case .made:
                guard let self, awaitingArchive.removeValue(forKey: restore) != nil else { return }
                // Held like the step's own writes while the copy catches up, but the restore was made, so an archive
                // the engine gives back or skips is told as not made rather than putting the step back.
                within(run) {
                    let archive = submit(.transition(id, .archived, from: .active), failing: String(localized: "Recovered but Not Archived"))
                    guard isFollowed(archive) else {
                        made.moves[id] = (from: change.from, to: .active)
                        return
                    }
                    leaveOutOfGiveBack(archive)
                    stateAnswers[archive] = { answer in
                        if answer == .notMade { made.moves[id] = (from: change.from, to: .active) }
                    }
                }
            }
        }
    }

    /// A blocked or dead write may still be made once released, or be withdrawn, so it is followed to its next answer.
    /// A restore answered so is made, if at all, without the archive waiting for it, so the person is told the item
    /// comes back active. A block of the whole queue answers every restore in it, so those are counted and told once
    /// no restore waits any longer.
    func stateWriteAnswered(_ write: WriteID, _ outcome: WriteOutcome) {
        let answer = StateAnswer(outcome)
        guard let follow = answer == .mayBeMade ? stateAnswers[write] : stateAnswers.removeValue(forKey: write) else { return }
        if answer != .made, awaitingArchive.removeValue(forKey: write) != nil, answer == .mayBeMade { archivesDropped += 1 }
        follow(answer)
        if archivesDropped > 0, awaitingArchive.isEmpty { tellArchivesDropped() }
    }

    /// The library is closing or changing, so no archive waits any longer for its restore's answer. Each such item
    /// comes back active if its restore is made, which the person is told with any restores already answered blocked
    /// or dead. Each restore is still followed, as a blocked one is, so the step registered records the move only if
    /// the restore is made. The library may stay open after all, as when a change of library is canceled; the archive
    /// is still not sent, so what the person was told stays true.
    func dropWaitingArchives() {
        guard !awaitingArchive.isEmpty else { return }
        let waiting = Array(awaitingArchive.keys)
        awaitingArchive = [:]
        for write in waiting { stateAnswers[write]?(.mayBeMade) }
        archivesDropped += waiting.count
        tellArchivesDropped()
    }

    private func tellArchivesDropped() {
        let count = archivesDropped
        archivesDropped = 0
        notices.tell(
            String(localized: "Couldn’t Finish Undo"),
            String(localized: "\(count) items will come back active, not archived, if they are recovered."))
    }

    /// Destroys items in the bin at the server, which only a server that can be reached does, so it is only where
    /// `reachesServer`. It is sent at the version the person was shown.
    func deletePermanently(_ ids: Set<ItemID>) {
        itemsToPurge.subtract(ids)
        guard reachesServer else {
            notices.tell(
                String(localized: "Can’t Delete Immediately"),
                String(localized: "The Marfa server can’t be reached. The items are still in Recently Deleted."))
            return
        }
        for id in ids {
            guard let item = item(id), item.state == .trashed else { continue }
            submit(.purge(id, version: item.version), failing: String(localized: "Can’t Delete Immediately"))
        }
    }
}

/// An item's state before and after a state change.
typealias StateChange = (from: ItemState, to: ItemState)

/// What the server's answer to a state change's write means for the move.
enum StateAnswer {
    /// Accepted or merged.
    case made
    /// Refused, conflicted or skipped (`MarfaEngine.judge`), so the item will not move.
    case notMade
    /// Blocked or dead, so it may still be made once released; or no longer followed, as the library closes.
    case mayBeMade

    init(_ outcome: WriteOutcome) {
        self = switch outcome {
        case .accepted, .merged: .made
        case .conflicted, .refused: .notMade
        case .blocked, .dead: .mayBeMade
        }
    }
}

/// The moves a state change made or may still make, kept as the server answers them, so the change registered in
/// return reverses only those.
final class StateMoves {
    var moves: [ItemID: StateChange] = [:]
}
