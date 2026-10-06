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
    /// The server refused the key, or it lacks what reading the library needs. Writes wait until the person gives
    /// another.
    case keyRefused
    /// Following the server stopped, and stays stopped until the next refresh. The copy still reads and queues.
    case stopped(code: String, message: String)
}

/// A library read from a Marfa server through the package's working copy: the copy answers every read, so the
/// library shows what it holds before, and without, the network.
nonisolated final class MarfaSource: ItemSource, SyncReporting {
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

    /// Takes `key` between server calls and asks the server with it at once; the follow and the drain go on
    /// with it whatever the answer, so a caller that keeps another key gives that one back.
    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck {
        do {
            return try await engine.sync.tryKey(key)
        } catch let error as MarfaError {
            // A copy that could not open its store again is closed for good, and is opened again.
            if case .closed = error { throw SourceFailure(kind: .missing, message: error.message) }
            throw SourceFailure(kind: .failed, message: error.message)
        }
    }

    // MARK: Sync problems

    var syncReport: SyncReport { hub.report.value }

    func syncReports() -> AsyncStream<SyncReport> {
        hub.report.values()
    }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        guard let entry = hub.report.value.problems.first(where: { $0.id == problem }), entry.actions.contains(action)
        else { return false }
        switch (problem, action) {
        case (.write(let id), .discard):
            return try await ask { .discard(id, $0) }
        case (.write(let id), .tryAgain):
            return try await ask { .release(id, $0) }
        case (.write(let id), .withdraw):
            // It reads the server, so it runs beside the engine rather than holding up the writes behind it; the
            // copy announces the withdrawal, which the engine reads again.
            do {
                return try await MarfaEngine.asking(hub) { try await copy.queue.withdraw(id) }
            } catch let error as MarfaError {
                throw SourceFailure(kind: .failed, message: error.message)
            }
        case (.conflictedCopy(let copy), .discard):
            submit(.transition(copy, .trashed), as: WriteID())
            return true
        case (.conflictedCopy(let copy), .keep):
            submit(.tag(copy, MarfaProblems.conflictedCopyTag, on: false), as: WriteID())
            return true
        default:
            return false
        }
    }

    private func ask(
        _ event: (CheckedContinuation<Result<Bool, SourceFailure>, Never>) -> MarfaEngine.Event
    ) async throws -> Bool {
        let result = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(event(continuation)) { continuation.resume(returning: .success(false)) }
        }
        return try result.get()
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
            return try await MarfaEngine.asking(hub) { try await copy.blobs.get(hash) }
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
            hits = try await MarfaEngine.asking(hub) { try await copy.search(text, filters: filters, limit: 500) }
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

    /// The report once every write submitted before this call is in the queue.
    func settledReport() async -> SyncReport {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.settle(continuation)) { continuation.resume(returning: hub.report.value) }
        }
    }

    /// Closes, as `close()` does, only if no more than `limit` writes are not sent once every write submitted
    /// before this call is in the queue, deciding and closing in one step; otherwise it stays open and answers
    /// the report that kept it so.
    func close(unlessUnsentExceeds limit: Int) async -> SyncReport? {
        let kept = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.closeIfUnsent(atMost: limit, continuation)) {
                continuation.resume(returning: nil)
            }
        }
        if kept == nil { events.finish() }
        return kept
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
            let row = try await MarfaEngine.asking(hub) { () async throws -> Marfa.Item? in
                if let row = try await copy.items.get(id.rawValue) { return row }
                return try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id.rawValue }
            }
            if let row { return row }
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
        var finished = false
    }

    private let state = Mutex(State())
    private let keyChange = Mutex((changing: false, count: 0))
    private let connectionState = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport())

    var connection: MarfaConnectionState { connectionState.value }

    /// Counts each start and end of a change of key, so a call refused during one is told from one refused for
    /// its own sake.
    var keyChanges: Int { keyChange.withLock { $0.count } }

    func keyChanged(since mark: Int) -> Bool {
        keyChange.withLock { $0.changing || $0.count != mark }
    }

    func changingKey(_ changing: Bool) {
        keyChange.withLock {
            $0.changing = changing
            $0.count += 1
        }
    }
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
        connectionState.values()
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
