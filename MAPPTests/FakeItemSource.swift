import Foundation
import Synchronization
@testable import MAPP

/// A source the test drives: it tells its one reader the changes the test sends, answers bodies and searches
/// from what the test gives it, and keeps every write it is handed without applying any.
nonisolated final class FakeItemSource: ConnectedItemSource {
    nonisolated struct Submitted: Hashable, Sendable {
        let write: ItemWrite
        let id: WriteID
    }

    let offered = Mutex<SourceCapabilities>([.archive])
    let embeds: any EmbedResolver = MarfaEmbeds()
    let state = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport(queueRead: true))
    /// What `search` answers for each query; any other finds nothing.
    let hits = Mutex<[String: [ItemID]]>([:])
    let searches = Mutex(0)
    let searchFails = Mutex(false)
    let resolved = Mutex<[SyncAction]>([])
    let flushes = Mutex(0)
    let ended = Mutex<[ItemID]>([])
    private let held = Mutex<[ItemID: ItemBody]>([:])
    private let written = Mutex<[Submitted]>([])
    private let stream: AsyncStream<SourceChange>
    private let continuation: AsyncStream<SourceChange>.Continuation

    init() {
        (stream, continuation) = AsyncStream<SourceChange>.makeStream()
    }

    var capabilities: SourceCapabilities { offered.withLock { $0 } }
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

    func submit(_ write: ItemWrite, as id: WriteID) {
        written.withLock { $0.append(Submitted(write: write, id: id)) }
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

    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] {
        searches.withLock { $0 += 1 }
        if searchFails.withLock({ $0 }) { throw SourceFailure(kind: .failed, message: "The search could not be read.") }
        return hits.withLock { $0[text] ?? [] }
    }

    func endEditing(_ item: ItemID) {
        ended.withLock { $0.append(item) }
    }

    func flush() async {
        flushes.withLock { $0 += 1 }
    }

    func close() async {
        continuation.finish()
    }
}
