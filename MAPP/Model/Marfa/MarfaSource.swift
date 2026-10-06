import Foundation
import Marfa
import Synchronization

/// What the source knows of its server, for the app to show beside the library.
nonisolated enum MarfaConnectionState: Hashable, Sendable {
    /// Showing what the copy holds, not yet heard from the server.
    case connecting
    case online
    /// The server cannot be reached; writes wait in the queue and go when it can.
    case offline(reason: String?)
    /// Following the server stopped, and stays stopped until the next refresh. The copy still reads and queues.
    case stopped(code: String, message: String)
}

/// A library read from a Marfa server through the package's working copy: the copy answers every read, so the
/// library shows what it holds before, and without, the network.
nonisolated final class MarfaSource: ItemSource {
    let connection: MarfaConnection
    let capabilities: SourceCapabilities = [.archive]
    let embeds: any EmbedResolver = MarfaEmbeds()
    let copy: WorkingCopy
    private let hub = MarfaHub()
    let engine: MarfaEngine
    let events: AsyncStream<MarfaEngine.Event>.Continuation

    private init(copy: WorkingCopy, connection: MarfaConnection) {
        self.copy = copy
        self.connection = connection
        let (stream, events) = AsyncStream<MarfaEngine.Event>.makeStream()
        self.events = events
        engine = MarfaEngine(copy: copy, hub: hub, tell: { event in
            if case .terminated = events.yield(event) { false } else { true }
        })
        Task { [engine] in await engine.run(stream) }
    }

    /// Opens the working copy for `connection` and paints from it, asking the server nothing; `refresh()` then
    /// brings it up to date. `location` keeps each server's copy apart, outside any notes folder. It reads the
    /// keychain and makes the directory, so it never runs on the main actor.
    @concurrent static func open(
        _ connection: MarfaConnection, keys: any KeyStore, location: MarfaStoreLocation
    ) async throws -> MarfaSource {
        guard let key = try keys.key(for: connection) else {
            throw SourceFailure(kind: .denied, message: String(localized: "There’s no key for this Marfa server."))
        }
        let directory = location.directory(for: connection)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy: WorkingCopy
        do {
            copy = try await WorkingCopy.open(store: location.store(for: connection), server: connection.server(key: key))
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        // A second opener of a store only reads it, and every write it made would be refused.
        guard copy.handle == .writer else {
            await copy.close()
            throw SourceFailure(kind: .failed, message: String(localized: "This library is already open in MAPP or another app."))
        }
        let source = MarfaSource(copy: copy, connection: connection)
        source.events.yield(.paint)
        return source
    }

    func changes() -> AsyncStream<SourceChange> {
        hub.changes()
    }

    func connectionStates() -> AsyncStream<MarfaConnectionState> {
        hub.connectionStates()
    }

    var connectionState: MarfaConnectionState { hub.connection }

    /// Hydrates a new copy or catches up a held one, then sends what waits in the queue. Call it once the
    /// first paint is shown and again when the Mac wakes, which also restarts a stopped follow. Writes go to the
    /// queue at once meanwhile; a refresh or a drain that fails is tried again later on its own.
    func refresh() {
        Task { [engine] in await engine.sync.refresh() }
    }

    func submit(_ write: ItemWrite, as id: WriteID) {
        events.yield(.write(write, id))
    }

    func body(of item: ItemID) async throws -> ItemBody {
        let row = try await self.row(item)
        let text = MarfaMapping.body(of: row, catalogue: hub.catalogue) ?? ""
        return ItemBody(id: item, text: text, version: ItemVersion(row.version))
    }

    func fileURL(of item: ItemID) async throws -> URL {
        let row = try await self.row(item)
        guard let hash = row.properties[MarfaMapping.blobField]?.string else {
            throw SourceFailure(kind: .missing, message: String(localized: "This item has no file."))
        }
        do {
            return try await copy.blobs.get(hash)
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
    }

    /// Ids best match first, narrowed to `query` by what the copy holds, since the package filters one type at a
    /// time and one state at a time.
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] {
        var filters = SearchFilters(tags: query.tags.sorted(), beneath: query.beneath?.rawValue)
        if query.types.count == 1, query.includesSubtypes { filters.type = query.types.first?.rawValue }
        if query.states.count == 1, let state = query.states.first {
            filters.state = MarfaMapping.marfaState(state)
        } else {
            filters.allStates = true
        }
        let hits: [SearchHit]
        do {
            hits = try await copy.search(text, filters: filters, limit: 500)
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        let (items, catalogue) = hub.itemsAndCatalogue
        // The copy already kept only what is beneath the root, so each hit counts as beneath it here.
        let beneath = Set(hits.map { ItemID($0.item.id) })
        return hits.compactMap { hit in
            let id = ItemID(hit.item.id)
            guard let item = items[id], query.matches(item, catalogue: catalogue, descendants: beneath) else { return nil }
            return id
        }
    }

    func endEditing(_ item: ItemID) {}

    /// Returns once every write submitted before it has been queued and the queue drained where the server can
    /// be reached.
    func flush() async {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.flush(continuation)) { continuation.resume() }
        }
    }

    /// Nothing submitted after this is taken, and a flush still waiting returns.
    func close() async {
        await withCheckedContinuation { continuation in
            let sent = events.yield(.close(continuation))
            events.finish()
            if case .terminated = sent { continuation.resume() }
        }
    }

    /// A row in the bin is not answered by `get`, only by a list of the bin.
    private func row(_ id: ItemID) async throws -> Marfa.Item {
        do {
            if let row = try await copy.items.get(id.rawValue) { return row }
            if let row = try await copy.items.list(ListFilters(state: .trashed)).first(where: { $0.id == id.rawValue }) {
                return row
            }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        throw SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))
    }
}

