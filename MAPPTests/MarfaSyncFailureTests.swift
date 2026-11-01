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
}

/// What the sync shows when the app's own refresh fails: what the package says of the connection, and nothing of its
/// own. The fake copy has no server, so each test sends the update the package would send, as the copy's own stream
/// delivers it.
@Suite(.serialized, .hangLimit)
struct MarfaSyncFailureTests {
    private func open(failing errors: [MarfaError]) async throws -> (FakeCopy, MarfaSource, FailingRefresh, ChangeLog) {
        let server = FailingRefresh(failing: errors)
        let fake = WorkingCopy.fake(itemTypes: SampleLibrary.itemTypes, edgeTypes: SampleLibrary.edgeTypes)
        let (_, source, log) = try await scriptedSource(fake, refreshing: server)
        return (fake, source, server, log)
    }

    private func unavailable(_ state: ChangeLog.State) -> Int {
        state.changes.count { if case .unavailable = $0 { true } else { false } }
    }

    private func update(_ connection: CopyConnection) -> CopyUpdate {
        CopyUpdate(reread: .parts(Reread.Parts()), connection: connection)
    }

    @Test(arguments: [
        MarfaError.canceled(message: "the call was canceled"),
        MarfaError.server(status: 503, code: "unavailable", message: "The server is busy."),
        MarfaError.network(message: "offline"),
        MarfaError.keyChanging(message: "The key is changing."),
        MarfaError.copyExpired(reason: "read_view_changed", message: "The copy expired."),
    ])
    func aFailureThePackageHandlesIsNeitherShownNorReported(_ error: MarfaError) async throws {
        let (_, source, server, log) = try await open(failing: [error])
        source.refresh()
        try #require(await eventually { server.attempts >= 1 })
        await source.engine.sync.flush()
        #expect(unavailable(log.current) == 0, "\(error) was reported")
        if case .unavailable = source.connectionState { Issue.record("\(error) was shown as a fault") }
        await source.close()
    }

    /// The package sets the connection for a fault of the app's own call, so the sync shows nothing of its own.
    @Test func aFaultOfTheAppsCallIsShownWhenThePackageSaysSoAndNotBefore() async throws {
        let (fake, source, server, log) = try await open(failing: [.store(message: "the store failed")])
        source.refresh()
        try #require(await eventually { server.attempts >= 1 })
        await source.engine.sync.flush()
        #expect(unavailable(log.current) == 0, "the sync judged the call's error itself")
        #expect(source.connectionState == .online)

        fake.sendUpdate(update(.stopped(.store(message: "the store failed"))))
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(await waitForConnection(source) { if case .unavailable = $0 { true } else { false } })
        await source.close()
    }

    @Test func aStoppedLibraryStaysStoppedAcrossServerEventsUntilThePackageFollows() async throws {
        let (fake, source, _, log) = try await open(failing: [])
        let stopped = update(.stopped(.store(message: "the store failed")))
        fake.sendUpdate(stopped)
        _ = try #require(await log.wait { unavailable($0) == 1 })

        // The package says it again and a server event arrives: neither shows the library online or tells again.
        fake.sendUpdate(stopped)
        await source.hear(Change(origin: .server(event: "item.updated", cursor: "c"), itemId: nil, edgeId: nil))
        #expect(!(await waitForConnection(source) { $0 == .online }), "a stopped library was shown online")
        #expect(unavailable(log.current) == 1)

        fake.sendUpdate(update(.following))
        #expect(await waitForConnection(source) { $0 == .online })
        fake.sendUpdate(stopped)
        _ = try #require(await log.wait { unavailable($0) == 2 })
        await source.close()
    }

    /// A first fill that failed on a fault is the package's `.needsHydration(error)`: shown with the error, and
    /// with nothing hydrating, so Refresh is offered.
    @Test func aFailedFirstFillIsShownWithItsErrorAndOffersRefresh() async throws {
        let (fake, source, _, log) = try await open(failing: [])
        let refused = MarfaError.server(status: 400, code: "bad_request", message: "The server refused the fill.")
        fake.sendUpdate(update(.needsHydration(nil)))
        fake.sendUpdate(update(.needsHydration(refused)))
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(await waitForConnection(source) { $0 == .unavailable(message: refused.message) })
        #expect(await eventually { source.syncReport.phase == .current }, "Refresh is not offered")
        await source.close()
    }

    /// The package reports it as a stopped follow, or as a copy that needs hydration when its first fill met it.
    @Test(arguments: [false, true])
    func aServerThatIsAnotherOneIsToldWithTheChangesThatWillNotBeSent(duringTheFirstFill: Bool) async throws {
        let (fake, source, _, log) = try await open(failing: [])
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "Unsent", body: "Text")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "Unsent") != nil })
        let other = MarfaError.wrongServer(expected: "one", got: "two", message: "Another server.")
        fake.sendUpdate(update(duringTheFirstFill ? .needsHydration(other) : .stopped(other)))
        #expect(await waitForConnection(source) { $0 == .unavailable(message: Words.otherServer(unsent: 1)) })
        #expect(Words.otherServer(unsent: 1).contains("1 change"))
        await source.close()
    }

    /// A key the server ended is the package's `.keyRefused`: shown as that, told once, and waiting for another key.
    @Test func aKeyTheServerEndedIsShownRefusedAndToldOnce() async throws {
        let (fake, source, _, log) = try await open(failing: [])
        let ended = MarfaError.copyExpired(reason: "credential_ended", message: "the key ended")
        for _ in 0..<3 { fake.sendUpdate(update(.keyRefused(ended))) }
        #expect(await waitForConnection(source) { $0 == .keyRefused })
        try #require(await eventually { log.current.changes.contains { if case .unavailable = $0 { true } else { false } } })
        try await Task.sleep(for: .milliseconds(200))
        #expect(unavailable(log.current) == 1)
        await source.close()
    }

    @Test func aKeyTheKeychainWouldNotGiveIsNeitherMissingNorRefused() async throws {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemorySignIns([connection.address: "unused"])
        keys.makeUnreadable(connection)
        let root = URL.temporaryDirectory.appending(path: "MarfaSyncFailureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        do {
            _ = try await MarfaSource.open(connection, signIns: keys, location: MarfaStoreLocation(root: root))
            Issue.record("opened a copy without its key")
        } catch let failure as SourceFailure {
            #expect(failure.kind == .failed)
            #expect(failure.message == Words.signInUnreadable)
        }
    }
}
