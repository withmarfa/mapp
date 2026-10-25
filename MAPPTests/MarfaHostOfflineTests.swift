import Foundation
import Marfa
import Testing
@testable import MAPP

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

        try await discardEverything(host)
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
        // Time for a reconnection the refused key should not set off.
        try await Task.sleep(for: .seconds(1))
        #expect(host.state == .keyRefused)

        try await host.replaceKey("given")
        #expect(host.source === source)
        #expect(bench.keys.key(for: try MarfaConnection(address: address)) == "given")
        // Hydrating again against a closed port fails at once, which shows the new key was tried.
        #expect(await eventually { if case .offline = host.state { true } else { false } }, "\(host.state)")
        try await discardEverything(host)
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
        try await discardEverything(host)
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
        try await discardEverything(host)
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
