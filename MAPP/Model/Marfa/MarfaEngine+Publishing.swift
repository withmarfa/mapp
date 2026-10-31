import Foundation
import Marfa

/// Mapping rows into items, and telling readers what changed since they were last told.
extension MarfaEngine {
    /// Maps `ids` again and tells readers what differs, in one change: the first time, everything as `.loaded`.
    /// An item's text goes with it where the item is new, its version moved or its text changed, so a page never
    /// shows a version with older text. Failures gathered on the way follow as `.unavailable`.
    func publish(_ ids: some Sequence<ItemID>, catalogueChanged: Bool = false) {
        hub.setBinned(binned)
        let copies = conflictedCopies()
        settleConflicts(copies)
        let ids = Set(ids).union(changedSync)
        changedSync = []
        if catalogueChanged, painted, hub.catalogue != catalogue { hub.publish(.catalogue(catalogue)) }
        var changes = ItemChanges()
        var present: [(id: ItemID, row: Marfa.Item)] = []
        let told = hub.told(ids)
        for id in ids {
            guard let row = rows[id.rawValue] ?? binned[id.rawValue] else {
                if told[id] != nil { changes.removed.append(id) }
                continue
            }
            present.append((id, row))
        }
        let mapped = Self.mapped(present, reading: Mapping(
            rows: rows, edges: edges, catalogue: catalogue, syncStates: syncStates, bodyLinks: bodyLinks))
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
                bodyLinks: state.bodyLinks[row.id], isHeld: { state.rows[$0] != nil })
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
