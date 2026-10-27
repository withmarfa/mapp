import Foundation
import Synchronization
import Testing
@testable import MAPP

/// The name a server gives itself, read through a fake description source.
@MainActor struct MarfaInstanceNameTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func libraries(_ bench: HostBench, host: MarfaHost) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "MarfaInstanceNameTests-\(UUID().uuidString)"))
        // No page is open here; the real hand-over waits on every page in the process, those of other suites included.
        return Libraries(host: host, defaults: defaults, handOverPages: { $0(true) })
    }

    @Test func theNameIsReadOnceTheConnectionIsSet() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        #expect(host.instanceName(for: first) == nil)
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Home Marfa" })
    }

    @Test func theHostIsShownBeforeAnyNameHasBeenRead() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let libraries = try libraries(bench, host: host)
        #expect(LibraryDescription.name(libraries) == "first.test")
    }

    @Test func theNameReplacesTheHostAsSoonAsItIsRead() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        let libraries = try libraries(bench, host: host)
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { LibraryDescription.name(libraries) == "Home Marfa" })
    }

    @Test func eachServerKeepsItsOwnName() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "One"; $0[second] = "Two" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "One" })
        try await host.changeAddress(to: "http://second.test:8210", key: "k", choice: .keepCopy)
        #expect(await eventually { host.instanceName(for: second) == "Two" })
        #expect(host.instanceName(for: first) == nil)
    }

    @Test func aFailedReadKeepsTheLastName() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Home Marfa" })
        let source = try #require(bench.servers.last)
        bench.servers.names.withLock { $0[first] = nil }
        let before = bench.servers.reads.withLock { $0 }
        source.state.set(.offline(reason: nil))
        source.state.set(.online)
        #expect(await eventually { bench.servers.reads.withLock { $0 } > before })
        #expect(host.instanceName(for: first) == "Home Marfa")
    }

    @Test func aReconnectReadsTheNameAgain() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Old" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Old" })
        let source = try #require(bench.servers.last)
        bench.servers.names.withLock { $0[first] = "New" }
        source.state.set(.offline(reason: nil))
        source.state.set(.online)
        #expect(await eventually { host.instanceName(for: first) == "New" })
    }

    @Test func theNameIsKeptForTheNextLaunch() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Home Marfa" })
        bench.servers.names.withLock { $0[first] = nil }
        let relaunched = bench.host()
        #expect(relaunched.instanceName(for: first) == "Home Marfa")
        await relaunched.launch()
        #expect(relaunched.instanceName(for: first) == "Home Marfa")
    }

    @Test func disconnectingForgetsTheName() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Home Marfa" })
        try await host.disconnect()
        #expect(host.instanceName(for: first) == nil)
    }
}
