import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// A library that answers nothing of its own: the test sets its connection and report, and reads what it was
/// asked to do.
nonisolated final class FakeMarfaSource: MarfaHostedSource {
    let connection: MarfaConnection
    let capabilities: SourceCapabilities = []
    let embeds: any EmbedResolver = MarfaEmbeds()
    let state = Latest(MarfaConnectionState.connecting)
    let report = Latest(SyncReport(queueRead: true))
    let refusesKeys = Mutex(false)
    /// What the server makes of each key tried; any other is accepted.
    let verdicts = Mutex<[String: MarfaSync.KeyCheck]>([:])
    private let asked = Mutex<[String]>([])

    init(connection: MarfaConnection) {
        self.connection = connection
    }

    var calls: [String] { asked.withLock { $0 } }

    private func record(_ call: String) {
        asked.withLock { $0.append(call) }
    }

    var connectionState: MarfaConnectionState { state.value }
    func connectionStates() -> AsyncStream<MarfaConnectionState> { state.values() }
    func refresh() { record("refresh") }

    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck {
        record("tryKey \(key)")
        if refusesKeys.withLock({ $0 }) { throw SourceFailure(kind: .missing, message: "The copy closed.") }
        return verdicts.withLock { $0[key] } ?? .accepted
    }

    func settledReport() async -> SyncReport { report.value }

    func close(unlessUnsentExceeds limit: Int) async -> SyncReport? {
        let report = report.value
        if (report.queueRead ? report.changesNotSent : .max) > limit { return report }
        record("close")
        return nil
    }

    var syncReport: SyncReport { report.value }
    func syncReports() -> AsyncStream<SyncReport> { report.values() }
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }

    func changes() -> AsyncStream<SourceChange> { AsyncStream { $0.finish() } }
    func submit(_ write: ItemWrite, as id: WriteID) {}
    func body(of item: ItemID) async throws -> ItemBody { throw SourceFailure(kind: .missing, message: "") }
    func fileURL(of item: ItemID) async throws -> URL { throw SourceFailure(kind: .missing, message: "") }
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] { [] }
    func endEditing(_ item: ItemID) {}
    func flush() async {}
    func close() async { record("close") }
}

/// Opens a fake library for each address, as `MarfaSource.open` would: refused without a key, and making the
/// copy's directory.
nonisolated final class FakeServers: Sendable {
    let failure = Mutex<SourceFailure?>(nil)
    /// While set, an open waits, as one behind a keychain prompt would.
    let slow = Mutex(false)
    let opening = Mutex(false)
    private let made = Mutex<[FakeMarfaSource]>([])

    var opened: [FakeMarfaSource] { made.withLock { $0 } }
    var last: FakeMarfaSource? { opened.last }

    var opener: MarfaHost.Opener {
        { connection, keys, location in
            if let failure = self.failure.withLock({ $0 }) { throw failure }
            self.opening.withLock { $0 = true }
            while self.slow.withLock({ $0 }) { try await Task.sleep(for: .milliseconds(10)) }
            guard try keys.key(for: connection) != nil else {
                throw SourceFailure(kind: .denied, message: "There’s no key for this Marfa server.")
            }
            try FileManager.default.createDirectory(at: location.directory(for: connection), withIntermediateDirectories: true)
            let source = FakeMarfaSource(connection: connection)
            self.made.withLock { $0.append(source) }
            return source
        }
    }
}

/// Keys held in memory, whose delete can be made to fail as a keychain's can.
nonisolated final class TestKeyStore: KeyStore {
    private let keys = Mutex<[MarfaConnection: String]>([:])
    let failsDelete = Mutex(false)

    func save(_ key: String, for connection: MarfaConnection) {
        keys.withLock { $0[connection] = key }
    }

    func key(for connection: MarfaConnection) -> String? {
        keys.withLock { $0[connection] }
    }

    func delete(for connection: MarfaConnection) throws {
        if failsDelete.withLock({ $0 }) { throw SourceFailure(kind: .denied, message: "The keychain refused.") }
        _ = keys.withLock { $0.removeValue(forKey: connection) }
    }
}

