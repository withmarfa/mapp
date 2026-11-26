import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// The name a server gives itself, read through a fake description source.
@Suite(.hangLimit)
@MainActor struct MarfaInstanceNameTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    @Test func eachServerKeepsItsOwnName() async throws {
        let bench = HostBench()
        bench.servers.names.withLock { $0[first] = "One"; $0[second] = "Two" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "One" })
        try await host.changeAddress(to: "http://second.test:8210", key: "k", choice: .keepCopy)
        #expect(await eventually { host.instanceName(for: second) == "Two" })
        #expect(host.instanceName(for: first) == "One", "the Marfa left keeps its name for a return")
    }

    @Test func theNameIsKeptForTheNextLaunch() async throws {
        let bench = HostBench()
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
        let bench = HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(await eventually { host.instanceName(for: first) == "Home Marfa" })
        try await host.disconnect()
        #expect(host.instanceName(for: first) == nil)
    }
}
