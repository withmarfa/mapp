import Foundation
import Marfa
import UniformTypeIdentifiers

/// The writes a copy holds that the server has not taken, by their queue ids, so what the person agrees to lose
/// covers those and no write that arrives after.
nonisolated struct UnsentChanges: Sendable {
    /// What the person wrote in one of the writes, to show before they agree to lose it.
    nonisolated struct Text: Hashable, Sendable, Identifiable {
        let id: String
        var change: SyncProblemEntry.Change
        var content: SyncContent
        /// Nil for a store read without opening it, whose writes say no date and are listed in queue order.
        var date: Date?
    }

    var ids: Set<String>
    /// The writes that carried content, oldest first. Shown, never compared: two reads of the same queue agree
    /// on what is not sent by its ids alone.
    var texts: [Text] = []
    var count: Int { ids.count }
}

nonisolated extension UnsentChanges: Hashable {
    static func == (lhs: UnsentChanges, rhs: UnsentChanges) -> Bool { lhs.ids == rhs.ids }
    func hash(into hasher: inout Hasher) { hasher.combine(ids) }
}

nonisolated enum CloseOutcome: Hashable, Sendable {
    case closed
    /// Kept open for writes not agreed to; nil where the queue could not be read.
    case waiting(UnsentChanges?)
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
    let hub = MarfaHub()
    let engine: MarfaEngine
    let events: MarfaEngine.Events
    /// The answers to the app's writes to its settings item, which the engine takes with the rest.
    let preferenceAnswers = PreferenceAnswers()
    private let counting: MarfaCounts

    init(copy: WorkingCopy, connection: MarfaConnection,
         reading: (any MarfaReading)? = nil, refreshing: (any MarfaRefreshing)? = nil) {
        self.copy = copy
        counting = MarfaCounts(copy: copy)
        let downloads = MarfaDownloads(copy: copy)
        downloadedFiles = downloads
        self.connection = connection
        let (stream, continuation) = AsyncStream<MarfaEngine.Event>.makeStream()
        let events = MarfaEngine.Events(continuation, activity: hub.activity)
        self.events = events
        embeds = MarfaEmbeds(events: events)
        engine = MarfaEngine(
            copy: copy, hub: hub, reading: reading, refreshing: refreshing, preferenceAnswers: preferenceAnswers, tell: { event in
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
            throw SourceFailure(kind: .denied, message: String(localized: "The app isn’t signed in to this Marfa server."))
        }
        try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
        let copy: WorkingCopy
        do {
            copy = try await openCopy(connection, server: server, location: location)
        } catch let error as MarfaError {
            throw failure(opening: error)
        }
        // A second opener of a store only reads it, and every write it made would be refused.
        guard copy.handle == .writer else {
            await copy.close()
            throw SourceFailure(kind: .inUse, message: Words.inUse)
        }
        let refreshing = MarfaRefresh(copy: copy, scopes: { try? signIns.scopes(for: connection) })
        let source = MarfaSource(copy: copy, connection: connection, refreshing: refreshing)
        source.events.yield(.paint)
        return source
    }

    /// Another program holding the store, as its writer or mid-write, is the same to the person: another copy of
    /// the app has the library open.
    nonisolated static func failure(opening error: MarfaError) -> SourceFailure {
        switch error {
        case .wrongSchema(_, _, let unsent, let message): SourceFailure(kind: .otherVersion(unsent: unsent), message: message)
        case .readingHandle, .storeBusy: SourceFailure(kind: .inUse, message: Words.inUse)
        default: SourceFailure(kind: .failed, message: Words.message(for: error))
        }
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

    func counts(of ids: [ItemID], _ query: CountQuery) async throws -> [ItemID: ItemCountAnswer] {
        try await counting.counts(of: ids, query)
    }

    func moreItemsTaken(with ids: [ItemID]) async -> Int? {
        let copy = copy
        do {
            let preview = try await MarfaEngine.asking { try await copy.items.previewTrash(ids: ids.map(\.rawValue)) }
            return max(Int(clamping: preview.count) - Set(ids).count, 0)
        } catch {
            return nil
        }
    }

    func instanceID() async -> String? {
        let copy = copy
        return try? await MarfaEngine.asking { try await copy.status() }.instanceId
    }

    /// Hydrates a new copy or catches up a held one, then sends what waits in the queue. Call it once the
    /// first paint is shown; the package refills a copy whose place the server let go, as after a long sleep.
    /// Writes go to the queue at once meanwhile; a refresh or a drain that fails is tried again later on its own.
    func refresh() {
        Task { [engine] in await engine.sync.refresh() }
    }

    func downloadEverythingAgain() {
        Task { [engine] in await engine.sync.rehydrate() }
    }

    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID, undoing: UndoGroup?) -> Bool {
        let event: MarfaEngine.Event = undoing.map { .undo(write, id, $0) } ?? .write(write, id)
        if case .terminated = events.yield(event) { return false }
        return true
    }

    func body(of item: ItemID) async throws -> ItemBody {
        let row = try await self.row(item)
        let text = MarfaMapping.body(of: row, catalogue: hub.catalogue) ?? ""
        return ItemBody(id: item, text: text, version: ItemVersion(row.version))
    }

    func linkAnswers(of targets: [String], in itemID: ItemID?) async throws -> [LinkAnswer] {
        try await MarfaEngine.asking { try await copy.items.linkCandidates(of: targets, in: itemID?.rawValue) }.map { answer in
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

    /// `Edges.check` throws `validation` or `notFound` for an edge the core refuses. Any other error (the copy closed or not yet whole, a canceled call) says nothing about the edge.
    func edgeVerdict(_ draft: EdgeDraft) async -> EdgeVerdict {
        await verdict { try await MarfaEngine.asking { try await copy.edges.check(from: draft.from.rawValue, to: draft.to.rawValue, type: draft.type) } }
    }

    func edgeVerdict(moving edge: EdgeID, end: EdgeTypeInfo.End, to: ItemID) async -> EdgeVerdict {
        let move: EdgeEdit.Move = end == .from ? .from(to.rawValue) : .to(to.rawValue)
        return await verdict { try await MarfaEngine.asking { try await copy.edges.check(edge.rawValue, moving: move) } }
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

    /// The core's refusal in the person's words where the app can say more than the core does: an end that already holds the
    /// one link of its type is named, as is a link made twice. Any other refusal is the core's own.
    private func refusal(_ error: MarfaError) async -> String {
        guard case .validation("edge_constraint_violation", _, let details, _) = error else { return error.message }
        switch details?.object?["constraint"]?.string {
        case "cardinality":
            let object = details?.object
            let full = (object?["to_id"] ?? object?["from_id"])?.string
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
        #if DEBUG
        if let url = await SampleGallery.url(forBlob: hash) { return url }
        #endif
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
        default: Words.message(for: error)
        }
    }

    /// Where kept copies are, under this copy's temporary folder so another copy never clears them, and cleared when
    /// the library is disconnected or its downloads are removed.
    nonisolated static let keptFiles = AppPaths.temporary("Marfa Files")

    /// The file's title as a name on disk, with the extension its type has where the title has none, since the
    /// page, Open and the Finder all tell a file's kind by its extension.
    static func keptName(title: String?, mimeType: String?) -> String {
        let safe = FileName.fileSafe(title ?? "")
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

    func items(matching query: LibraryViewQuery) async throws -> [ItemID] {
        do {
            return try await MarfaEngine.asking { try await engine.reading.items(matching: MarfaMapping.listFilters(query)) }
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
        let limit: Int
        if case .items(_, _, let itemLimit) = target { limit = itemLimit } else { limit = SearchResults.limit }
        let rows: Rows<SearchHit>
        do {
            switch target {
            case .items(let itemQuery, let filter, _):
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
    func unsentWrites() async -> UnsentChanges? {
        await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.unsent(continuation)) { continuation.resume(returning: nil) }
        }
    }

    /// Closes, as `close()` does, only if every write not sent, once every write submitted before this call is
    /// in the queue, is one of `agreed`, deciding and closing in one step; nil agrees to whatever the copy
    /// holds. Otherwise it stays open and answers what is not sent.
    func close(agreeing agreed: UnsentChanges?) async -> CloseOutcome {
        let outcome = await withCheckedContinuation { continuation in
            if case .terminated = events.yield(.closeAgreeing(agreed, continuation)) {
                continuation.resume(returning: .closed)
            }
        }
        if outcome == .closed { events.finish() }
        return outcome
    }

    /// A copy that could not be given the sign-in is told closed or open by asking it, since only the package knows
    /// whether its store opened again.
    func use(_ server: Server) async throws -> SourceRole {
        do {
            try await copy.use(server)
        } catch {
            let closed: Bool
            do {
                _ = try await copy.status()
                closed = false
            } catch MarfaError.closed {
                closed = true
            } catch {
                closed = false
            }
            throw SourceUseFailure(cause: error, closed: closed)
        }
        // Another sign-in may reach the app's own settings where this one did not, or no longer reach them.
        Task { [engine] in await engine.sync.reconsiderSlice() }
        return copy.handle == .writer ? .writer : .reader
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
            throw SourceFailure(kind: .failed, message: Words.message(for: error))
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