/// The package has no embeds yet: body links and attachments as edges are still to come.
nonisolated struct MarfaEmbeds: EmbedResolver {
    func base(for item: ItemID) -> String { "" }
    func resolve(_ reference: String, from item: ItemID) async -> URL? { nil }
    func attach(_ files: [URL], to item: ItemID) async throws -> [Embed] {
        throw SourceFailure(kind: .failed, message: MarfaEngine.notYet)
    }
}

/// Keeps what every reader of the source has been told, so one that arrives late starts from `.loaded` with it.
nonisolated final class MarfaHub: Sendable {
    private struct State {
        var snapshot: SourceSnapshot?
        var readers: [UUID: AsyncStream<SourceChange>.Continuation] = [:]
        var connection = MarfaConnectionState.connecting
        var watchers: [UUID: AsyncStream<MarfaConnectionState>.Continuation] = [:]
        var finished = false
    }

    private let state = Mutex(State())

    var connection: MarfaConnectionState { state.withLock { $0.connection } }
    var catalogue: Catalogue { state.withLock { $0.snapshot?.catalogue ?? Catalogue() } }

    var itemsAndCatalogue: ([ItemID: Item], Catalogue) {
        state.withLock { state in
            let items = state.snapshot?.items ?? []
            return (
                Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last }),
                state.snapshot?.catalogue ?? Catalogue()
            )
        }
    }

    var snapshot: SourceSnapshot? { state.withLock { $0.snapshot } }

    func changes() -> AsyncStream<SourceChange> {
        let (stream, continuation) = AsyncStream<SourceChange>.makeStream()
        let token = UUID()
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.readers.removeValue(forKey: token) } }
        let finished = state.withLock { state in
            guard !state.finished else { return true }
            if let snapshot = state.snapshot { continuation.yield(.loaded(snapshot)) }
            state.readers[token] = continuation
            return false
        }
        if finished { continuation.finish() }
        return stream
    }

    func connectionStates() -> AsyncStream<MarfaConnectionState> {
        let (stream, continuation) = AsyncStream<MarfaConnectionState>.makeStream()
        let token = UUID()
        continuation.onTermination = { [weak self] _ in self?.state.withLock { _ = $0.watchers.removeValue(forKey: token) } }
        let finished = state.withLock { state in
            guard !state.finished else { return true }
            continuation.yield(state.connection)
            state.watchers[token] = continuation
            return false
        }
        if finished { continuation.finish() }
        return stream
    }

    /// Only the engine publishes, one change at a time, so telling readers outside the lock keeps their order.
    func publish(_ change: SourceChange) {
        let readers = state.withLock { state -> [AsyncStream<SourceChange>.Continuation] in
            switch change {
            case .loaded(let snapshot): state.snapshot = snapshot
            default:
                guard state.snapshot != nil else { return [] }
                state.snapshot?.apply(change)
            }
            return Array(state.readers.values)
        }
        for reader in readers { reader.yield(change) }
    }

    func set(_ connection: MarfaConnectionState) {
        let watchers = state.withLock { state -> [AsyncStream<MarfaConnectionState>.Continuation] in
            guard state.connection != connection else { return [] }
            state.connection = connection
            return Array(state.watchers.values)
        }
        for watcher in watchers { watcher.yield(connection) }
    }

    func finish() {
        let (readers, watchers) = state.withLock { state in
            state.finished = true
            defer {
                state.readers = [:]
                state.watchers = [:]
            }
            return (Array(state.readers.values), Array(state.watchers.values))
        }
        for reader in readers { reader.finish() }
        for watcher in watchers { watcher.finish() }
    }
}

extension SourceSnapshot {
    nonisolated mutating func apply(_ change: SourceChange) {
        switch change {
        case .loaded(let snapshot): self = snapshot
        case .upserted(let changed):
            var index = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            for item in changed {
                if let position = index[item.id] {
                    items[position] = item
                } else {
                    index[item.id] = items.count
                    items.append(item)
                }
            }
        case .removed(let ids):
            let gone = Set(ids)
            items.removeAll { gone.contains($0.id) }
        case .catalogue(let catalogue): self.catalogue = catalogue
        case .places(let places): self.places = places
        case .bodyChanged, .answered, .unavailable: break
        }
    }
}
