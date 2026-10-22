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
    let embeds: any EmbedResolver = FakeEmbeds()
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

    /// Keys the copy closes on, as one that cannot open its store again does.
    let closesOn = Mutex<Set<String>>([])

    func tryKey(_ key: String) async throws -> MarfaSync.KeyCheck {
        record("tryKey \(key)")
        if refusesKeys.withLock({ $0 }) || closesOn.withLock({ $0.contains(key) }) {
            throw SourceFailure(kind: .missing, message: "The copy closed.")
        }
        return verdicts.withLock { $0[key] } ?? .accepted
    }

    /// The text of the first writes the report counts, as the copy reads it from its queue.
    let unsentTexts = Mutex<[SyncContent]>([])

    /// One write for each the report counts.
    func unsentWrites() async -> UnsentWrites? {
        let report = report.value
        guard report.queueRead else { return nil }
        var unsent = UnsentWrites.fake(report.changesNotSent)
        unsent.texts = unsentTexts.withLock { $0 }.enumerated().map { index, content in
            UnsentWrites.Text(id: "w\(index)", change: .edit, content: content, date: Date(timeIntervalSinceReferenceDate: Double(index)))
        }
        return unsent
    }

    func close(agreeing agreed: UnsentWrites?) async -> CloseOutcome {
        let unsent = await unsentWrites()
        let covered = if let unsent { agreed.map { unsent.ids.isSubset(of: $0.ids) } ?? true } else { agreed == nil }
        guard covered else { return .waiting(unsent) }
        record("close")
        return .closed
    }

    var syncReport: SyncReport { report.value }
    func syncReports() -> AsyncStream<SyncReport> { report.values() }
    func resolve(_ problem: SyncProblemEntry.ID, by action: SyncAction) async throws -> Bool { false }

    func changes() -> AsyncStream<SourceChange> { AsyncStream { $0.finish() } }
    func submit(_ write: ItemWrite, as id: WriteID) -> Bool { true }
    func body(of item: ItemID) async throws -> ItemBody { throw SourceFailure(kind: .missing, message: "") }
    func fileURL(of item: ItemID) async throws -> URL { throw SourceFailure(kind: .missing, message: "") }
    func bodies(of items: Set<ItemID>) async throws -> [ItemBody] { [] }
    func search(_ text: String, in query: ItemQuery) async throws -> [ItemID] { [] }
    func endEditing(_ item: ItemID) {}
    /// While set, `queueSubmitted` waits, as an engine busy with a long step would.
    let queuing = Mutex(false)
    let queued = Mutex(0)

    func queueSubmitted() async {
        while queuing.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
        queued.withLock { $0 += 1 }
    }

    /// While set, closing waits, as a copy finishing its last step does.
    let closesSlowly = Mutex(false)

    func close() async {
        record("close")
        while closesSlowly.withLock({ $0 }) { try? await Task.sleep(for: .milliseconds(10)) }
    }
}

