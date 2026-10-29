import Foundation
import Testing
@testable import MAPP

/// The date of the last sync is kept by the host for each server, and Refresh is offered only where it can do something.
@Suite(.hangLimit)
@MainActor struct MarfaHostSyncedTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private static let key = "MarfaLastSynced"

    private func kept(_ bench: HostBench) -> [String: Date] {
        bench.defaults.dictionary(forKey: Self.key) as? [String: Date] ?? [:]
    }

    @Test func aSyncIsKeptForItsServer() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(host.lastSynced == nil)
        let source = try #require(bench.servers.last)
        source.report.update { $0.lastSynced = day }
        #expect(await eventually { host.lastSynced == day })
        #expect(kept(bench) == ["http://first.test:8210": day])
    }

    @Test func theDateSurvivesALaunchAndAThisRunSyncReplacesIt() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        bench.servers.last?.report.update { $0.lastSynced = day }
        #expect(await eventually { kept(bench)["http://first.test:8210"] == day })

        let relaunched = bench.host()
        #expect(relaunched.lastSynced == nil, "no server is set until the host launches")
        await relaunched.launch()
        #expect(relaunched.connection == first)
        #expect(relaunched.lastSynced == day, "painted from what the launch before kept")

        let later = day + 3600
        bench.servers.last?.report.update { $0.lastSynced = later }
        #expect(await eventually { relaunched.lastSynced == later })
        #expect(kept(bench)["http://first.test:8210"] == later)
    }

    @Test func anotherServerHasItsOwnDateAndTheOneLeftIsForgotten() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        bench.servers.last?.report.update { $0.lastSynced = day }
        #expect(await eventually { host.lastSynced == day })

        try await host.changeAddress(to: "http://second.test:8210", key: "k", choice: .discardNothing)
        #expect(host.connection == second)
        #expect(host.lastSynced == nil, "the first server's sync says nothing of the second's copy")
        #expect(kept(bench).isEmpty)

        let later = day + 60
        bench.servers.last?.report.update { $0.lastSynced = later }
        #expect(await eventually { host.lastSynced == later })
        #expect(kept(bench) == ["http://second.test:8210": later])

        try await host.disconnect(.discardNothing)
        #expect(kept(bench).isEmpty)
        #expect(host.lastSynced == nil)
    }

    @Test func aSyncReportedAfterLeavingIsNotKept() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        try await host.disconnect(.discardNothing)
        source.report.update { $0.lastSynced = day }
        // A report for a library that is gone has nowhere to arrive; the wait gives one time to, if it could.
        try await Task.sleep(for: .milliseconds(100))
        #expect(kept(bench).isEmpty)
    }

    // MARK: Refresh

    @Test func refreshIsOfferedOnlyWhereItCanDoSomething() async throws {
        let bench = try HostBench()
        let host = bench.host()
        #expect(!host.canRefresh, "no library")
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)

        #expect(host.canRefresh, "connecting, with a copy open")
        source.state.set(.online)
        #expect(await eventually { host.canRefresh })

        source.state.set(.offline(reason: "network"))
        #expect(await eventually { host.state == .offline(reason: "network") })
        #expect(host.canRefresh, "a server out of reach is tried again at once")

        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })
        #expect(!host.canRefresh, "a key the server refuses needs a new one first")

        source.state.set(.online)
        #expect(await eventually { host.canRefresh })
        source.report.update { $0.phase = .updating }
        #expect(await eventually { !host.canRefresh }, "already syncing")
        source.report.update { $0.phase = .current }
        #expect(await eventually { host.canRefresh })
    }

    @Test func refreshAsksTheSourceToSyncOnlyWhenItIsOffered() async throws {
        let bench = try HostBench()
        let host = bench.host()
        host.refresh()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        #expect(source.calls == ["refresh"], "the connect's own")
        host.refresh()
        #expect(source.calls == ["refresh", "refresh"])

        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })
        host.refresh()
        #expect(source.calls == ["refresh", "refresh"])
    }

    @Test func theSampleLibraryHasNoServerToRefresh() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { connection, _, _ in SampleLibrary.open(connection) })
        try await host.connect(address: SampleLibrary.connection.address.absoluteString, key: "sample")
        #expect(!host.hasServer)
        #expect(!host.canRefresh)
    }
}
