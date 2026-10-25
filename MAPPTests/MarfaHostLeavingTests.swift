import Foundation
import Marfa
import struct MarfaCore.Draft
import Synchronization
import Testing
@testable import MAPP

/// Leaving a server: what is removed, in what order, and what the person is told when a removal fails. Each test
/// was first seen failing on the code before its fix.
@MainActor struct MarfaHostLeavingTests {
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
        // Time for the change of address, held at opening, to see the old copy's report.
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
            try await discardEverything(host)
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
        let seen = Mutex<[String: Int]?>(nil)
        bench.keys.onDelete.withLock {
            $0 = { seen.withLock { $0 = UserDefaults(suiteName: suite)?.dictionary(forKey: "MarfaDiscardedCopies") as? [String: Int] ?? [:] } }
        }
        try await host.disconnect()
        #expect(seen.withLock { $0 } == ["http://first.test:8210": 0], "marked with the number of changes agreed to be lost")
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true)
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