nonisolated extension UnsentWrites {
    static func fake(_ count: Int) -> UnsentWrites {
        UnsentWrites(ids: Set((0..<count).map { "w\($0)" }))
    }
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
    /// Run as each delete begins.
    let onDelete = Mutex<(@Sendable () -> Void)?>(nil)

    func save(_ key: String, for connection: MarfaConnection) {
        keys.withLock { $0[connection] = key }
    }

    func key(for connection: MarfaConnection) -> String? {
        keys.withLock { $0[connection] }
    }

    func delete(for connection: MarfaConnection) throws {
        onDelete.withLock { $0 }?()
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

    /// The copy stays on disk and the person decides: keeping it loses nothing, and a discard needs the answer to
    /// the question about the changes in it.
    @Test func aCopyADifferentVersionMadeKeepsItsChangesUntilThePersonChooses() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 3), message: "The package’s words.") }
        let host = bench.host()

        await host.launch()
        #expect(host.state == .otherVersion(unsent: 3))
        #expect(host.source == nil)
        #expect(host.waitingChanges == 3)
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: host.state, isLaunching: false, isBusy: false) == .failed)

        await expect(.changesWaiting(nil)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == first)
        #expect(bench.hasCopy(first))
        #expect(bench.keys.key(for: first) == "k")

        try await host.disconnect(.keepCopy)
        #expect(host.connection == nil)
        #expect(bench.hasCopy(first), "keeping the copy leaves it for the version that can send what it holds")
        #expect(bench.keys.key(for: first) == nil)
    }

    @Test func aCopyAnotherCopyOfTheAppHoldsIsLeftForThePersonToQuitIt() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .inUse, message: "The package’s words.") }
        let host = bench.host()

        await host.launch()
        #expect(host.state == .inUse)
        #expect(host.source == nil)
        #expect(bench.hasCopy(first))
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: host.state, isLaunching: false, isBusy: false) == .failed)
    }

    @Test func connectingToAServerWhoseCopyADifferentVersionMadeIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: nil), message: "The package’s words.") }
        await expect(.otherVersion(unsent: nil)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.hasCopy(first))
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

        await expect(.changesWaiting(.fake(2))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
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
        try await host.disconnect(.discardCopy(.fake(2)))
        #expect(!bench.hasCopy(first))
    }

    /// Text a page hands over as the copy is left reaches the copy before it reads its queue and closes, so it is
    /// asked about rather than lost.
    @Test func editsHandedOverAsACopyIsLeftAreInItWhenItCloses() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        host.handOverEdits = { source.report.set(SyncReport(waiting: 1, queueRead: true)); return true }

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "k2")
        }
        #expect(host.connection == first)
        #expect(!source.calls.contains("close"))
    }

    @Test func aRejectedEditorFlushKeepsTheCurrentLibraryOpen() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(host.source as? FakeMarfaSource)
        host.handOverEdits = { false }
        do { try await host.disconnect(.keepCopy); Issue.record("Leaving was approved after the editor rejected saving") }
        catch { if case .unavailable = error {} else { Issue.record("Unexpected failure: \(error)") } }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))
        #expect(!host.isBusy)
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
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
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

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
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
        #expect(error as? MarfaHost.Problem == .changesWaiting(.fake(1)))
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
            try await host.disconnect(.discardCopy(nil))
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

/// The second review's findings, each first seen failing on the code before its fix.
@MainActor struct MarfaHostSecondReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    @Test(.timeLimit(.minutes(1)))
    func aRetryInACancelledTaskStops() async throws {
        let hub = MarfaHub()
        hub.changingKey(true)
        let attempts = Mutex(0)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await MarfaEngine.asking(hub) { () async throws -> Int in
                let count = attempts.withLock { count in
                    count += 1
                    return count
                }
                if count >= 10_000 { return count }
                throw MarfaError.invalid(message: "this working copy is changing its key; ask again")
            }
        }
        let result = await task.result
        #expect(attempts.withLock { $0 } < 10, "\(attempts.withLock { $0 }) attempts")
        guard case .failure = result else {
            Issue.record("went on retrying in a cancelled task")
            return
        }
    }

    /// Giving the old key back can close the copy too, which is then opened again rather than kept attached.
    @Test func aCopyThatClosesWhileTheOldKeyGoesBackIsOpenedAgain() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.verdicts.withLock { $0["typo"] = .refused }
        source.closesOn.withLock { $0 = ["good"] }
        do {
            try await host.replaceKey("typo")
            Issue.record("took a key the server refuses")
        } catch {}
        #expect(source.calls == ["refresh", "tryKey typo", "tryKey good", "close"])
        #expect(bench.servers.opened.count == 2)
        #expect(host.source === bench.servers.last)
        #expect(bench.keys.key(for: first) == "good")
    }

    /// The copy is marked discarded before anything is removed, so a launch after a crash part way never sends
    /// what the person chose to discard.
    @Test func aCopyIsMarkedDiscardedBeforeItIsRemoved() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let suite = bench.suite
        let seen = Mutex<[String]?>(nil)
        bench.keys.onDelete.withLock {
            $0 = { seen.withLock { $0 = UserDefaults(suiteName: suite)?.stringArray(forKey: "MarfaDiscardedCopies") ?? [] } }
        }
        try await host.disconnect()
        #expect(seen.withLock { $0 } == ["http://first.test:8210"])
        #expect(bench.defaults.stringArray(forKey: "MarfaDiscardedCopies") ?? [] == [])
        #expect(!bench.hasCopy(first))
    }

    @Test func aKeyAndACopyThatCannotBeRemovedAreBothReported() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        bench.keys.failsDelete.withLock { $0 = true }
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: bench.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bench.root.path) }
        do {
            try await host.disconnect()
            Issue.record("said the key and the copy were removed")
        } catch {
            #expect("\(error)".contains("The keychain refused."), "\(error)")
            #expect("\(error)".contains("copy"), "\(error)")
        }
    }
}

