import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MAPP

/// A refresh whose network steps fail with an error the test chooses, counting how often they were tried.
private nonisolated final class FailingRefresh: MarfaRefreshing {
    private let tries = Mutex(0)
    private let failures = Mutex<[MarfaError]>([])

    init(failing errors: [MarfaError]) { failures.withLock { $0 = errors } }

    var attempts: Int { tries.withLock { $0 } }

    private func attempt() throws {
        tries.withLock { $0 += 1 }
        if let error = failures.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) { throw error }
    }

    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .never)
    }

    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        try attempt()
        return HydrateReport(types: types, tier: tier, edgeTypes: edgeTypes, items: 0, edges: 0, pages: 1, pagesTotal: 1,
                             resumed: false, restarted: nil, inPlace: false, cursor: "done")
    }

    func catchUp() async throws { try attempt() }
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
    func updates() -> AsyncStream<CopyUpdate>? { quietUpdates() }
}

/// What the sync shows when the app's own refresh fails: the package retries what asking again may clear, so only
/// a fault it cannot clear is shown, and a canceled call is not a fault.
@Suite(.serialized, .hangLimit)
struct MarfaSyncFailureTests {
    private func open(failing errors: [MarfaError]) async throws -> (MarfaSource, FailingRefresh, ChangeLog, TemporaryMarfaCopy) {
        let store = try TemporaryMarfaCopy()
        // A server that refuses every connection, as the app's own copies have one to drain to.
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let copy = try await WorkingCopy.open(
            store: store.root.appending(path: "store.sqlite"), server: connection.server(key: "unused"))
        let server = FailingRefresh(failing: errors)
        let source = MarfaSource(copy: copy, connection: connection, refreshing: server)
        let log = ChangeLog(source)
        source.events.yield(.paint)
        _ = try #require(await log.wait { $0.snapshot != nil })
        return (source, server, log, store)
    }

    private func unavailable(_ state: ChangeLog.State) -> Int {
        state.changes.count { if case .unavailable = $0 { true } else { false } }
    }

    @Test(arguments: [
        MarfaError.canceled(message: "the call was canceled"),
        MarfaError.server(status: 503, code: "unavailable", message: "The server is busy."),
        MarfaError.network(message: "offline"),
        MarfaError.keyChanging(message: "The key is changing."),
        MarfaError.copyExpired(reason: "read_view_changed", message: "The copy expired."),
    ])
    func aFailureThePackageHandlesIsNeitherShownNorReported(_ error: MarfaError) async throws {
        let (source, server, log, store) = try await open(failing: [error])
        defer { store.remove() }
        source.refresh()
        try #require(await eventually { server.attempts >= 1 })
        await source.engine.sync.flush()
        #expect(unavailable(log.current) == 0, "\(error) was reported")
        if case .unavailable = source.connectionState { Issue.record("\(error) was shown as a fault") }
        await source.close()
    }

    @Test func aFaultAskingAgainMayNotClearIsShownOnceAndStaysUntilARefreshSucceeds() async throws {
        let (source, server, log, store) = try await open(failing: [.store(message: "the store failed")])
        defer { store.remove() }
        source.refresh()
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(await waitForConnection(source) { if case .unavailable = $0 { true } else { false } })

        // A refresh is offered while stopped, and its success is what clears the fault.
        source.refresh()
        try #require(await eventually { server.attempts >= 2 })
        await source.engine.sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .following))
        #expect(await waitForConnection(source) { $0 == .online })
        #expect(unavailable(log.current) == 1)
        await source.close()
    }

    @Test func aServerThatIsAnotherOneIsToldWithTheChangesThatWillNotBeSent() async throws {
        let (source, _, log, store) = try await open(failing: [])
        defer { store.remove() }
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Unsent", body: "Text")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "Unsent") != nil })
        let other = MarfaError.wrongServer(expected: "one", got: "two", message: "Another server.")
        await source.engine.sync.take(CopyUpdate(reread: .parts(Reread.Parts()), connection: .stopped(other)))
        #expect(await waitForConnection(source) { $0 == .unavailable(message: Words.otherServer(unsent: 1)) })
        #expect(Words.otherServer(unsent: 1).contains("1 change"))
        await source.close()
    }

    @Test func aKeyTheKeychainWouldNotGiveIsNeitherMissingNorRefused() async throws {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection.address: "unused"])
        keys.makeUnreadable(connection.address)
        let root = URL.temporaryDirectory.appending(path: "MarfaSyncFailureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await MarfaSource.open(connection, keys: keys, location: MarfaStoreLocation(root: root))
            Issue.record("opened a copy without its key")
        } catch let failure as SourceFailure {
            #expect(failure.kind == .failed)
            #expect(failure.message == Words.keyUnreadable)
        }
    }
}
