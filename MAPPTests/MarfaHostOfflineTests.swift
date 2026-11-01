import Foundation
import Marfa
import Testing
@testable import MAPP

/// The host over a real copy whose server refuses every connection.
@MainActor @Suite(.serialized, .hangLimit)
struct MarfaHostOfflineTests {
    private let address = "http://127.0.0.1:9"

    /// The choice the person makes after being shown `problem`.
    private static func discard(after problem: MarfaHost.Problem?) -> MarfaHost.DisconnectChoice {
        if case .changesWaiting(let shown) = problem { .discardCopy(shown ?? UnsentWrites(ids: [])) } else { .discardCopy(UnsentWrites(ids: [])) }
    }

    private static func count(_ problem: MarfaHost.Problem) -> Int? {
        if case .changesWaiting(let unsent) = problem { unsent?.count } else { nil }
    }

    @Test
    func aKeptCopyGoesOnWhereItWasLeft() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
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

    /// A sign-in the Keychain would not give is not a missing one: the library is shown unavailable for that reason.
    @Test
    func anUnreadableSignInIsToldAndNotShownAsSignedOut() async throws {
        let bench = try HostBench()
        let connection = try MarfaConnection(address: address)
        bench.defaults.set(address, forKey: "MarfaAddress")
        bench.signIns.save("first", for: connection.address)
        bench.signIns.makeUnreadable(connection)
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
        await host.launch()
        #expect(host.state == .unavailable(message: Words.signInUnreadable), "\(host.state)")
        #expect(host.source == nil)
        #expect(bench.signIns.calls.isEmpty, "nothing was replaced or signed out")
    }

    /// The count comes from the copy once the write is queued, not from a report not yet passed on.
    @Test
    func aWriteMadeJustBeforeLeavingIsNotLost() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
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
    @Test
    func aWriteMadeAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
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

    @Test
    func aWriteMadeWhileMovingAddressAfterThePersonWasAskedIsNotDiscarded() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
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

    @Test
    func aDamagedCopyIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { try await MarfaSource.open($0, signIns: $1, location: $2) })
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
