import Foundation
import Marfa

/// Mapping rows into items, and telling readers what changed since they were last told.
extension MarfaEngine {
    /// Maps `ids` again and tells readers what differs, in one change: the first time, everything as `.loaded`.
    /// An item's text goes with it where the item is new, its version moved or its text changed, so a page never
    /// shows a version with older text. Failures gathered on the way follow as `.unavailable`.
    func publish(_ ids: some Sequence<ItemID>, catalogueChanged: Bool = false) async {
        let own = Set(ids).union(changedSync)
        let ids = own.union(unnamed)
        changedSync = []
        // Asked before anything is read for the change, so the engine's state stands still from here to the end.
        var displays = await displays(of: own, thenEarlier: unnamed)
        let copies = conflictedCopies()
        settleConflicts(copies)
        if catalogueChanged, painted, hub.catalogue != catalogue { hub.publish(.catalogue(catalogue)) }
        var changes = ItemChanges()
        var present: [(id: ItemID, row: Marfa.Item)] = []
        let told = hub.told(ids)
        // An item the core could not be asked about keeps the name and preview it was last told, and is asked again
        // with the next change.
        for id in unnamed {
            guard let previous = told[id]?.item else { continue }
            displays[id.rawValue] = ItemDisplay(name: previous.name, preview: previous.preview.isEmpty ? nil : previous.preview)
        }
        for id in ids {
            guard let row = rows[id.rawValue] else {
                if told[id] != nil { changes.removed.append(id) }
                continue
            }
            present.append((id, row))
        }
        let mapped = Self.mapped(present, reading: Mapping(
            rows: rows, edges: edges, catalogue: catalogue, syncStates: syncStates, bodyLinks: bodyLinks,
            displays: displays))
        for (item, text) in mapped {
            let previous = told[item.id]
            if let text, previous?.item.version != item.version || previous?.text != text {
                changes.bodies.append(ItemBody(id: item.id, text: text, version: item.version))
            }
            if previous?.item != item { changes.upserted.append(item) }
        }
        if !painted {
            painted = true
            // Nothing was told before, so every item mapped here is new.
            hub.publish(.loaded(SourceSnapshot(
                items: changes.upserted.sorted(by: MarfaHub.newestFirst), catalogue: catalogue, views: views,
                bodies: Dictionary(changes.bodies.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }))))
        } else if !changes.isEmpty {
            hub.publish(.changed(changes))
        }
        for failure in failures { hub.publish(.unavailable(failure)) }
        failures = []
        publishReport(copies)
    }

    /// What mapping a row reads of the engine, copied out so several threads can map rows at once.
    nonisolated struct Mapping: Sendable {
        let rows: [String: Marfa.Item]
        let edges: MarfaEdgeTable
        let catalogue: Catalogue
        let syncStates: [ItemID: SyncState]
        let bodyLinks: [String: BodyLinks]
        /// What the core names each row and shows of it, by row id.
        let displays: [String: ItemDisplay]
    }

    /// The most rows asked about in one `items.displays` call. The core serves one call at a time, so a whole large
    /// library in one call holds every other read and write of the copy until it ends (about 16 microseconds a row
    /// for 3 KB notes); in batches they interleave.
    nonisolated static let displayBatch = 2_000

    /// The name and preview the core gives each of `own` the engine holds, from the copy's catalog in batches, and
    /// then each of `earlier`, the items it could not be asked about before, but only once `own` was answered, so a
    /// lookup that keeps failing is not asked about the whole library again with every change. A row whose batch
    /// fails is left out and kept in `unnamed`. The failure is told when a lookup first fails, and again only after
    /// one has succeeded.
    private func displays(of own: Set<ItemID>, thenEarlier earlier: Set<ItemID>) async -> [String: ItemDisplay] {
        unnamed = []
        var answers: [String: ItemDisplay] = [:]
        let heldOwn = own.compactMap { rows[$0.rawValue] }
        var failed = await ask(heldOwn, into: &answers)
        if failed {
            unnamed.formUnion(earlier)
        } else if !heldOwn.isEmpty {
            let heldEarlier = earlier.subtracting(own).compactMap { rows[$0.rawValue] }
            failed = await ask(heldEarlier, into: &answers)
        } else {
            unnamed.formUnion(earlier)
        }
        if !failed && !answers.isEmpty { namesFailing = false }
        return answers
    }

    /// Asks the core about `held` in batches, and returns whether any batch failed.
    private func ask(_ held: [Marfa.Item], into answers: inout [String: ItemDisplay]) async -> Bool {
        answers.reserveCapacity(answers.count + held.count)
        var failed = false
        var start = 0
        while start < held.count {
            let end = held.count - start > Self.displayBatch ? start + Self.displayBatch : held.count
            let batch = Array(held[start..<end])
            start = end
            do {
                #if DEBUG
                hooks.namesAsked.update { $0.append(batch.map(\.id)) }
                if let error = hooks.naming.current?(batch.map(\.id)) { throw error }
                #endif
                let answered = try await Self.asking { try await copy.items.displays(of: batch) }
                for (row, display) in zip(batch, answered) { answers[row.id] = display }
            } catch {
                failed = true
                unnamed.formUnion(batch.map { ItemID($0.id) })
                if !namesFailing {
                    namesFailing = true
                    readFailed(error)
                }
            }
        }
        return failed
    }

    /// Below this many rows, spreading the work costs more than it saves.
    nonisolated static let serialMapping = 256

    /// Each row as the library shows it, with its text, in the order given. A whole read maps
    /// every row, which is most of a launch's paint, and each row maps alone, so a large batch is spread over the
    /// processor's cores.
    nonisolated static func mapped(
        _ present: [(id: ItemID, row: Marfa.Item)], reading state: Mapping
    ) -> [(item: Item, text: String?)] {
        @Sendable func map(_ row: Marfa.Item, id: ItemID) -> (item: Item, text: String?) {
            let held = state.edges.edges(touching: row.id).sorted { $0.createdAt < $1.createdAt }
            let item = MarfaMapping.item(
                row, edges: held, catalogue: state.catalogue, sync: state.syncStates[id] ?? .settled,
                bodyLinks: state.bodyLinks[row.id], display: state.displays[row.id], isHeld: { state.rows[$0] != nil })
            return (item, MarfaMapping.body(of: row, catalogue: state.catalogue))
        }
        guard present.count >= serialMapping else { return present.map { map($0.row, id: $0.id) } }
        let chunks = min(present.count / (serialMapping / 4), ProcessInfo.processInfo.activeProcessorCount * 4)
        // Each chunk fills its own slots, and the chunks together cover every slot once.
        return Array<(item: Item, text: String?)>(unsafeUninitializedCapacity: present.count) { buffer, count in
            nonisolated(unsafe) let slots = buffer
            DispatchQueue.concurrentPerform(iterations: chunks) { chunk in
                let start = present.count * chunk / chunks, end = present.count * (chunk + 1) / chunks
                for index in start..<end { slots.initializeElement(at: index, to: map(present[index].row, id: present[index].id)) }
            }
            count = present.count
        }
    }
}
