import Foundation
import Marfa
import Synchronization
import UniformTypeIdentifiers

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

/// How the library's server stands, for the app to show beside the library: the one record of it. An open copy
/// reports `connecting`, `online`, `offline`, `keyRefused` and `unavailable` (`MarfaHub`), which `MarfaLibrary`
/// holds; `MarfaHost` reports the rest, and any of these, only while no copy is open.
nonisolated enum MarfaConnectionState: Hashable, Sendable {
    /// No server is set.
    case disconnected
    /// Showing what the copy holds, not yet heard from the server.
    case connecting
    case online
    /// The server cannot be reached; writes wait in the queue and go when it can.
    case offline(reason: String?)
    /// The server ended the sign-in, or it lacks what reading the library needs. Writes wait until the person gives
    /// another in Settings.
    case keyRefused
    /// The copy cannot be opened, or the sync stopped on a fault that asking again may not clear, such as a copy made
    /// for another server; the message is the package's. It stays until the package follows the server again or a
    /// refresh succeeds. The copy still reads and queues.
    case unavailable(message: String)
    /// A different version of the app made the copy, so this one can't open it, and leaves it as it is. The
    /// changes in it that the server has not taken (`unsent`, never 0, and nil where that can't be read) can
    /// only be sent by that version.
    case otherVersion(unsent: UInt64?)
    /// Another copy of the app on this Mac holds the copy, so this one can't open it.
    case inUse
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
    let events: MarfaEngine.Events

    init(copy: WorkingCopy, connection: MarfaConnection,
         reading: (any MarfaReading)? = nil, refreshing: (any MarfaRefreshing)? = nil) {
        self.copy = copy
        let downloads = MarfaDownloads(copy: copy)
        downloadedFiles = downloads
        self.connection = connection
        let (stream, continuation) = AsyncStream<MarfaEngine.Event>.makeStream()
        let events = MarfaEngine.Events(continuation, activity: hub.activity)
        self.events = events
        embeds = MarfaEmbeds(events: events)
        engine = MarfaEngine(copy: copy, hub: hub, reading: reading, refreshing: refreshing, tell: { event in
            if case .terminated = events.yield(event) { false } else { true }
        })
        Task { [engine] in await engine.run(stream) }
    }

    /// Opens the working copy for `connection` and paints from it, asking the server nothing; `refresh()` then
    /// brings it up to date. `location` keeps each server's copy apart. It reads the sign-in from the Keychain and makes the
    /// directory, so it never runs on the main actor.
    @concurrent static func open(
        _ connection: MarfaConnection, signIns: any SignIns, location: MarfaStoreLocation
    ) async throws -> MarfaSource {
        let server: Server?
        do {
            server = try signIns.server(for: connection)
        } catch {
            // A sign-in the Keychain would not give is neither missing nor ended: the person is told that, and the
            // sign-in is left where it is.
            throw SourceFailure(kind: .failed, message: Words.signInUnreadable)
        }
        guard let server else {
            throw SourceFailure(kind: .denied, message: String(localized: "MAPP isn’t signed in to this Marfa server."))
        }
        try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
        let copy: WorkingCopy
        do {
            copy = try await openCopy(connection, server: server, location: location)
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
    /// in it the server has not taken. With none, the copy holds only what the server holds, so `.replace` makes
    /// an empty one, keeping the files it downloaded, and the new copy hydrates from the server. With any changes
    /// it refuses with that count (`wrongSchema`), and only that version can send them, so the person is told.
    private static func openCopy(
        _ connection: MarfaConnection, server: Server, location: MarfaStoreLocation
    ) async throws -> WorkingCopy {
        try await WorkingCopy.open(
            store: location.store(for: connection), server: server, ifRefused: .replace)
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
    func submit(_ write: ItemWrite, as id: WriteID, undoing: UndoGroup?) -> Bool {
        let event: MarfaEngine.Event = undoing.map { .undo(write, id, $0) } ?? .write(write, id)
        if case .terminated = events.yield(event) { return false }
        return true
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
                return try await MarfaEngine.asking { try await copy.queue.withdraw(id) }
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

    func linkAnswers(of targets: [String], in note: ItemID?) async throws -> [LinkAnswer] {
        try await copy.items.linkCandidates(of: targets, in: note?.rawValue).map { answer in
            let state: LinkAnswer.State
            switch answer.state {
            case .bound: state = .bound
            case .ambiguous: state = .ambiguous
            case .unresolved: state = .unresolved
            }
            return LinkAnswer(
                target: answer.target, state: state, item: answer.item.map { ItemID($0) }, candidates: answer.candidates.map { ItemID($0) })
        }
    }

    /// `Edges.check` throws `validation` or `notFound` for an edge the core refuses. Any other error (the key changing,
    /// the copy closed or not yet whole, a canceled call) says nothing about the edge.
    func edgeVerdict(_ draft: EdgeDraft) async -> EdgeVerdict {
        await verdict { try await copy.edges.check(from: draft.source.rawValue, to: draft.target.rawValue, type: draft.type) }
    }

    func edgeVerdict(moving edge: EdgeID, end: EdgeTypeInfo.End, to: ItemID) async -> EdgeVerdict {
        let move: EdgeEdit.Move = end == .source ? .source(to.rawValue) : .target(to.rawValue)
        return await verdict { try await copy.edges.check(edge.rawValue, moving: move) }
    }

    private func verdict(_ check: () async throws -> Void) async -> EdgeVerdict {
        do {
            try await check()
            return .taken
        } catch let error as MarfaError {
            switch error {
            case .validation, .notFound: return .refused(await refusal(error))
            default: return .unknown
            }
        } catch {
            return .unknown
        }
    }

    /// The core's refusal in the person's words where MAPP can say more than the core does: an end that already holds the
    /// one link of its type is named, as is a link made twice. Any other refusal is the core's own.
    private func refusal(_ error: MarfaError) async -> String {
        guard case .validation("edge_constraint_violation", _, let details) = error else { return error.message }
        switch details?.object?["constraint"]?.string {
        case "cardinality":
            let object = details?.object
            let full = (object?["target_id"] ?? object?["source_id"])?.string
            var title: String?
            if let full { title = try? await row(ItemID(full)).title }
            let name = title.flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Untitled")
            return String(localized: "“\(name)” can hold only one link of this kind, and already holds it.")
        case "duplicate":
            return String(localized: "These items are already linked this way.")
        default:
            return error.message
        }
    }

    func fileURL(of item: ItemID) async throws -> URL {
        let row = try await self.row(item)
        guard let hash = row.properties[MarfaMapping.blobField]?.string else {
            throw SourceFailure(kind: .missing, message: String(localized: "This item has no file."))
        }
        let name = Self.keptName(title: row.title, mimeType: row.properties[MarfaMapping.mimeTypeField]?.string)
        do {
            return try await MarfaEngine.asking {
                try await copy.blobs.withFile(hash) { try await Self.keptCopy(of: $0, hash: hash, name: name) }
            }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: Self.fetchFailure(error))
        } catch {
            throw SourceFailure(kind: .failed, message: error.localizedDescription)
        }
    }

    /// Why a file couldn't be had, in the person's words where the package's would only be technical.
    static func fetchFailure(_ error: MarfaError) -> String {
        if error.isOffline { return String(localized: "This file isn’t on this Mac, and the Marfa server can’t be reached.") }
        return switch error {
        case .noRoom, .storageFull: String(localized: "This Mac doesn’t have enough space to download this file.")
        case .bytesAbsent: String(localized: "The Marfa server doesn’t have this file’s contents.")
        default: error.message
        }
    }

    /// Where kept copies are, cleared when the library is disconnected or its downloads are removed.
    nonisolated static let keptFiles = URL.temporaryDirectory.appending(path: "MAPP Files", directoryHint: .isDirectory)

    /// The file's title as a name on disk, with the extension its type has where the title has none, since the
    /// page, Open and the Finder all tell a file's kind by its extension.
    static func keptName(title: String?, mimeType: String?) -> String {
        let safe = NoteText.fileSafe(title ?? "")
        let name = safe.isEmpty ? String(localized: "File") : safe
        guard (name as NSString).pathExtension.isEmpty,
              let ext = mimeType.flatMap({ UTType(mimeType: $0) })?.preferredFilenameExtension
        else { return name }
        return "\(name).\(ext)"
    }

    /// The package keeps a fetched file from cache trimming only while `withFile` runs, and the views read the file
    /// long after, so its bytes are copied out into a folder named by their hash, which names them whole.
    @concurrent static func keptCopy(of file: URL, hash: String, name: String, in folder: URL = keptFiles) async throws -> URL {
        let manager = FileManager.default
        let directory = folder.appending(path: hash, directoryHint: .isDirectory)
        let kept = directory.appending(path: name, directoryHint: .notDirectory)
        if manager.fileExists(atPath: kept.path) { return kept }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        // Copied beside and moved in whole, so a copy cut short is never taken for the file. The partial copy's
        // name starts with a dot, which `OpenFile` never opens.
        let partial = directory.appending(path: ".\(UUID().uuidString).partial", directoryHint: .notDirectory)
        try manager.copyItem(at: file, to: partial)
        do {
            // Read-only, so an app Open hands it to offers a duplicate rather than saving over Marfa's file.
            try manager.setAttributes([.posixPermissions: 0o444], ofItemAtPath: partial.path)
            try manager.moveItem(at: partial, to: kept)
        } catch {
            try? manager.removeItem(at: partial)
            if !manager.fileExists(atPath: kept.path) { throw error }
        }
        return kept
    }

    /// Clears every kept copy, so files fetched for a library don't outlast it on this Mac.
    @concurrent static func removeKeptCopies(in folder: URL = keptFiles) async {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Read from the copy alone, so a view lists only what the copy holds, which is every item the library holds.
    func items(inView view: ItemID) async throws -> [ItemID] {
        do {
            return try await MarfaEngine.asking { try await engine.reading.items(inView: view.rawValue) }
                .filter(MarfaMapping.isLibraryItem).map { ItemID($0.id) }
        } catch {
            throw MarfaEngine.failure(error)
        }
    }

    func createView(_ settings: LibraryViewSettings, idempotencyKey: String) async throws -> LibraryView {
        try await writingView {
            try await copy.createView(MarfaMapping.viewSettings(settings), idempotencyKey: idempotencyKey)
        }
    }

    func changeView(
        _ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64, idempotencyKey: String
    ) async throws -> LibraryView {
        try await writingView {
            try await copy.changeView(
                view.rawValue, MarfaMapping.viewChange(change), baseVersion: baseVersion, idempotencyKey: idempotencyKey)
        }
    }

    func deleteView(_ view: ItemID, idempotencyKey: String) async throws {
        do {
            try await MarfaEngine.asking { try await copy.deleteView(view.rawValue, idempotencyKey: idempotencyKey) }
        } catch {
            throw MarfaMapping.viewFailure(error)
        }
    }

    /// The copy announces the write, which the engine reads into the views it publishes.
    private func writingView(_ write: () async throws -> SavedView) async throws -> LibraryView {
        let saved: SavedView
        do {
            saved = try await MarfaEngine.asking(write)
        } catch {
            throw MarfaMapping.viewFailure(error)
        }
        guard let view = MarfaMapping.view(saved) else {
            throw ViewWriteFailure(kind: .gone, message: String(localized: "Your Marfa server no longer has this view."))
        }
        return view
    }

    /// Narrowed to `target` by the copy, which matches and ranks as the server does, cuts each hit's excerpt and
    /// keeps what is not in the bin out of its answer, so the limit counts items shown.
    func search(_ text: String, in target: SearchTarget) async throws -> SourceSearch {
        let limit = SearchResults.limit
        let rows: Rows<SearchHit>
        do {
            switch target {
            case .items(let itemQuery, let filter):
                var filters = SearchFilters(
                    tier: itemQuery.tier.map(MarfaMapping.marfaTier), tags: itemQuery.tags.sorted(), filter: filter,
                    beneath: itemQuery.beneath?.rawValue)
                if itemQuery.states.isEmpty {
                    filters.allStates = true
                } else {
                    filters.states = Set(itemQuery.states.map(MarfaMapping.marfaState))
                }
                filters.types = itemQuery.types.isEmpty ? nil : Set(itemQuery.types.map(\.rawValue))
                rows = try await MarfaEngine.asking { try await copy.search(text, filters: filters, limit: limit) }
            case .view(let view):
                rows = try await MarfaEngine.asking { try await copy.search(text, inView: view.rawValue, limit: limit) }
            }
        } catch {
            throw MarfaEngine.failure(error)
        }
        var result = SourceSearch(isIncomplete: rows.completeness != .complete, isCapped: rows.rows.count >= limit)
        for hit in rows.rows {
            let id = ItemID(hit.item.id)
            result.hits.append(id)
            result.excerpts[id] = SearchExcerpt(
                runs: hit.excerpt.runs.map { SearchExcerpt.Run(text: $0.text, isMatch: $0.isMatch) },
                version: ItemVersion(hit.item.version), modified: MarfaMapping.timestamp(hit.item.updatedDate))
        }
        return result
    }

    /// Returns once every write submitted before it has been queued and the queue drained where the server can
    /// be reached. The app never waits on the server like this; the tests that drive a server do.
    func flush() async {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.flush(continuation)) { continuation.resume() }
        }
    }

    var engineActivity: EngineActivity? { hub.activity }

    /// Returns once every write submitted before it is in the queue, or refused, without waiting on the network,
    /// so a quit while offline keeps every write and does not wait for a server. It waits for those writes alone,
    /// never behind a read of the copy told after them.
    func queueSubmitted() async {
        await hub.activity.writesTaken()
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

    /// A row in the bin is not answered by `get`, so it is asked for with the bin included.
    private func row(_ id: ItemID) async throws -> Marfa.Item {
        do {
            let rows = try await MarfaEngine.asking { try await copy.items.get([id.rawValue], includingBin: true) }
            if let row = rows.first { return row }
        } catch let error as MarfaError {
            throw SourceFailure(kind: .failed, message: error.message)
        }
        throw SourceFailure(kind: .missing, message: String(localized: "This item isn’t in the library."))
    }
}

/// Attaches files through the engine, which asks the package to queue each one's upload, its file item and its
/// edge to the item, and says what to write in the text to embed it. A file added on its own goes the same way.
nonisolated struct MarfaEmbeds: EmbedResolver {
    let events: MarfaEngine.Events

    func attach(_ file: URL, to item: ItemID) async throws -> Embed {
        let result = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.attach(file, item, continuation)) {
                continuation.resume(returning: .failure(SourceFailure(kind: .missing, message: MarfaEngine.closedLibrary)))
            }
        }
        return try result.get()
    }

    func addFile(_ file: URL, title: String?, tier: Tier?, parent: ItemID?) async throws -> ItemID {
        let result = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.addFile(file, title: title, tier: tier, parent: parent, continuation)) {
                continuation.resume(returning: .failure(SourceFailure(kind: .missing, message: MarfaEngine.closedLibrary)))
            }
        }
        return try result.get()
    }
}

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
            case .answered, .taken, .unavailable: break
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

    /// Only the engine publishes, one change at a time, so telling readers outside the lock keeps their order.
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