/// A host on its own defaults, key store and store directory, all removed when the test ends.
@MainActor final class HostBench {
    let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    let suite = "MarfaHostTests-\(UUID().uuidString)"
    let defaults: UserDefaults
    let keys = TestKeyStore()
    let location: MarfaStoreLocation
    let servers = FakeServers()

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
        location = try MarfaStoreLocation(root: root)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func host(opener: MarfaHost.Opener? = nil) -> MarfaHost {
        MarfaHost(defaults: defaults, keys: keys, location: location, opener: opener ?? servers.opener)
    }

    var savedAddress: String? { defaults.string(forKey: "MarfaAddress") }

    func hasCopy(_ connection: MarfaConnection) -> Bool {
        FileManager.default.fileExists(atPath: location.directory(for: connection).path)
    }
}

@MainActor func eventually(_ timeout: Duration = .seconds(10), _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while clock.now < end {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

@MainActor struct MarfaHostTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func expect(_ problem: MarfaHost.Problem, _ work: () async throws(MarfaHost.Problem) -> Void) async {
        do {
            try await work()
            Issue.record("expected \(problem)")
        } catch {
            #expect(error == problem)
        }
    }

    @Test func connectingKeepsTheAddressAndKeyAndPaintsBeforeTheServer() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: " HTTP://First.test:8210/ ", key: " key-1 ")
        #expect(host.connection == first)
        #expect(bench.savedAddress == "http://first.test:8210")
        #expect(bench.keys.key(for: first) == "key-1")
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        source.state.set(.online)
        #expect(await eventually { host.state == .online })
        source.state.set(.offline(reason: "network: refused"))
        #expect(await eventually { host.state == .offline(reason: "network: refused") })
        source.state.set(.stopped(code: "store", message: "The store is damaged."))
        #expect(await eventually { host.state == .unavailable(message: "The store is damaged.") })
    }

    @Test func aBadAddressOrAMissingKeyIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        for address in ["not a server", "ftp://first.test", "http://user:pass@first.test", ""] {
            await expect(.notAServer) { () throws(MarfaHost.Problem) in try await host.connect(address: address, key: "k") }
        }
        await expect(.noKey) { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test", key: "  ") }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func aCopyThatCannotBeOpenedIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }
        await expect(.unavailable(message: "The store is damaged.")) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.keys.key(for: first) == nil)
    }

    @Test func aRefusedKeyIsReplacedInPlace() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "wrong")
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })

        try await host.replaceKey("right")
        #expect(bench.keys.key(for: first) == "right")
        #expect(source.calls == ["refresh", "tryKey right"])
        #expect(bench.servers.opened.count == 1)
        source.state.set(.online)
        #expect(await eventually { host.state == .online })

        // Connecting to the same address again only changes the key.
        try await host.connect(address: "http://first.test:8210/", key: "again")
        #expect(source.calls.last == "tryKey again")
        #expect(bench.servers.opened.count == 1)
    }

    /// The new key was never answered for, so the copy opens again with the old one, and the person is told.
    @Test func aCopyThatCannotTakeTheKeyOpensAgainWithTheOldOne() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.refusesKeys.withLock { $0 = true }
        await expect(.unavailable(message: "The copy closed.")) { () throws(MarfaHost.Problem) in try await host.replaceKey("new") }
        #expect(source.calls == ["refresh", "tryKey new", "close"])
        #expect(bench.servers.opened.count == 2)
        #expect(host.source === bench.servers.last)
        #expect(bench.keys.key(for: first) == "old")
    }

    @Test func aKeyTheServerRefusesIsNotKept() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.verdicts.withLock { $0["typo"] = .refused }
        await expect(.keyRefused) { () throws(MarfaHost.Problem) in try await host.replaceKey("typo") }
        #expect(bench.keys.key(for: first) == "good")
        #expect(source.calls == ["refresh", "tryKey typo", "tryKey good"])
    }

    @Test func aKeyTheServerCannotBeAskedAboutIsKeptOnlyInPlaceOfARefusedOne() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.verdicts.withLock { $0["later"] = .unanswered("network: down") }
        await expect(.serverUnreachable(reason: "network: down")) { () throws(MarfaHost.Problem) in
            try await host.replaceKey("later")
        }
        #expect(bench.keys.key(for: first) == "good")
        #expect(source.calls.last == "tryKey good")

        source.state.set(.keyRefused)
        try await host.replaceKey("later")
        #expect(bench.keys.key(for: first) == "later")
        #expect(source.calls.last == "tryKey later")
    }

    @Test func leavingWithWritesWaitingNeedsAChoice() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })

        await expect(.changesWaiting(2)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == first)
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        try await host.disconnect(.keepCopy)
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(host.source == nil)
        #expect(host.report == SyncReport())
        #expect(source.calls.last == "close")
        #expect(bench.savedAddress == nil)
        #expect(bench.keys.key(for: first) == nil)
        #expect(bench.hasCopy(first))

        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        try await host.disconnect(.discardCopy)
        #expect(!bench.hasCopy(first))
    }

    @Test func refusedWritesCountAsWaiting() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let refused = SyncProblemEntry(
            id: .write("w"), itemID: ItemID("i"), kind: .refused, change: .create, reason: SyncProblem(code: "x"),
            content: SyncContent(title: "Kept"), actions: [.discard])
        try #require(bench.servers.last).report.set(SyncReport(problems: [refused], queueRead: true))
        #expect(await eventually { host.report.problems == [refused] })
        await expect(.changesWaiting(1)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func leavingWithNothingWaitingRemovesTheCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(host.waitingChanges == 0)
        try await host.disconnect()
        #expect(!bench.hasCopy(first))
        #expect(bench.keys.key(for: first) == nil)
    }

    /// Until the copy's queue is read, nothing is known of what waits in it.
    @Test func aCopyNotYetReadNeedsAChoice() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport())
        #expect(await eventually { host.waitingChanges == nil })
        await expect(.changesWaiting(nil)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func anotherAddressWarnsAndKeepsTheFirstUntilTheSecondOpens() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        old.report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { host.waitingChanges == 1 })

        await expect(.changesWaiting(1)) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        await expect(.changesWaiting(1)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://second.test:8210", key: "two")
        }
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "No room.") }
        await expect(.unavailable(message: "No room.")) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .keepCopy)
        }
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(bench.keys.key(for: first) == "one")
        #expect(bench.keys.key(for: second) == nil)

        bench.servers.failure.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .keepCopy)
        #expect(host.connection == second)
        #expect(host.source === bench.servers.last)
        #expect(bench.savedAddress == "http://second.test:8210")
        #expect(bench.keys.key(for: first) == nil)
        #expect(bench.keys.key(for: second) == "two")
        #expect(old.calls.last == "close")
        #expect(bench.hasCopy(first))
    }

    @Test func aLaunchReconnectsFromTheCopyWithoutWaitingOnTheServer() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.connection == first)
        // The fake never answers, so a launch that waited on the server would not have returned.
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        await host.launch()
        #expect(bench.servers.opened.count == 1)
    }

    @Test func aLaunchWithoutAKeyAsksForOne() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let host = bench.host()
        await host.launch()
        #expect(host.state == .keyRefused)
        #expect(host.connection == first)
        #expect(host.source == nil)
        try await host.replaceKey("k")
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)
    }

    @Test func aLaunchWithNothingSavedDoesNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        await host.launch()
        #expect(host.state == .disconnected)
        #expect(bench.servers.opened.isEmpty)
        await expect(.notConnected) { () throws(MarfaHost.Problem) in try await host.replaceKey("k") }
    }
}

