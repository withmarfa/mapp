import Foundation
import Marfa
import struct MarfaCore.Item
import struct MarfaCore.ListFilters
import struct MarfaCore.SearchFilters
import struct MarfaCore.SearchHit
import enum MarfaCore.ItemState
import Synchronization

/// The writes a copy holds that the server has not taken, by their queue ids, so what the person agrees to lose
/// covers those and no write that arrives after.
nonisolated struct UnsentWrites: Sendable {
    /// What the person wrote in one of the writes, to show before they agree to lose it.
    nonisolated struct Text: Hashable, Sendable, Identifiable {
        let id: String
        var change: SyncProblemEntry.Change
        var content: SyncContent
        var date: Date
    }

    var ids: Set<String>
    /// The writes that carried content, oldest first. Shown, never compared: two reads of the same queue agree
    /// on what is not sent by its ids alone.
    var texts: [Text] = []
    var count: Int { ids.count }
}

nonisolated extension UnsentWrites: Hashable {
    static func == (lhs: UnsentWrites, rhs: UnsentWrites) -> Bool { lhs.ids == rhs.ids }
    func hash(into hasher: inout Hasher) { hasher.combine(ids) }
}

nonisolated enum CloseOutcome: Hashable, Sendable {
    case closed
    /// Kept open for writes not agreed to; nil where the queue could not be read.
    case waiting(UnsentWrites?)
}

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
    /// Following the server stopped, and stays stopped until a refresh: one a failed follow waits for, and one the engine makes when the core ended the stream on a fault and a new one is taken. The copy still reads and queues.
    case stopped(code: String, message: String)
}

