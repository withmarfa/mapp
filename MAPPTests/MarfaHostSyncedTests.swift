import Foundation
import Testing
@testable import MAPP

/// The date of the last sync is the copy's own (the open source reports it), and Refresh is offered only where it
/// can do something.
@Suite(.hangLimit)
@MainActor struct MarfaHostSyncedTests {
    private let day = Date(timeIntervalSinceReferenceDate: 800_000_000)

    @Test func theLastSyncIsWhatTheOpenSourceReports() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(host.lastSynced == nil)
        let source = try #require(bench.servers.last)
        source.report.update { $0.lastSynced = day }
        #expect(await eventually { host.lastSynced == day })
        // The host keeps nothing of it: the copy does, so a launch shows it before the server answers.
        #expect(bench.defaults.dictionary(forKey: "MarfaLastSynced") == nil)
    }

    @Test func noLibraryHasNoLastSync() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.report.update { $0.lastSynced = day }
        #expect(await eventually { host.lastSynced == day })
        try await discardEverything(host)
        #expect(host.lastSynced == nil)
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

        source.state.set(.unavailable(message: "stopped"))
        #expect(await eventually { host.state == .unavailable(message: "stopped") })
        #expect(host.canRefresh, "a stopped follow is tried again by a refresh")

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
        #expect(source.calls.isEmpty, "the copy follows its server itself; connecting asks for nothing")
        host.refresh()
        #expect(source.calls == ["refresh"])

        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })
        host.refresh()
        #expect(source.calls == ["refresh"])
    }

    @Test func theSampleLibraryHasNoServerToRefresh() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { connection, _, _ in SampleLibrary.open(connection) })
        try await host.connect(address: SampleLibrary.connection.address.absoluteString, key: "sample")
        #expect(!host.hasServer)
        #expect(!host.canRefresh)
    }
}
