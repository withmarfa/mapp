import Foundation
import Marfa

/// What waits for the person: conflicted copies, refusals and the report, and discarding or releasing a write.
extension MarfaEngine {
    func conflictedCopies() -> [MarfaProblems.ConflictedCopy] {
        rows.values.filter { $0.state == .active && $0.tags.contains(MarfaProblems.conflictedCopyTag) }.map { row in
            MarfaProblems.ConflictedCopy(row: row, original: (linkedOriginals[row.id] ?? originals[row.id]).map { ItemID($0) })
        }
    }

    /// An item stops showing its conflict once the person has kept or binned the copy it names.
    func settleConflicts(_ copies: [MarfaProblems.ConflictedCopy]) {
        let open = Set(copies.map { ItemID($0.row.id) })
        var settled = false
        for (item, held) in remembered {
            guard case .conflicted(let sibling?, _) = held.state, rows[sibling.rawValue] != nil, !open.contains(sibling)
            else { continue }
            remembered[item] = nil
            originals[sibling.rawValue] = nil
            settled = true
        }
        if settled { restate() }
    }

    func publishReport(_ copies: [MarfaProblems.ConflictedCopy]) {
        guard queueRead else { return }
        let named = Set((queue + Array(refusals.values)).compactMap(\.itemId))
        let types = Dictionary(uniqueKeysWithValues: named.compactMap { id in rows[id].map { (id, TypeID($0.type)) } })
        let report = MarfaProblems.report(
            queue: queue, kept: Array(refusals.values), conflictedCopies: copies, catalogue: catalogue, types: types)
        hub.report.update { current in
            let phase = current.phase
            let fill = current.fill
            let lastSynced = current.lastSynced
            current = report
            current.phase = phase
            current.fill = fill
            current.lastSynced = lastSynced
        }
    }

    private func entry(_ id: String) -> SyncProblemEntry? {
        hub.report.value.problems.first { $0.id == .write(id) }
    }

    /// Those refused only for it go first, since the queue keeps a write another still depends on.
    func discard(_ id: String) async -> Result<Bool, SourceFailure> {
        guard let entry = entry(id), entry.actions.contains(.discard) else { return .success(false) }
        let held = Set(queue.map(\.id))
        do {
            for write in entry.dependents + [id] {
                if held.contains(write) {
                    guard try await Self.asking(hub, { try await copy.queue.discard(write) }) else { continue }
                }
                refusals[write] = nil
            }
        } catch {
            return .failure(Self.failure(error))
        }
        if let item = entry.itemID, !refusals.values.contains(where: { $0.itemId == item.rawValue }),
            case .refused = remembered[item]?.state
        {
            remembered[item] = nil
        }
        await readQueue()
        publish(entry.itemID.map { [$0] } ?? [])
        return .success(refusals[id] == nil)
    }

    func release(_ id: String) async -> Result<Bool, SourceFailure> {
        guard let entry = entry(id), entry.actions.contains(.tryAgain) else { return .success(false) }
        let released: Bool
        do {
            released = try await Self.asking(hub) { try await copy.queue.release(id) }
        } catch {
            return .failure(Self.failure(error))
        }
        await readQueue()
        publish(entry.itemID.map { [$0] } ?? [])
        if released { await sync.drain() }
        return .success(released)
    }
}
