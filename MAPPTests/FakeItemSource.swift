import Foundation
import Synchronization
@testable import MAPP

/// Embeds that keep what they are asked to attach, as the file's name inside the text the page writes for it, and
/// fail where the test says.
nonisolated final class FakeEmbeds: EmbedResolver {
    let attached = Mutex<[(file: String, item: ItemID)]>([])
    let failure = Mutex<SourceFailure?>(nil)

    func attach(_ files: [URL], to item: ItemID) async throws -> [Embed] {
        if let failure = failure.withLock({ $0 }) { throw failure }
        return files.map { file in
            attached.withLock { $0.append((file.lastPathComponent, item)) }
            return Embed(link: file.lastPathComponent, name: file.lastPathComponent)
        }
    }

    let added = Mutex<[(file: String, data: Data, title: String?, tier: Tier?, parent: ItemID?)]>([])

    func addFile(_ file: URL, title: String?, tier: Tier?, parent: ItemID?) async throws -> ItemID {
        if let failure = failure.withLock({ $0 }) { throw failure }
        let data = try Data(contentsOf: file)
        added.withLock { $0.append((file.lastPathComponent, data, title, tier, parent)) }
        return ItemID.mint()
    }
}

/// A source the test drives: it tells its one reader the changes the test sends, answers bodies and searches
/// from what the test gives it, and keeps every write it is handed without applying any.
nonisolated final class FakeItemSource: ItemSource {
    nonisolated struct Submitted: Hashable, Sendable {
        let write: ItemWrite
        let id: WriteID
    }

    let attaching = FakeEmbeds()
    var embeds: any EmbedResolver { attaching }
    let state = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport(queueRead: true))
    /// What `search` answers for each query; any other finds nothing.
    let hits = Mutex<[String: [ItemID]]>([:])
    let searches = Mutex(0)
    let searchFails = Mutex(false)
    /// What a search answers beside its hits, and where it was asked to look.
    let excerpts = Mutex<[String: [ItemID: SearchExcerpt]]>([:])
    let searchIncomplete = Mutex(false)
    let searchCapped = Mutex(false)
    let targets = Mutex<[SearchTarget]>([])
    /// What `items(inView:)` answers for each view; any other lists nothing.
    let viewMembers = Mutex<[ItemID: [ItemID]]>([:])
    let viewReads = Mutex(0)
    let viewFails = Mutex(false)
    let resolved = Mutex<[SyncAction]>([])
    let queues = Mutex(0)
    /// While set, `queueSubmitted` waits, as an engine busy with a long step would.
    let queuing = Mutex(false)
    let isClosed = Mutex(false)
    private let held = Mutex<[ItemID: ItemBody]>([:])
    private let written = Mutex<[Submitted]>([])
    private let stream: AsyncStream<SourceChange>
    private let continuation: AsyncStream<SourceChange>.Continuation

    init() {
        (stream, continuation) = AsyncStream<SourceChange>.makeStream()
    }

    var submitted: [Submitted] { written.withLock { $0 } }
    var writes: [ItemWrite] { submitted.map(\.write) }

    func send(_ change: SourceChange) {
        continuation.yield(change)
    }

    func setBody(_ text: String, of id: ItemID, version: Int64 = 1) {
        held.withLock { $0[id] = ItemBody(id: id, text: text, version: ItemVersion(version)) }
    }

    func clearWrites() {
        written.withLock { $0 = [] }
    }

    var connectionState: MarfaConnectionState { state.value }
    func connectionStates() -> AsyncStream<MarfaConnectionState> { state.values() }
    var syncReport: SyncReport { report.value }
    func syncReports() -> AsyncStream<SyncReport> { report.values() }

    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool {
        resolved.withLock { $0.append(action) }
        return true
    }

    func changes() -> AsyncStream<SourceChange> { stream }

    @discardableResult
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool {
        guard !isClosed.withLock({ $0 }) else { return false }
        written.withLock { $0.append(Submitted(write: write, id: id)) }
        return true
    }

    func body(of item: ItemID) async throws -> ItemBody {
        guard let body = held.withLock({ $0[item] }) else { throw SourceFailure(kind: .missing, message: "No text.") }
        return body
    }

    func bodies(of items: Set<ItemID>) async throws -> [ItemBody] {
        held.withLock { held in items.compactMap { held[$0] } }
    }

    func fileURL(of item: ItemID) async throws -> URL {
        URL(filePath: "/dev/null")
    }

    func search(_ text: String, in target: SearchTarget) async throws -> SourceSearch {
        searches.withLock { $0 += 1 }
        targets.withLock { $0.append(target) }
        if searchFails.withLock({ $0 }) { throw SourceFailure(kind: .failed, message: "The search could not be read.") }
        return SourceSearch(
            hits: hits.withLock { $0[text] ?? [] }, excerpts: excerpts.withLock { $0[text] ?? [:] },
            isIncomplete: searchIncomplete.withLock { $0 }, isCapped: searchCapped.withLock { $0 })
    }

    /// The views the fake server holds. A change based on another version than the one held is refused as a
    /// conflict, as the server refuses one to a setting changed since.
    let savedViews = Mutex<[ItemID: LibraryView]>([:])
    /// What every view write throws while set, as a server that cannot be reached would.
    let viewFailure = Mutex<ViewWriteFailure?>(nil)
    /// The idempotency key of each view write, in order.
    let viewKeys = Mutex<[String]>([])

    func createView(_ settings: LibraryViewSettings, idempotencyKey: String) async throws -> LibraryView {
        try viewWrite(idempotencyKey)
        let view = LibraryView(
            id: ItemID.mint(), title: settings.title, version: 1, query: settings.query, sort: settings.sort, group: settings.group)
        heldViews { $0[view.id] = view }
        return view
    }

    func changeView(_ view: ItemID, _ change: LibraryViewChange, baseVersion: Int64, idempotencyKey: String) async throws -> LibraryView {
        try viewWrite(idempotencyKey)
        guard var held = savedViews.withLock({ $0[view] }) else {
            throw ViewWriteFailure(kind: .gone, message: "The server has no such view.")
        }
        guard held.version == baseVersion else {
            throw ViewWriteFailure(kind: .conflict, message: "The view changed since.")
        }
        if let title = change.title { held.title = title }
        if let query = change.query { held.query = query }
        if let sort = change.sort { held.sort = sort }
        switch change.group {
        case .set(let group): held.group = group
        case .clear: held.group = nil
        case nil: break
        }
        held.version += 1
        heldViews { $0[view] = held }
        return held
    }

    func deleteView(_ view: ItemID, idempotencyKey: String) async throws {
        try viewWrite(idempotencyKey)
        guard savedViews.withLock({ $0[view] }) != nil else {
            throw ViewWriteFailure(kind: .gone, message: "The server has no such view.")
        }
        heldViews { $0[view] = nil }
    }

    private func viewWrite(_ key: String) throws {
        viewKeys.withLock { $0.append(key) }
        if let failure = viewFailure.withLock({ $0 }) { throw failure }
    }

    /// Tells the reader the views, as the copy's own word on a write does.
    private func heldViews(_ change: (inout [ItemID: LibraryView]) -> Void) {
        let views = savedViews.withLock { views in
            change(&views)
            return LibraryView.ordered(Array(views.values))
        }
        send(.views(views))
    }

    func items(inView view: ItemID) async throws -> [ItemID] {
        viewReads.withLock { $0 += 1 }
        if viewFails.withLock({ $0 }) { throw SourceFailure(kind: .failed, message: "The view asks for a type the copy does not hold.") }
        return viewMembers.withLock { $0[view] ?? [] }
    }

    func queueSubmitted() async {
        while queuing.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
        queues.withLock { $0 += 1 }
    }

    func close() async {
        isClosed.withLock { $0 = true }
        continuation.finish()
    }

    let refreshes = Mutex(0)
    func refresh() { refreshes.withLock { $0 += 1 } }
    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck { .accepted }
    func unsentWrites() async -> UnsentWrites? { nil }

    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome {
        await close()
        return .closed
    }
}
