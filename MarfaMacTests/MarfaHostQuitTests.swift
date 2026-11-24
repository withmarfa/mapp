import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// Leaving a copy with a quit at any wait: what the next launch finds is never the copy, and never a queue the
/// person chose to discard.
@Suite(.hangLimit)
@MainActor struct MarfaHostQuitTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let firstAddress = "http://first.test:8210"

    /// What a launch would find at one moment: the saved address and the addresses whose copy is marked to go.
    private struct Found: Equatable, Sendable {
        var address: String?
        var marked: [String]
    }

    private nonisolated static func found(_ suite: String) -> Found {
        let defaults = UserDefaults(suiteName: suite)
        let marks = defaults?.dictionary(forKey: "MarfaDiscardedCopies") ?? [:]
        return Found(address: defaults?.string(forKey: "MarfaAddress"), marked: marks.keys.sorted())
    }

    /// A connected host whose copy holds two unsent changes, and the ids the person is shown.
    private func connected(_ bench: HostBench, remover: MarfaHost.Remover? = nil, cleaner: MarfaHost.Cleaner? = nil) async throws -> (MarfaHost, FakeMarfaSource, UnsentChanges) {
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: remover, cleaner: cleaner)
        try await host.connect(address: firstAddress, key: "k")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        let held = try await source.storeWrites
        return (host, source, UnsentChanges(ids: Set(held)))
    }

    /// A discard marks the copy and forgets the address before the copy closes, so a quit at the close, at the end of
    /// the sign-in or at the removal finds nothing to open and the copy marked.
    @Test func aQuitAtAnyWaitOfADiscardingDisconnectNeverOpensTheCopy() async throws {
        let bench = HostBench()
        let suite = bench.suite
        let seen = Mutex<[String: Found]>([:])
        let remover: MarfaHost.Remover = { store, agreed in
            seen.withLock { $0["remover"] = Self.found(suite) }
            try await MarfaHost.removeStore(store, agreedToLose: agreed)
        }
        let cleaner: MarfaHost.Cleaner = { seen.withLock { $0["cleaner"] = Self.found(suite) } }
        let (host, source, shown) = try await connected(bench, remover: remover, cleaner: cleaner)
        source.onClose.withLock { $0 = { seen.withLock { $0["close"] = Self.found(suite) } } }
        bench.signIns.onSignOut.withLock { $0 = { seen.withLock { $0["signOut"] = Self.found(suite) } } }

        try await host.disconnect(.discardCopy(shown))

        let marked = Found(address: nil, marked: [firstAddress])
        #expect(seen.withLock { $0 } == ["close": marked, "cleaner": marked, "signOut": marked, "remover": marked])
        #expect(Self.found(suite) == Found(address: nil, marked: []), "the copy is gone and its mark with it")
        #expect(!bench.hasCopy(first))
        let next = bench.host()
        await next.launch()
        #expect(next.connection == nil && next.source == nil, "a later launch opens nothing")
    }

    /// With no discard chosen the address still goes before the files and pictures are removed, and the empty copy is
    /// marked to go before the cleaner runs.
    @Test func aDisconnectForgetsTheAddressBeforeTheCleanerRuns() async throws {
        let bench = HostBench()
        let suite = bench.suite
        let seen = Mutex<Found?>(nil)
        let host = bench.host(cleaner: { seen.withLock { $0 = Self.found(suite) } })
        try await host.connect(address: firstAddress, key: "k")
        try await host.disconnect()
        #expect(seen.withLock { $0 } == Found(address: nil, marked: [firstAddress]))
        #expect(host.connection == nil)
        #expect(!bench.hasCopy(first))
    }

    /// A close that refuses (a write landed after the person was shown the list) leaves the library as it was: the
    /// address saved, no mark, the copy open.
    @Test func aCloseThatRefusesRestoresTheAddressAndTheMark() async throws {
        let bench = HostBench()
        let (host, source, shown) = try await connected(bench)
        let held = try #require(shown.ids.sorted().first)
        do {
            try await host.disconnect(.discardCopy(UnsentChanges(ids: [held])))
            Issue.record("left a copy with changes the person was not shown")
        } catch {
            if case .changesWaiting = error {} else { Issue.record("\(error)") }
        }
        #expect(Self.found(bench.suite) == Found(address: firstAddress, marked: []))
        #expect(host.connection == first)
        #expect(host.source === source)
        #expect(bench.hasCopy(first))
    }

    /// A switch to another address marks the old copy before it closes, so a quit while it closes never sends what
    /// was discarded. The old address is still the saved one until the new copy is shown.
    @Test func aQuitWhileASwitchClosesTheOldCopyFindsItMarked() async throws {
        let bench = HostBench()
        let suite = bench.suite
        let (host, old, shown) = try await connected(bench)
        let seen = Mutex<Found?>(nil)
        old.onClose.withLock { $0 = { seen.withLock { $0 = Self.found(suite) } } }
        try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .discardCopy(shown))
        #expect(seen.withLock { $0 } == Found(address: firstAddress, marked: [firstAddress]))
        #expect(Self.found(suite) == Found(address: "http://second.test:8210", marked: []))
        #expect(!bench.hasCopy(first))
    }

    /// The package removes the copy's files; the folder goes only if nothing is in it, so a copy another opener made in
    /// the gap is not taken with it.
    @Test func theCopysFolderIsKeptWhenSomethingIsInIt() async throws {
        let bench = HostBench()
        let directory = bench.location.directory(for: first)
        let gap: MarfaHost.Remover = { _, _ in
            try Data("opened in the gap".utf8).write(to: directory.appending(path: "other-copy"))
        }
        let host = bench.host(remover: gap)
        try await host.connect(address: firstAddress, key: "k")
        try await host.disconnect(.discardNothing)
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "other-copy").path))
        #expect(host.connection == nil)
    }

    @Test func theCopysFolderIsRemovedWhenItIsEmpty() async throws {
        let bench = HostBench()
        let host = bench.host(remover: { _, _ in })
        try await host.connect(address: firstAddress, key: "k")
        try await host.disconnect(.discardNothing)
        #expect(!bench.hasCopy(first))
    }

    /// A folder that is already gone, or one with something in it, is done, not an error.
    @Test func removingAFolderOnlyWhenEmptyNeverThrowsForAMissingOrBusyOne() throws {
        let root = URL.temporaryDirectory.appending(path: "RemoveIfEmpty-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try MarfaHost.removeIfEmpty(root.appending(path: "missing"))
        let file = root.appending(path: "file")
        try Data().write(to: file)
        try MarfaHost.removeIfEmpty(root)
        #expect(FileManager.default.fileExists(atPath: file.path))
        try FileManager.default.removeItem(at: file)
        try MarfaHost.removeIfEmpty(root)
        #expect(!FileManager.default.fileExists(atPath: root.path))
    }
}