/// The host over a real copy whose server refuses every connection.
@MainActor @Suite(.serialized)
struct MarfaHostOfflineTests {
    private let address = "http://127.0.0.1:9"

    /// The choice the person makes after being shown `problem`.
    private static func discard(after problem: MarfaHost.Problem?) -> MarfaHost.DisconnectChoice {
        if case .changesWaiting(let shown) = problem { .discardCopy(shown ?? UnsentWrites(ids: [])) } else { .discardCopy(UnsentWrites(ids: [])) }
    }

    private static func count(_ problem: MarfaHost.Problem) -> Int? {
        if case .changesWaiting(let unsent) = problem { unsent?.count } else { nil }
    }

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
            #expect(Self.count(error) == 1, "\(error)")
        }
        try await host.disconnect(.keepCopy)
        #expect(bench.hasCopy(connection))

        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.waiting == 1 })
        let log = ChangeLog(try #require(host.source as? MarfaSource))
        #expect(await log.wait { $0.item(titled: "MAPPTEST kept")?.sync == .waiting(writes: 1) } != nil)

        try await host.disconnect(.discardCopy(nil))
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
        try await host.disconnect(.discardCopy(nil))
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
            #expect(Self.count(error) == 1, "\(error)")
        }
        #expect(bench.hasCopy(connection))
        #expect(host.source != nil)
        try await host.disconnect(.discardCopy(nil))
    }

    /// A write that lands while the person is being asked, such as an editor's late save, is not discarded with
    /// what they were shown.
    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        let connection = try MarfaConnection(address: address)
        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST shown", body: "One")), as: WriteID())
        var shown: MarfaHost.Problem?
        do {
            try await host.disconnect()
        } catch {
            shown = error
        }
        #expect(shown != nil)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST late", body: "Two")), as: WriteID())
        do {
            try await host.disconnect(Self.discard(after: shown))
            Issue.record("discarded a write made after the person was asked")
        } catch {
            #expect(Self.count(error) == 2, "\(error)")
        }
        #expect(bench.hasCopy(connection))
        #expect(host.source != nil)
        try await host.disconnect(.keepCopy)
    }

    @Test(.timeLimit(.minutes(1)))
    func aWriteMadeWhileMovingAddressAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, keys: $1, location: $2) })
        let connection = try MarfaConnection(address: address)
        let other = "http://127.0.0.1:10"
        try await host.connect(address: address, key: "unused")
        #expect(await eventually { host.report.queueRead })
        let source = try #require(host.source)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST shown", body: "One")), as: WriteID())
        var shown: MarfaHost.Problem?
        do {
            try await host.changeAddress(to: other, key: "unused")
        } catch {
            shown = error
        }
        #expect(shown != nil)
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST late", body: "Two")), as: WriteID())
        do {
            try await host.changeAddress(to: other, key: "unused", choice: Self.discard(after: shown))
            Issue.record("discarded a write made after the person was asked")
        } catch {
            #expect(Self.count(error) == 2, "\(error)")
        }
        #expect(host.connection == connection)
        #expect(bench.hasCopy(connection))
        #expect(!bench.hasCopy(try MarfaConnection(address: other)))
        try await host.disconnect(.keepCopy)
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
        try await host.disconnect(.discardCopy(nil))
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

extension LiveMarfaTests {
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
            try await host.disconnect(.discardCopy(nil))
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
            try await host.disconnect(.discardCopy(nil))
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
            try await host.disconnect(.discardCopy(nil))
        }
    }
}

