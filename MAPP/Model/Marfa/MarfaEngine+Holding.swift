import Foundation
import Marfa
import struct MarfaCore.Item
import struct MarfaCore.Edge

/// What the engine holds of the rows and edges a write touches, apart from the numbers that move on their own (a
/// version, a modified date), so two readings differ only where something the person could see changed.
nonisolated struct Stand: Equatable {
    enum Face: Equatable {
        /// An item whose content the write replaces.
        case item(Marfa.Item)
        /// An item that is only named, such as an end of a link or the item a state is set on.
        case place(type: String, state: String)
        case edge(Marfa.Edge)
        /// The edges of one type between two items, whichever way they run.
        case links([String])
    }

    var faces: [String: Face] = [:]
}

/// A write of an undo or a redo that the copy refused while it was brought up to date.
nonisolated struct Held {
    var write: ItemWrite
    var id: WriteID
    var group: UndoGroup
    /// How the write found what it touches, when the person made it.
    var stand: Stand
}

/// An undo or a redo pressed while the copy is brought up to date is not lost. The package refuses a write to an
/// edge, or to a row it does not hold yet, until the copy is whole, and the undo manager has already taken the step
/// off its stack, so the engine keeps the write and makes it once the copy has been read whole again: exactly once,
/// and only if what it touches is as it was when the person pressed Undo. Otherwise it is given back as refused
/// (`heldChangedCode`, `heldTimeoutCode`) and the library tells the person and keeps the step on the undo stack.
extension MarfaEngine {
    nonisolated static func isBeingBroughtUpToDate(_ error: MarfaError) -> Bool {
        switch error {
        case .hydrationIncomplete, .copyExpired: true
        default: false
        }
    }

    func hold(_ write: ItemWrite, as id: WriteID, in group: UndoGroup, standing: Stand?) async {
        let first = standing == nil && !held.contains { $0.group == group }
        held.append(Held(write: write, id: id, group: group, stand: standing ?? stand(for: write)))
        guard standing == nil else { return }
        if first { arm(group) }
        await sync.refresh()
        // A copy that was made whole while the refresh ran says nothing more, so it is read once here.
        if held.contains(where: { $0.group == group }) { await reload() }
    }

    private func arm(_ group: UndoGroup) {
        Task { [tell, holdLimit] in
            try? await Task.sleep(for: holdLimit)
            _ = tell(.holdExpired(group))
        }
    }

    /// A catch-up that is still under way is waited for. One that is not, as when the server cannot be reached, is
    /// given up, so a held undo never waits without end.
    func expire(_ group: UndoGroup) {
        guard held.contains(where: { $0.group == group }) else { return }
        if hub.report.value.phase == .catchingUp { return arm(group) }
        refuse(group, code: Self.heldTimeoutCode, message: Self.heldTimedOut)
    }

    private func refuse(_ group: UndoGroup, code: String, message: String) {
        for entry in held where entry.group == group {
            hub.publish(.answered(entry.id, .refused(SyncProblem(code: code, message: message, notQueued: true))))
        }
        held.removeAll { $0.group == group }
    }

    /// Called once a read found the copy whole. Every held write is judged against what was just read before any is
    /// made, so one that follows another (an undo and its redo) is judged as the person saw it, not as the one before
    /// it leaves things. A group with any write whose items changed is given back whole.
    func releaseHeld() async {
        guard !held.isEmpty else { return }
        let waiting = held
        held = []
        let changed = Set(waiting.filter { stand(for: $0.write) != $0.stand }.map(\.group))
        var stopped = false
        var behind: [Held] = []
        for entry in waiting {
            if changed.contains(entry.group) {
                hub.publish(.answered(
                    entry.id, .refused(SyncProblem(code: Self.heldChangedCode, message: Self.heldChanged, notQueued: true))))
            } else if stopped {
                // The copy refused an earlier write again, so the order is kept by trying none of the later ones.
                behind.append(entry)
            } else if await perform(rebased(entry.write), as: entry.id, holding: entry.group, standing: entry.stand) {
                stopped = true
            }
        }
        held += behind
    }

    /// The write on the version the engine holds now, since an item with the content the person saw may be on a later
    /// version after the catch-up, or after a write held before this one was made.
    private func rebased(_ write: ItemWrite) -> ItemWrite {
        func current(_ id: ItemID, or base: ItemVersion) -> ItemVersion { rows[id.rawValue].map { ItemVersion($0.version) } ?? base }
        switch write {
        case .editProperties(let id, let changes, let base, let undoing):
            return .editProperties(id, changes, base: current(id, or: base), undoing: undoing)
        case .editBody(let id, let text, let base, let merge):
            return .editBody(id, text, base: current(id, or: base), merge: merge)
        case .retype(let id, let type, let changes, let base):
            return .retype(id, type, changes, base: current(id, or: base))
        case .retier(let id, let tier, let base):
            return .retier(id, tier, base: current(id, or: base))
        default:
            return write
        }
    }

    func stand(for write: ItemWrite) -> Stand {
        var stand = Stand()
        func item(_ id: ItemID) {
            guard var row = rows[id.rawValue] else { return }
            row.version = 0
            row.updatedAt = ""
            stand.faces["item \(id.rawValue)"] = .item(row)
        }
        func place(_ id: String) {
            guard let row = rows[id] else { return }
            stand.faces["place \(id)"] = .place(type: row.type, state: String(describing: row.state))
        }
        func edge(_ id: String) {
            guard var edge = edges[id] else { return }
            place(edge.sourceId)
            place(edge.targetId)
            edge.version = 0
            edge.updatedAt = ""
            stand.faces["edge \(id)"] = .edge(edge)
        }
        switch write {
        case .editProperties(let id, _, _, _), .retype(let id, _, _, _), .retier(let id, _, _), .editBody(let id, _, _, _):
            item(id)
        case .transition(let id, _), .tag(let id, _, _):
            place(id.rawValue)
        case .link(let draft, _):
            place(draft.source.rawValue)
            place(draft.target.rawValue)
            let ends: Set<String> = [draft.source.rawValue, draft.target.rawValue]
            let between = edges.edges(touching: draft.source.rawValue)
                .filter { $0.edgeType == draft.type && Set([$0.sourceId, $0.targetId]) == ends }
            stand.faces["links \(draft.type) \(draft.source.rawValue) \(draft.target.rawValue)"] = .links(between.map(\.id).sorted())
        case .unlink(let id):
            edge(id.rawValue)
        case .moveEdge(let id, _, let to):
            edge(id.rawValue)
            place(to.rawValue)
        case .create, .purge:
            break
        }
        return stand
    }
}