/// Findings from review, each first seen failing on the code before its fix.
@MainActor struct MarfaHostReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    /// Writes made while the new address's copy opens, slowly, are not discarded with the old copy.
    @Test func writesMadeWhileAnotherAddressOpensKeepTheOldCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.servers.opening.withLock { $0 = false }
        bench.servers.slow.withLock { $0 = true }
        let change = Task { try await host.changeAddress(to: "http://second.test:8210", key: "two") }
        #expect(await eventually { bench.servers.opening.withLock { $0 } })
        old.report.set(SyncReport(waiting: 1, queueRead: true))
        try await Task.sleep(for: .milliseconds(100))
        bench.servers.slow.withLock { $0 = false }
        let result = await change.result
        guard case .failure(let error) = result else {
            Issue.record("left the old copy with a write waiting")
            return
        }
        #expect(error as? MarfaHost.Problem == .changesWaiting(1))
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(bench.hasCopy(first))
        #expect(bench.keys.key(for: first) == "one")
        #expect(bench.keys.key(for: second) == nil)
        #expect(!old.calls.contains("close"))
        #expect(bench.servers.opened.count == 2)
        #expect(bench.servers.last?.calls.last == "close")
    }

    @Test func aKeyThatCannotBeRemovedIsReported() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        bench.keys.failsDelete.withLock { $0 = true }
        do {
            try await host.disconnect(.keepCopy)
            Issue.record("said the key was removed")
        } catch {}
        #expect(bench.keys.key(for: first) == "k")
    }

    /// A copy the person chose to discard, which could not be removed, is never opened again as it was.
    @Test func aCopyThatCannotBeRemovedIsReportedAndNotResumed() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bench.root.path)
        do {
            try await host.disconnect(.discardCopy)
            Issue.record("said the copy was removed")
        } catch {}
        #expect(bench.hasCopy(first))
        do {
            try await host.connect(address: "http://first.test:8210", key: "k")
            Issue.record("opened a copy the person discarded")
        } catch {}
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bench.root.path)
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(host.source != nil)
        #expect(bench.servers.opened.count == 2)
    }
}