/// The modes a window would read while a step runs: sampled whenever the step waits, which is when a window can
/// draw.
@MainActor final class ModeWatch {
    private(set) var seen: [Libraries.Mode] = []
    private var watching: Task<Void, Never>?

    init(_ libraries: Libraries) {
        watching = Task { [weak self] in
            while !Task.isCancelled {
                self?.seen.append(libraries.mode)
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func stop() {
        watching?.cancel()
    }
}

/// The connect review's findings for the host, each failing on the code before its fix.
@MainActor struct MarfaHostConnectReviewTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func libraries(_ bench: HostBench) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "MarfaHostConnectReviewTests-\(UUID().uuidString)"))
        return Libraries(folder: NotesFolder(defaults: defaults), host: bench.host())
    }

    /// A quit while the key and the copy are removed must not leave the address behind, or the next launch opens
    /// the server just left, with its key gone, and says the key was refused.
    @Test(arguments: [MarfaHost.DisconnectChoice.keepCopy, .discardCopy(nil)])
    func leavingAServerForgetsItsAddressBeforeRemovingAnything(choice: MarfaHost.DisconnectChoice) async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let suite = bench.suite
        let seen = Mutex<String?>("not asked")
        bench.keys.onDelete.withLock {
            $0 = { seen.withLock { $0 = UserDefaults(suiteName: suite)?.string(forKey: "MarfaAddress") } }
        }
        try await host.disconnect(choice)
        #expect(seen.withLock { $0 } == nil, "the address was still saved when the key went")
        #expect(bench.keys.key(for: first) == nil)
        #expect(bench.hasCopy(first) == (choice == .keepCopy), "a kept copy stays, a discarded one goes")

        let next = bench.host()
        await next.launch()
        #expect(next.configuredConnection == nil)
        #expect(next.source == nil)
    }

    /// The windows go from one server's library to the other's, never through the notes folder, while the old
    /// key and copy are removed.
    @Test func switchingServersNeverShowsTheFolderBetween() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", key: "k1")
        bench.keys.onDelete.withLock { $0 = { Thread.sleep(forTimeInterval: 0.2) } }

        let watch = ModeWatch(libraries)
        try await libraries.host.changeAddress(to: "http://second.test:8210", key: "k2")
        watch.stop()
        #expect(!watch.seen.contains(.files), "\(watch.seen)")
        #expect(watch.seen.allSatisfy { $0 == .marfa }, "\(watch.seen)")
        #expect(libraries.host.connection == second)
    }

    /// A copy that closes as a key is replaced is waited for while it opens again, not shown as the notes folder.
    @Test func aCopyOpenedAgainForAKeyIsWaitedForNotShownAsTheFolder() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.closesOn.withLock { $0 = ["new"] }
        source.closesSlowly.withLock { $0 = true }

        let watch = ModeWatch(libraries)
        let replacing = Task { try await libraries.host.replaceKey("new") }
        #expect(await eventually { source.calls.contains("close") })
        try await Task.sleep(for: .milliseconds(50))
        source.closesSlowly.withLock { $0 = false }
        _ = await replacing.result
        watch.stop()
        #expect(!watch.seen.contains(.files), "\(watch.seen)")
        #expect(watch.seen.contains(.opening), "\(watch.seen)")
        #expect(libraries.mode == .marfa)
    }

    /// Quitting waits until the copy has queued every write, but only so long, so a copy that cannot answer
    /// never keeps the app from quitting.
    @Test func quittingWaitsForTheCopyToQueueButOnlySoLong() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", key: "k")
        _ = try #require(libraries.current as? MarfaLibrary)
        let source = try #require(bench.servers.last)

        #expect(await libraries.flushEditors(within: .seconds(10)))
        #expect(source.queued.withLock { $0 } == 1)

        source.queuing.withLock { $0 = true }
        let clock = ContinuousClock()
        let start = clock.now
        #expect(await libraries.flushEditors(within: .milliseconds(200)) == false)
        #expect(clock.now - start < .seconds(5))
        source.queuing.withLock { $0 = false }
    }
}
