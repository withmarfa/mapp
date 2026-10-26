import Foundation
import Marfa
import struct MarfaCore.Draft
import Synchronization
import Testing
@testable import MAPP

/// A library that answers nothing of its own: the test sets its connection and report, and reads what it was
/// asked to do.
nonisolated final class FakeMarfaSource: ItemSource {
    let connection: MarfaConnection
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
    func items(inView view: ItemID) async throws -> [ItemID] { [] }
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
    /// The name each address gives itself; an address with none cannot be read.
    let names = Mutex<[MarfaConnection: String]>([:])
    let reads = Mutex(0)
    /// How many writes a new copy's store holds, unsent, as a real one does after the person wrote.
    let storedWrites = Mutex(0)

    var describer: MarfaHost.Describer {
        { connection in
            self.reads.withLock { $0 += 1 }
            guard let name = self.names.withLock({ $0[connection] }) else {
                throw SourceFailure(kind: .missing, message: "The server did not answer.")
            }
            return name
        }
    }

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
            let store = location.store(for: connection)
            let stored = self.storedWrites.withLock { $0 }
            if stored > 0, !FileManager.default.fileExists(atPath: store.path) {
                let copy = try await WorkingCopy.open(store: store)
                for index in 0..<stored {
                    _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": .string("unsent \(index)")]))
                }
                await copy.close()
            }
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

nonisolated extension MarfaHost.DisconnectChoice {
    /// A discard of a copy the person was shown nothing waiting in.
    static var discardNothing: Self { .discardCopy(UnsentWrites(ids: [])) }
}

/// Leaves the library as a person does: asked what waits, they discard exactly that.
@MainActor func discardEverything(_ host: MarfaHost) async throws {
    do {
        try await host.disconnect()
    } catch {
        guard case .changesWaiting(let shown?) = error else { throw error }
        try await host.disconnect(.discardCopy(shown))
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
        location = MarfaStoreLocation(root: root)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        try? FileManager.default.removeItem(at: root)
    }

    func host(opener: MarfaHost.Opener? = nil, remover: MarfaHost.Remover? = nil) -> MarfaHost {
        MarfaHost(
            defaults: defaults, keys: keys, location: location, opener: opener ?? servers.opener, describer: servers.describer,
            remover: remover ?? { try await WorkingCopy.remove(store: $0, unsent: $1) })
    }

    var savedAddress: String? { defaults.string(forKey: "MarfaAddress") }

    func hasCopy(_ connection: MarfaConnection) -> Bool {
        FileManager.default.fileExists(atPath: location.directory(for: connection).path)
    }
}