/// A library read from a Marfa server through the package's working copy: the copy answers every read, so the
/// library shows what it holds before, and without, the network.
nonisolated final class MarfaSource: ItemSource {
    let connection: MarfaConnection
    let embeds: any EmbedResolver
    let copy: WorkingCopy
    let downloadedFiles: (any DownloadedFiles)?
    private let hub = MarfaHub()
    let engine: MarfaEngine
    let events: AsyncStream<MarfaEngine.Event>.Continuation

    init(copy: WorkingCopy, connection: MarfaConnection,
         reading: (any MarfaReading)? = nil, refreshing: (any MarfaRefreshing)? = nil) {
        self.copy = copy
        let downloads = MarfaDownloads(copy: copy)
        downloadedFiles = downloads
        self.connection = connection
        let (stream, events) = AsyncStream<MarfaEngine.Event>.makeStream()
        self.events = events
        embeds = MarfaEmbeds(events: events)
        engine = MarfaEngine(copy: copy, hub: hub, downloads: downloads, reading: reading, refreshing: refreshing, tell: { event in
            if case .terminated = events.yield(event) { false } else { true }
        })
        Task { [engine] in await engine.run(stream) }
    }

    /// Opens the working copy for `connection` and paints from it, asking the server nothing; `refresh()` then
    /// brings it up to date. `location` keeps each server's copy apart. It reads the keychain and makes the
    /// directory, so it never runs on the main actor.
    @concurrent static func open(
        _ connection: MarfaConnection, keys: any KeyStore, location: MarfaStoreLocation
    ) async throws -> MarfaSource {
        guard let key = try keys.key(for: connection) else {
            throw SourceFailure(kind: .denied, message: String(localized: "There’s no key for this Marfa server."))
        }
        try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
        let copy: WorkingCopy
        do {
            copy = try await openCopy(connection, key: key, location: location)
        } catch MarfaError.wrongSchema(_, _, let unsent, let message) {
            throw SourceFailure(kind: .otherVersion(unsent: unsent), message: message)
        } catch MarfaError.readingHandle {
            throw SourceFailure(kind: .inUse, message: Words.inUse)
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        // A second opener of a store only reads it, and every write it made would be refused.
        guard copy.handle == .writer else {
            await copy.close()
            throw SourceFailure(kind: .inUse, message: Words.inUse)
        }
        let source = MarfaSource(copy: copy, connection: connection)
        source.events.yield(.paint)
        return source
    }

    /// The package refuses a copy a different version of the app made, removing nothing, with the count of changes
    /// in it the server has not taken. With none, the copy holds only what the server holds, so the package
    /// replaces it with an empty one, keeping the files it downloaded, and the new copy hydrates from the server.
    /// The package refuses the replacement while another process writes the copy or a change arrives in it. With
    /// any changes, or where the count can't be read, only that version can send them, and the person is told.
    private static func openCopy(
        _ connection: MarfaConnection, key: String, location: MarfaStoreLocation
    ) async throws -> WorkingCopy {
        let store = location.store(for: connection)
        do {
            return try await WorkingCopy.open(store: store, server: connection.server(key: key))
        } catch MarfaError.wrongSchema(_, _, 0?, _) {
            do {
                return try await WorkingCopy.replaceRefused(store: store, server: connection.server(key: key))
            } catch let error as MarfaError {
                switch error {
                case .wrongSchema, .readingHandle: throw error
                default: throw SourceFailure(kind: .failed, message: Words.notReplaced)
                }
            }
        }
    }

    func changes() -> AsyncStream<SourceChange> {
        hub.changes()
    }

    func connectionStates() -> AsyncStream<MarfaConnectionState> {
        hub.connectionStates()
    }

    var connectionState: MarfaConnectionState { hub.connection }

    /// Hydrates a new copy or catches up a held one, then sends what waits in the queue. Call it once the
    /// first paint is shown; the package refills a copy whose place the server let go, as after a long sleep.
    /// Writes go to the queue at once meanwhile; a refresh or a drain that fails is tried again later on its own.
    func refresh() {
        Task { [engine] in await engine.sync.refresh() }
    }

    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool {
        if case .terminated = events.yield(.write(write, id)) { return false }
        return true
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

    /// A few rows are read one by one; more are read in one list of the copy rather than a read each.
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody] {
        guard !items.isEmpty else { return [] }
        let rows: [Marfa.Item]
        do {
            rows = try await MarfaEngine.asking(hub) { () async throws -> [Marfa.Item] in
                if items.count <= 12 {
                    var rows: [Marfa.Item] = []
                    for id in items { if let row = try await copy.items.get(id.rawValue) { rows.append(row) } }
                    return rows
                }
                return try await copy.items.list(ListFilters(allStates: true)).filter { items.contains(ItemID($0.id)) }
            }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        let catalogue = hub.catalogue
        // An item in the server's bin is not in the copy, so its text is what the bin read gave.
        let held = Set(rows.map(\.id))
        let binned = items.compactMap { id in held.contains(id.rawValue) ? nil : hub.binnedRow(id.rawValue) }
        return (rows + binned).compactMap { row in
            MarfaMapping.body(of: row, catalogue: catalogue)
                .map { ItemBody(id: ItemID(row.id), text: $0, version: ItemVersion(row.version)) }
        }
    }

    func fileURL(of item: ItemID) async throws -> URL {
        let row = try await self.row(item)
        guard let hash = row.properties[MarfaMapping.blobField]?.string else {
            throw SourceFailure(kind: .missing, message: String(localized: "This item has no file."))
        }
        do {
            return try await MarfaEngine.asking(hub) {
                try await copy.blobs.withFile(hash) { try Self.keptCopy(of: $0, named: hash) }
            }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        } catch {
            throw SourceFailure(kind: .failed, message: error.localizedDescription)
        }
    }

    /// The package keeps a fetched file from cache trimming only while `withFile` runs, and the views read the file
    /// long after, so its bytes are copied out under their hash, which names them whole.
    static func keptCopy(of file: URL, named hash: String) throws -> URL {
        let manager = FileManager.default
        let directory = URL.temporaryDirectory.appending(path: "MAPP Files", directoryHint: .isDirectory)
        let kept = directory.appending(path: hash, directoryHint: .notDirectory)
        if manager.fileExists(atPath: kept.path) { return kept }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Copied beside and moved in whole, so a copy cut short is never taken for the file.
        let partial = directory.appending(path: "\(hash).\(UUID().uuidString).partial", directoryHint: .notDirectory)
        try manager.copyItem(at: file, to: partial)
        do {
            try manager.moveItem(at: partial, to: kept)
        } catch {
            try? manager.removeItem(at: partial)
            if !manager.fileExists(atPath: kept.path) { throw error }
        }
        return kept
    }

    /// Read from the copy alone, so a view lists only what the copy holds, which is every item the library holds.
    func items(inView view: ItemID) async throws -> [ItemID] {
        do {
            return try await MarfaEngine.asking(hub) { try await engine.reading.items(inView: view.rawValue) }
                .filter(MarfaMapping.isLibraryItem).map { ItemID($0.id) }
        } catch {
            throw MarfaEngine.failure(error)
        }
    }

    /// Narrowed to `query` by what the copy holds, since the package filters one type at a time and one state at
    /// a time.
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
            hits = try await MarfaEngine.asking(hub) { try await copy.search(text, filters: filters, limit: 500).rows }
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

    /// Returns once every write submitted before it has been queued and the queue drained where the server can
    /// be reached. The app never waits on the server like this; the tests that drive a server do.
    func flush() async {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.flush(continuation)) { continuation.resume() }
        }
    }

    /// Returns once every write submitted before it is in the queue, or refused, without waiting on the network,
    /// so a quit while offline keeps every write and does not wait for a server.
    func queueSubmitted() async {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.queued(continuation)) { continuation.resume() }
        }
    }

    /// The writes not sent once every write submitted before this call is in the queue; nil where the queue
    /// cannot be read.
    func unsentWrites() async -> UnsentWrites? {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.unsent(continuation)) { continuation.resume(returning: nil) }
        }
    }

    /// Closes, as `close()` does, only if every write not sent, once every write submitted before this call is
    /// in the queue, is one of `agreed`, deciding and closing in one step; nil agrees to whatever the copy
    /// holds. Otherwise it stays open and answers what is not sent.
    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome {
        let outcome = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.closeAgreeing(agreed, continuation)) {
                continuation.resume(returning: .closed)
            }
        }
        if outcome == .closed { events.finish() }
        return outcome
    }

    /// Nothing submitted after this is taken, and a flush still waiting returns.
    func close() async {
        await withCheckedContinuation { continuation in
            let sent = events.yield(.close(continuation))
            events.finish()
            if case .terminated = sent { continuation.resume() }
        }
    }

    /// A row in the bin is not answered by `get`: the copy lists those it still holds, and the rest are the ones
    /// the server's bin gave.
    private func row(_ id: ItemID) async throws -> Marfa.Item {
        do {
            let row = try await MarfaEngine.asking(hub) { () async throws -> Marfa.Item? in
                if let row = try await copy.items.get(id.rawValue) { return row }
                return try await copy.items.list(ListFilters(state: .trashed)).first { $0.id == id.rawValue }
            }
            if let row = row ?? hub.binnedRow(id.rawValue) { return row }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        throw SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))
    }
}

/// Attaches files through the engine, which asks the package to queue each one's upload, its file item and its
/// edge to the item, and says what to write in the text to embed it.
nonisolated struct MarfaEmbeds: EmbedResolver {
    let events: AsyncStream<MarfaEngine.Event>.Continuation

    func attach(_ files: [URL], to item: ItemID) async throws -> [Embed] {
        var embeds: [Embed] = []
        for file in files {
            let result = await withCheckedContinuation { continuation in
                if case .terminated = events.yield(.attach(file, item, continuation)) {
                    continuation.resume(returning: .failure(SourceFailure(kind: .missing, message: MarfaEngine.closedLibrary)))
                }
            }
            embeds.append(try result.get())
        }
        return embeds
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
    /// The rows of the server's bin that the copy does not hold, for the readers of their text.
    private let bin = Mutex<[String: Marfa.Item]>([:])

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
    func setBinned(_ rows: [String: Marfa.Item]) {
        bin.withLock { $0 = rows }
    }

    func binnedRow(_ id: String) -> Marfa.Item? {
        bin.withLock { $0[id] }
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
        case .views(let views): self.views = views
        case .bodyChanged, .answered, .unavailable: break
        }
    }
}
