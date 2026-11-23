import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

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
        MarfaError.server(status: 503, code: "unavailable", message: "The server is busy.", details: nil, server: nil),
        MarfaError.network(message: "offline"),
        MarfaError.keyChanging(message: "The key is changing."),
        MarfaError.copyExpired(reason: "read_view_changed", message: "The copy expired.", server: nil),
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
        let refused = MarfaError.server(status: 400, code: "bad_request", message: "The server refused the fill.", details: nil, server: nil)
        fake.sendUpdate(update(.needsHydration(nil)))
        fake.sendUpdate(update(.needsHydration(refused)))
        _ = try #require(await log.wait { unavailable($0) == 1 })
        #expect(Words.message(for: refused) == Words.syncFailed, "the server's text is never shown")
        #expect(await waitForConnection(source) { $0 == .unavailable(message: Words.syncFailed) })
        #expect(await eventually { source.syncReport.phase == .current }, "Refresh is not offered")
        await source.close()
    }

    /// A refused key and a contract mismatch each have words of their own for every caller of `Words.message(for:)`.
    @Test func aRefusedKeyAndAContractMismatchAreToldInTheAppsWords() {
        let raw = "https://marfa.example.test refused"
        let ended = "The server has ended MAPP’s sign-in. Sign in again in Settings."
        let refusals = [
            MarfaError.signedOut(origin: "https://marfa.example.test", message: raw),
            .unauthorized(code: "unauthorized", message: raw, server: nil),
            .copyExpired(reason: "credential_ended", message: raw, server: nil),
        ]
        for error in refusals { #expect(Words.message(for: error) == ended) }
        #expect(Words.message(for: .copyExpired(reason: "reach_changed", message: raw, server: nil)) == Words.syncFailed)

        let unsent = MarfaError.contractMismatch(served: "9", expected: 1, status: 412, writeSent: false, message: raw, server: nil)
        let sent = MarfaError.contractMismatch(served: "9", expected: 1, status: nil, writeSent: true, message: raw, server: nil)
        #expect(Words.message(for: unsent) == "This version of MAPP and the server use different versions of Marfa, so the server didn’t make the change. Update MAPP or the server, then try again.")
        #expect(Words.message(for: sent) == "This version of MAPP and the server use different versions of Marfa, and the change may already have been made. Update MAPP or the server, then check the change.")
        #expect(!Words.message(for: sent).contains("example.test"))
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

    /// The package reports a server too old as a stopped follow, or as a copy whose first fill met it: each is shown
    /// in the app's words, with none of the server's text, and the sidebar stops saying it is syncing.
    @Test(arguments: [false, true])
    func aServerTooOldIsToldInTheAppsWordsAndNotTheServersText(duringTheFirstFill: Bool) async throws {
        let raw = "Copy streams require exactly edges=all&copy=1"
        let tooOld = MarfaError.serverTooOld(served: "0.0.77", oldest: "0.0.78", message: raw)
        let (fake, source, _, log) = try await open(failing: [])
        fake.sendUpdate(update(duringTheFirstFill ? .needsHydration(tooOld) : .stopped(tooOld)))
        let words = "This server runs Marfa 0.0.77. Update the server to Marfa 0.0.78 or later to use this app."
        #expect(Words.message(for: tooOld) == words)
        let state = try #require(await log.wait { unavailable($0) == 1 })
        let told = state.changes.compactMap { change -> String? in
            if case .unavailable(let failure) = change { failure.message } else { nil }
        }
        #expect(told == [words])
        #expect(await waitForConnection(source) { $0 == .unavailable(message: words) })
        let foot = try #require(SyncFootLine(state: source.connectionState, report: source.syncReport, lastSynced: nil, now: Date()))
        #expect(foot.kind == .failed, "the sidebar kept syncing")
        #expect(foot.help == words)
        #expect(ConnectionStatus(source.connectionState).detail?.hasSuffix(words) == true)
        await source.close()
    }

    /// withmarfa/mapp#454: a first hydration that is filling and then stops for a server too old leaves the Settings pages
    /// no progress to show, though the package's last fill is still on the report.
    @Test func aFirstFillThatStopsForAServerTooOldLeavesSettingsNoProgress() async throws {
        let tooOld = MarfaError.serverTooOld(served: "0.0.77", oldest: "0.0.78", message: "Copy streams require exactly edges=all&copy=1")
        let (fake, source, _, _) = try await open(failing: [])
        fake.sendUpdate(CopyUpdate(
            reread: .parts(Reread.Parts()), connection: .needsHydration(nil), fill: FillProgress(listed: 0, expected: 5000)))
        #expect(
            await eventually { FillWording.shows(source.syncReport.fill, in: source.connectionState) },
            "the fill was never shown, so the test would pass for the wrong reason")
        fake.sendUpdate(update(.needsHydration(tooOld)))
        #expect(await waitForConnection(source) { if case .unavailable = $0 { true } else { false } })
        #expect(!FillWording.shows(source.syncReport.fill, in: source.connectionState), "Settings kept saying it was downloading")
        await source.close()
    }

    /// A renewal the server or the app's renewer could not finish, with the sign-in kept, is the package's
    /// `renewalRefused`: each reason has its own words, and none of the package's text.
    @Test(arguments: [
        (RenewalRefusalReason.refused, "MAPP couldn’t renew its sign-in with the server, because the server didn’t accept the renewal. Try again later. If it keeps happening, check the server’s address in Settings, or sign in again."),
        (RenewalRefusalReason.redirected, "MAPP couldn’t renew its sign-in because the server redirected the request. Check the server address in Settings, then try again. If this keeps happening, sign in again."),
        (RenewalRefusalReason.unreadable, "MAPP couldn’t renew its sign-in with the server, because it couldn’t read the server’s answer. Try again later. If it keeps happening, check the server’s address in Settings, or sign in again."),
    ])
    func aRefusedRenewalIsToldInTheAppsWordsForItsReason(reason: RenewalRefusalReason, words: String) {
        let raw = "https://marfa.example.test refused to renew the sign-in: the server answered 301"
        let error = MarfaError.renewalRefused(reason: reason, message: raw)
        #expect(Words.message(for: error) == words)
        #expect(!Words.message(for: error).contains("301"), "the package's text is never shown")
        #expect(!Words.message(for: error).contains("example.test"), "the address in the package's text is never shown")
        #expect(Set(RenewalRefusalReason.allCases.map { Words.message(for: .renewalRefused(reason: $0, message: raw)) }).count == RenewalRefusalReason.allCases.count)
    }

    /// A stopped follow that met a refused renewal is an unavailable library in those words: not signed out, and not
    /// offline, since the server answered and the sign-in stands.
    @Test(arguments: RenewalRefusalReason.allCases)
    func aFollowStoppedOnARefusedRenewalIsShownUnavailableInTheAppsWords(reason: RenewalRefusalReason) async throws {
        let error = MarfaError.renewalRefused(reason: reason, message: "the server answered 301")
        let (fake, source, _, log) = try await open(failing: [])
        fake.sendUpdate(update(.stopped(error)))
        let words = Words.message(for: error)
        #expect(words != Words.syncFailed)
        let state = try #require(await log.wait { unavailable($0) == 1 })
        let told = state.changes.compactMap { change -> String? in
            if case .unavailable(let failure) = change { failure.message } else { nil }
        }
        #expect(told == [words])
        #expect(await waitForConnection(source) { $0 == .unavailable(message: words) })
        #expect(source.connectionState != .keyRefused)
        let foot = try #require(SyncFootLine(state: source.connectionState, report: source.syncReport, lastSynced: nil, now: Date()))
        #expect(foot.kind == .failed)
        #expect(foot.help == words)
        await source.close()
    }

    /// A key the server ended is the package's `.keyRefused`: shown as that, told once, and waiting for another key.
    @Test func aKeyTheServerEndedIsShownRefusedAndToldOnce() async throws {
        let (fake, source, _, log) = try await open(failing: [])
        let ended = MarfaError.copyExpired(reason: "credential_ended", message: "the key ended", server: nil)
        for _ in 0..<3 { fake.sendUpdate(update(.keyRefused(ended))) }
        #expect(await waitForConnection(source) { $0 == .keyRefused })
        try #require(await eventually { log.current.changes.contains { if case .unavailable = $0 { true } else { false } } })
        try await Task.sleep(for: .milliseconds(200))
        #expect(unavailable(log.current) == 1)
        await source.close()
    }

    @Test func aKeyTheKeychainWouldNotGiveIsNeitherMissingNorRefused() async throws {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = ScriptedSignIns([connection.address: "unused"])
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