/// The host over a real copy whose server refuses every connection.
@MainActor @Suite(.serialized)
struct MarfaHostOfflineTests {
    private let address = "http://127.0.0.1:9"

    @Test(.timeLimit(.minutes(1)))
    func aKeptCopyGoesOnWhereItWasLeft() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST kept", body: "Waiting")), as: WriteID())
        #expect(await eventually { host.report.waiting == 1 })
        #expect(host.report.oldestWaiting != nil)

        do {
            try await host.disconnect()
            Issue.record("left a copy with a write waiting")
        } catch {
            #expect(error == .changesWaiting(1))
        }
        try await host.disconnect(.keepCopy)
        #expect(bench.hasCopy(connection))

        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.waiting == 1 })
        let log = ChangeLog(try #require(host.source as? MarfaSource))
        #expect(await log.wait { $0.item(titled: "MAPPTEST kept")?.sync == .waiting(writes: 1) } != nil)

        try await host.disconnect(.discardCopy)
        #expect(!bench.hasCopy(connection))
    }

    /// A key the server ends expires the copy; it waits for another key rather than hydrating again at once.
    @Test(.timeLimit(.minutes(1)))
    func anEndedKeyWaitsForAnother() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        try await host.connect(address: address, key: "ended")
        let source = try #require(host.source as? MarfaSource)
        #expect(await eventually { if case .offline = host.state { true } else { false } })
        let ended = MarfaError.copyExpired(reason: "credential_ended", message: "the key ended")
        source.events.yield(.change(Change(origin: .stopped(ended), itemId: nil, edgeId: nil)))
        #expect(await eventually { host.state == .keyRefused })
        try await Task.sleep(for: .seconds(1))
        #expect(host.state == .keyRefused)

        try await host.replaceKey("given")
        #expect(host.source === source)
        #expect(bench.keys.key(for: try MarfaConnection(address: address)) == "given")
        // Hydrating again against a closed port fails at once, which shows the new key was tried.
        #expect(await eventually { if case .offline = host.state { true } else { false } }, "\(host.state)")
        try await host.disconnect(.discardCopy)
    }

    /// The count comes from the copy once the write is queued, not from a report not yet passed on.
    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeJustBeforeLeavingIsNotLost() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST last", body: "Just typed")), as: WriteID())
        do {
            try await host.disconnect()
            Issue.record("left a copy with a write waiting")
        } catch {
            #expect(error == .changesWaiting(1))
        }
        #expect(bench.hasCopy(connection))
        #expect(host.source != nil)
        try await host.disconnect(.discardCopy)
    }

    /// The package refuses every call while the copy changes key, and asks for it again.
    @Test(.timeLimit(.minutes(2)))
    func writesMadeWhileTheKeyChangesAreQueued() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        try await host.connect(address: address, key: "first")
        let source = try #require(host.source as? MarfaSource)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let count = 200
        let change = Task { try? await host.replaceKey("second") }
        for index in 0..<count {
            source.submit(
                .create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST key \(index)", body: "Typed")),
                as: WriteID())
            if index % 5 == 0 { await Task.yield() }
        }
        await change.value
        let all = await log.wait { ($0.snapshot?.items.count ?? 0) >= count }
        let refused = log.current.changes.filter { if case .answered(_, .refused) = $0 { true } else { false } }
        let unavailable = log.current.changes.filter { if case .unavailable = $0 { true } else { false } }
        #expect(all != nil, "\(log.current.snapshot?.items.count ?? 0) of \(count) queued")
        #expect(refused.isEmpty, "\(refused.count) refused, such as \(String(describing: refused.first))")
        #expect(unavailable.isEmpty, "\(String(describing: unavailable.first))")
        #expect(await eventually { host.report.waiting == count }, "\(host.report.waiting)")
        try await host.disconnect(.discardCopy)
    }

    @Test(.timeLimit(.minutes(1)))
    func aDamagedCopyIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        let connection = try MarfaConnection(address: address)
        try FileManager.default.createDirectory(at: bench.location.directory(for: connection), withIntermediateDirectories: true)
        try Data("not a store".utf8).write(to: bench.location.store(for: connection))
        do {
            try await host.connect(address: address, key: "unused")
            Issue.record("opened a damaged copy")
        } catch {
            guard case .unavailable(let message) = error else {
                Issue.record("the damaged copy answered \(error)")
                return
            }
            #expect(!message.isEmpty)
        }
        #expect(host.state == .disconnected)
        #expect(host.source == nil)
    }
}

