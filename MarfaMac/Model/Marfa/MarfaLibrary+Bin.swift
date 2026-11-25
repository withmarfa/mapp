import Foundation

extension MarfaLibrary {
    func delete(_ ids: Set<ItemID>, undoManager: UndoManager?) {
        let plan = deletePlan(ids)
        var changes: [ItemID: (from: ItemState, to: ItemState)] = [:]
        for id in plan.moving { if let item = item(id) { changes[id] = (item.state, .trashed) } }
        tellSkipped(plan.skips, didChange: !changes.isEmpty, failing: String(localized: "Can’t Delete"))
        let name = changes.count == 1 ? String(localized: "Delete Item") : String(localized: "Delete Items")
        setStates(changes, name: name, undoManager: undoManager)
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
        setStates(changes, name: String(localized: "Recover"), undoManager: undoManager)
    }

    /// An Undo or Redo moves only an item still in the state this Mac left it in (`stateLeft`). A state moves no
    /// version, so the server would not catch a change another device made since; that item is left alone and the
    /// person told. An item already where the step would put it needs nothing sent, and the step counts as made for
    /// it. The step registered in return reverses only what the server took or may still take.
    func setStates(_ changes: [ItemID: StateChange], name: String, undoManager: UndoManager?) {
        var changes = changes.filter { item($0.key) != nil }
        var changedSince = BatchSkips()
        var already: [ItemID: StateChange] = [:]
        if undoRun != nil {
            for (id, change) in changes {
                let left = stateLeft(id)
                guard left != change.from else { continue }
                changes[id] = nil
                if left == change.to { already[id] = change } else { changedSince.skip(.changedSince) }
            }
            tellSkipped(changedSince, didChange: !changes.isEmpty, failing: name)
            if changes.isEmpty, already.isEmpty, !changedSince.isEmpty { undoRun?.outcome.wasMade = false }
        }
        guard !changes.isEmpty || !already.isEmpty || !changedSince.isEmpty else { return }
        let made = StateMoves()
        made.moves = already
        for (id, change) in changes { move(id, change, recordingIn: made, name: name) }
        registerUndo(undoManager, name: name) { [weak undoManager] library in
            guard !made.moves.isEmpty else { return library.notices.tell(name, library.notMade) }
            library.setStates(made.moves.mapValues { (from: $0.to, to: $0.from) }, name: name, undoManager: undoManager)
        }
    }

    /// The state an item is in as this Mac left it: where a state change on its way leaves it, or else what the copy shows.
    func stateLeft(_ id: ItemID) -> ItemState? {
        movingTo[id]?.to ?? item(id)?.state
    }

    /// The server takes an item out of the bin only to active (`items/transition`), so a move from the bin to the
    /// archive restores it, then archives it once the server has accepted the restore. Queued together, the archive
    /// would be sent after a refused restore (`queue-and-verdicts/answer-frees-follower`) and archive an item another
    /// device had restored meanwhile. Where the archive does not follow, the item ends active and the step registered
    /// in return records that move.
    private func move(_ id: ItemID, _ change: StateChange, recordingIn made: StateMoves, name: String) {
        made.moves[id] = change
        let throughActive = change.from == .trashed && change.to == .archived
        let title = change.from == .trashed ? String(localized: "Can’t Recover") : String(localized: "Couldn’t Make This Change")
        let run = undoRun
        sendState(id, throughActive ? .active : change.to, from: change.from, leaving: change.to, failing: title) { [weak self] restore, answer in
            switch answer {
            case .notMade:
                made.moves[id] = nil
                return
            case .mayBeMade:
                if throughActive { made.moves[id] = (from: change.from, to: .active) }
                return
            case .made:
                break
            }
            // A later state change of this item, made before the answer, is the one that stands.
            guard let self, throughActive, movingTo[id]?.write == restore else { return }
            guard item(id)?.state == .active else {
                movingTo[id] = nil
                made.moves[id] = (from: change.from, to: .active)
                return notices.tell(name, BatchSkips.sentence(.changedSince, count: 1))
            }
            movingTo[id] = nil
            // Held like the step's own writes while the copy catches up, but the restore was made, so an archive the
            // engine gives back is told as not made rather than putting the step back.
            within(run) {
                let archive = sendState(id, .archived, from: .active, leaving: .archived, failing: String(localized: "Recovered but Not Archived")) { _, answer in
                    if answer == .notMade { made.moves[id] = (from: change.from, to: .active) }
                }
                leaveOutOfGiveBack(archive)
            }
        }
    }

    /// `answered` is told what the server's answer means for the move, at once where the source would not take it.
    @discardableResult
    private func sendState(
        _ id: ItemID, _ state: ItemState, from: ItemState, leaving final: ItemState, failing title: String,
        answered: @escaping (WriteID, StateAnswer) -> Void
    ) -> WriteID {
        let write = submit(from == .trashed && state == .active ? .restore(id) : .transition(id, state), failing: title)
        guard isFollowed(write) else {
            answered(write, .notMade)
            return write
        }
        movingTo[id] = StateMoving(write: write, sent: state, to: final)
        stateAnswers[write] = answered
        return write
    }

    /// The copy shows the write, so the item stands where the copy says, unless a second write is still to follow.
    func stateWriteTaken(_ write: WriteID) {
        guard let (id, moving) = movingTo.first(where: { $0.value.write == write }), !moving.awaitsArchive else { return }
        movingTo[id] = nil
    }

    /// A restore that is blocked or dead may still be made once released, but the archive waiting for it is not sent
    /// after it, so the person is told the item comes back active. A block of the whole queue answers every restore
    /// in it, so those are counted and told once no restore waits any longer.
    func stateWriteAnswered(_ write: WriteID, _ outcome: WriteOutcome) {
        let answer = StateAnswer(outcome)
        let moving = movingTo.first(where: { $0.value.write == write })
        if let (id, moving) = moving, answer != .made || !moving.awaitsArchive {
            movingTo[id] = nil
        }
        stateAnswers.removeValue(forKey: write)?(write, answer)
        if answer == .mayBeMade, moving?.value.awaitsArchive == true { archivesDropped += 1 }
        if archivesDropped > 0, !movingTo.values.contains(where: \.awaitsArchive) { tellArchivesDropped() }
    }

    /// The library is closing or changing, so no archive waits any longer for its restore's answer. Each such item
    /// comes back active if its restore is made, which the person is told with any restores already answered blocked
    /// or dead, and the steps registered record that move.
    /// The library may stay open after all, as when a change of library is canceled; the archive is still not sent,
    /// so what the person was told stays true.
    func dropWaitingArchives() {
        let waiting = movingTo.filter(\.value.awaitsArchive)
        guard !waiting.isEmpty else { return }
        for (id, moving) in waiting {
            movingTo[id] = StateMoving(write: moving.write, sent: moving.sent, to: moving.sent)
            stateAnswers.removeValue(forKey: moving.write)?(moving.write, .mayBeMade)
        }
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

/// A state change of this Mac's on its way: the write sent, the state it sends and the state the change leaves the
/// item in, which differ while a second write is still to follow.
struct StateMoving {
    let write: WriteID
    let sent: ItemState
    let to: ItemState

    /// A restore with an archive waiting for its answer.
    var awaitsArchive: Bool { sent != to }
}

/// What the server's answer to a state change's write means for the move.
enum StateAnswer {
    /// Accepted or merged.
    case made
    /// Refused or conflicted, so the item will not move.
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
