import Foundation
import Synchronization

/// Keeps what every reader of the source has been told, so one that arrives late starts from `.loaded` with it.
nonisolated final class MarfaHub: Sendable {
    private struct State {
        /// What readers were told, by item; nil until the first `.loaded`.
        var held: Held?
        var readers: [UUID: AsyncStream<SourceChange>.Continuation] = [:]
        var finished = false
    }

    /// Kept by ID, so a change costs what it names rather than the whole library; a late reader's `.loaded` is
    /// put in order only when it is asked for.
    private struct Held {
        var items: [ItemID: Item]
        var bodies: [ItemID: ItemBody]
        var catalogue: Catalogue
        var views: [LibraryView]

        init(_ snapshot: SourceSnapshot) {
            items = Dictionary(snapshot.items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            bodies = snapshot.bodies
            catalogue = snapshot.catalogue
            views = snapshot.views
        }

        var snapshot: SourceSnapshot {
            SourceSnapshot(
                items: items.values.sorted(by: MarfaHub.newestFirst), catalogue: catalogue, views: views, bodies: bodies)
        }

        mutating func apply(_ change: SourceChange) {
            switch change {
            case .loaded(let snapshot): self = Held(snapshot)
            case .changed(let changes):
                for id in changes.removed {
                    items[id] = nil
                    bodies[id] = nil
                }
                for item in changes.upserted { items[item.id] = item }
                for body in changes.bodies { bodies[body.id] = body }
            case .catalogue(let catalogue): self.catalogue = catalogue
            case .views(let views): self.views = views
            case .answered, .taken, .counts, .unavailable: break
            }
        }
    }

    /// The order of `.loaded`: newest first, by ID where two were made together, so every reader is told one order.
    nonisolated static func newestFirst(_ lhs: Item, _ rhs: Item) -> Bool {
        lhs.created != rhs.created ? lhs.created > rhs.created : lhs.id.rawValue < rhs.id.rawValue
    }

    private let state = Mutex(State())
    /// What the engine is doing, readable without awaiting it.
    let activity = EngineActivity()
    private let connectionState = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport())

    var connection: MarfaConnectionState { connectionState.value }

    var catalogue: Catalogue { state.withLock { $0.held?.catalogue ?? Catalogue() } }

    /// What readers were last told of each of `ids` that they hold: the item and its text. The engine tells only
    /// what differs from this, so the library's mapped items are held here, once, and not again in the engine.
    func told(_ ids: some Collection<ItemID>) -> [ItemID: (item: Item, text: String?)] {
        state.withLock { state in
            guard let held = state.held else { return [:] }
            var told: [ItemID: (item: Item, text: String?)] = [:]
            told.reserveCapacity(ids.count)
            for id in ids {
                if let item = held.items[id] { told[id] = (item, held.bodies[id]?.text) }
            }
            return told
        }
    }

    var itemsAndCatalogue: ([ItemID: Item], Catalogue) {
        state.withLock { ($0.held?.items ?? [:], $0.held?.catalogue ?? Catalogue()) }
    }

    func changes() -> AsyncStream<SourceChange> {
        let (stream, continuation) = AsyncStream<SourceChange>.makeStream()
        let token = UUID()
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.readers.removeValue(forKey: token) } }
        let finished = state.withLock { state in
            guard !state.finished else { return true }
            if let held = state.held { continuation.yield(.loaded(held.snapshot)) }
            state.readers[token] = continuation
            return false
        }
        if finished { continuation.finish() }
        return stream
    }

    func connectionStates() -> AsyncStream<MarfaConnectionState> {
        connectionState.values()
    }

    /// The engine publishes item changes in order. The sync can also request a count refresh between item changes.
    func publish(_ change: SourceChange) {
        let readers = state.withLock { state -> [AsyncStream<SourceChange>.Continuation] in
            switch change {
            case .loaded(let snapshot): state.held = Held(snapshot)
            default:
                guard state.held != nil else { return [] }
                state.held?.apply(change)
            }
            return Array(state.readers.values)
        }
        for reader in readers { reader.yield(change) }
    }

    func set(_ connection: MarfaConnectionState) {
        connectionState.set(connection)
    }

    func finish() {
        let readers = state.withLock { state in
            state.finished = true
            defer { state.readers = [:] }
            return Array(state.readers.values)
        }
        for reader in readers { reader.finish() }
        connectionState.finish()
        report.finish()
    }
}
