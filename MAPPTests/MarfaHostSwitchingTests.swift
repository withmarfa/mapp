import Foundation
import Marfa
import struct MarfaCore.Draft
import Synchronization
import Testing
@testable import MAPP

/// The modes a window would read while a step runs: sampled whenever the step waits, which is when a window can
/// draw.
@MainActor final class ModeWatch {
    private(set) var seen: [Libraries.Mode] = []
    private var watching: Task<Void, Never>?

    init(_ libraries: Libraries) {
        watching = Task { [weak self] in
            while !Task.isCancelled {
                self?.seen.append(libraries.mode)
                // Samples the mode often enough to see a brief change.
                try? await Task.sleep(for: .milliseconds(5))
            }
        }
    }

    func stop() {
        watching?.cancel()
    }
}

/// Switching and leaving servers as the windows see them, and quitting while a copy queues. Each test was first
/// seen failing on the code before its fix.
@Suite(.hangLimit)
@MainActor struct MarfaHostSwitchingTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func libraries(_ bench: HostBench) throws -> Libraries {
        let defaults = try #require(UserDefaults(suiteName: "MarfaHostSwitchingTests-\(UUID().uuidString)"))
        // No page is open here; the real hand-over waits on every page in the process, those of other suites included.
        return Libraries(host: bench.host(), defaults: defaults, handOverPages: { $0(true) })
    }

    /// A quit while the key and the copy are removed must not leave the address behind, or the next launch opens
    /// the server just left, with its key gone, and says the key was refused.
    @Test(arguments: [MarfaHost.DisconnectChoice.keepCopy, .discardNothing])
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

    /// The windows go from one server's library to the other's, never through the welcome screen or a failure,
    /// while the old key and copy are removed.
    @Test func switchingServersShowsNothingBetween() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", key: "k1")
        bench.keys.onDelete.withLock { $0 = { Thread.sleep(forTimeInterval: 0.2) } }

        let watch = ModeWatch(libraries)
        try await libraries.host.changeAddress(to: "http://second.test:8210", key: "k2")
        watch.stop()
        #expect(watch.seen.allSatisfy { $0 == .marfa }, "\(watch.seen)")
        #expect(libraries.host.connection == second)
    }

    /// A copy that closes as a key is replaced is waited for while it opens again, not shown as failed.
    @Test func aCopyOpenedAgainForAKeyIsWaitedForNotShownAsFailed() async throws {
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
        // Holds the close a little, as a slow one would be held.
        try await Task.sleep(for: .milliseconds(50))
        source.closesSlowly.withLock { $0 = false }
        _ = await replacing.result
        watch.stop()
        #expect(!watch.seen.contains(.failed), "\(watch.seen)")
        #expect(watch.seen.contains(.opening), "\(watch.seen)")
        #expect(libraries.mode == .marfa)
    }

    /// Quitting waits until the copy has queued every write, but only so long, and says why it did not quit.
    @Test func quittingWaitsForTheCopyToQueueButOnlySoLong() async throws {
        let bench = try HostBench()
        let libraries = try libraries(bench)
        try await libraries.host.connect(address: "http://first.test:8210", key: "k")
        _ = try #require(libraries.current as? MarfaLibrary)
        let source = try #require(bench.servers.last)

        #expect(await libraries.flushEditors(within: .seconds(10)))
        #expect(source.queued.withLock { $0 } == 1)

        source.queuing.withLock { $0 = true }
        // Returns at all only because the limit ends the wait, which the copy never would while it queues.
        #expect(await libraries.flushEditors(within: .milliseconds(200)) == false)
        #expect(libraries.current?.notices.waiting.last?.title == "Couldn’t Quit")
        source.queuing.withLock { $0 = false }
    }
}