/// Runs against the test instance only when it is configured, as `MarfaSourceLiveTests` does, each on a copy of
/// its own that it removes.
@MainActor @Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
struct MarfaHostLiveTests {
    private func host(_ bench: HostBench) -> MarfaHost {
        bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
    }

    @Test(.timeLimit(.minutes(2)))
    func aRefusedCreateIsAProblemThePersonCanCopyAndDiscard() async throws {
        let bench = try HostBench()
        let host = host(bench)
        let made = LiveMarfa.Made()
        do {
            try await refuseAndDiscard(host, made)
        } catch {
            await LiveMarfa.purge(made.ids)
            throw error
        }
        await LiveMarfa.purge(made.ids)
        try await host.disconnect(.discardCopy)
    }

    private func refuseAndDiscard(_ host: MarfaHost, _ made: LiveMarfa.Made) async throws {
        try await host.connect(address: try #require(LiveMarfa.address), key: try #require(LiveMarfa.key))
        #expect(await eventually(.seconds(30)) { host.state == .online && host.report.queueRead })

        let title = "MAPPTEST refused \(UUID().uuidString.prefix(8))"
        let id = made.mint()
        // The server makes no items of its own reserved types, so this is refused and nothing is made.
        try #require(host.source).submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: title)), as: WriteID())
        #expect(await eventually(.seconds(30)) { !host.report.problems.isEmpty })
        let entry = try #require(host.report.problems.first { $0.itemID == id })
        #expect(entry.kind == .refused)
        #expect(entry.change == .create)
        #expect(entry.reason?.code == "type_not_permitted")
        #expect(entry.reason?.message?.isEmpty == false)
        #expect(entry.copyText == title)
        #expect(entry.actions == [.discard])
        #expect(host.waitingChanges == 1)

        let source = try #require(host.source)
        #expect(try await source.resolve(entry.id, by: .tryAgain) == false)
        #expect(try await source.resolve(entry.id, by: .discard))
        #expect(await eventually { host.report.problems.isEmpty })
        let marfa = try #require(source as? MarfaSource)
        #expect(try await marfa.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
        #expect(host.waitingChanges == 0)
    }

    /// A mistyped key never replaces the key that works.
    @Test(.timeLimit(.minutes(2)))
    func aWrongKeyGivenForAWorkingCopyKeepsTheOldKey() async throws {
        let bench = try HostBench()
        let host = host(bench)
        let address = try #require(LiveMarfa.address)
        let key = try #require(LiveMarfa.key)
        try await host.connect(address: address, key: key)
        #expect(await eventually(.seconds(30)) { host.state == .online })
        do {
            try await host.replaceKey("mapptest-not-a-key-\(UUID().uuidString)")
            Issue.record("took a key the server refuses")
        } catch {}
        #expect(bench.keys.key(for: try MarfaConnection(address: address)) == key)
        #expect(await eventually(.seconds(30)) { host.state == .online }, "\(host.state)")
        try await host.disconnect(.discardCopy)
    }

    /// What the person typed after a create the server refused is shown, and copied, with it.
    @Test(.timeLimit(.minutes(2)))
    func anEditBehindARefusedCreateIsPartOfItsProblem() async throws {
        let root = URL.temporaryDirectory.appending(path: "MarfaHostTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let made = LiveMarfa.Made()
        let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
        let source = try await MarfaSource.open(
            connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
            location: try MarfaStoreLocation(root: root))
        do {
            let log = ChangeLog(source)
            _ = try #require(await log.wait { $0.snapshot != nil })
            // Queued before the copy is first hydrated, so neither goes until both are queued.
            let id = made.mint()
            source.submit(.create(id: id, ItemDraft(type: TypeID("system.folder"), title: "MAPPTEST first words")), as: WriteID())
            let created = try #require(await log.wait { $0.snapshot?.items.contains { $0.id == id } == true })
            let version = try #require(created.snapshot?.items.first { $0.id == id }?.version)
            source.submit(
                .editProperties(id, ["title": .string("MAPPTEST first words, then everything typed after")], base: version, undoing: nil),
                as: WriteID())
            #expect(await eventually { source.syncReport.waiting == 2 })
            source.refresh()
            #expect(await eventually(.seconds(30)) { source.syncReport.problems.contains { $0.itemID == id } })
            let entry = try #require(source.syncReport.problems.first { $0.itemID == id })
            #expect(entry.copyText == "MAPPTEST first words, then everything typed after")
            #expect(entry.dependents.count == 1)
            #expect(try await source.resolve(entry.id, by: .discard))
            #expect(await eventually { source.syncReport.problems.isEmpty })
            #expect(try await source.copy.queue.all().allSatisfy { $0.itemId != id.rawValue })
        } catch {
            await source.close()
            await LiveMarfa.purge(made.ids)
            throw error
        }
        await source.close()
        await LiveMarfa.purge(made.ids)
    }

    /// A throwaway key on a throwaway copy, so the real key is never revoked.
    @Test(.timeLimit(.minutes(2)))
    func aWrongKeyIsRefusedUntilTheRightOneIsGiven() async throws {
        let bench = try HostBench()
        let host = host(bench)
        try await host.connect(address: try #require(LiveMarfa.address), key: "mapptest-not-a-key-\(UUID().uuidString)")
        #expect(await eventually(.seconds(30)) { host.state == .keyRefused }, "\(host.state)")
        try await host.replaceKey(try #require(LiveMarfa.key))
        #expect(await eventually(.seconds(30)) { host.state == .online }, "\(host.state)")
        try await host.disconnect(.discardCopy)
    }
}
