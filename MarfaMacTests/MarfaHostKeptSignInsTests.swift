import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

/// Two Marfas stay signed in: a switch keeps the Marfa it leaves, with its sign-in, copy and queue, and coming back
/// through the Address field uses that sign-in again. A step that fails ends only a sign-in it made itself.
@Suite(.hangLimit)
@MainActor struct MarfaHostKeptSignInsTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func problem(_ work: () async throws(MarfaHost.Problem) -> Void) async -> MarfaHost.Problem? {
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }

    /// A bench whose two servers say they are two instances, so each has its own copy.
    private func bench() -> HostBench {
        let bench = HostBench()
        bench.servers.instances.withLock { $0 = [first: "instance-a", second: "instance-b"] }
        return bench
    }

    private func browsers(to connection: MarfaConnection, _ bench: HostBench) -> Int {
        bench.signIns.calls.filter { $0 == "browser \(connection.address.absoluteString)" }.count
    }

    private func signOuts(of connection: MarfaConnection, _ bench: HostBench) -> Int {
        bench.signIns.calls.filter { $0 == "signOut \(connection.address.absoluteString)" }.count
    }

    @Test func aSwitchKeepsTheSignInAndCopyOfTheMarfaItLeaves() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")

        #expect(host.connection == second)
        #expect(try bench.signIns.key(for: first.address) == "a")
        #expect(try bench.signIns.key(for: second.address) == "b")
        #expect(signOuts(of: first, bench) == 0)
        #expect(bench.hasCopy(first), "the copy left is kept for a return")
    }

    @Test func comingBackUsesTheKeptSignInWithoutTheBrowser() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")
        // A browser that would fail shows any sign-in asked for.
        bench.signIns.script(browser: [.failure(SignInError.canceled)])

        try #require(await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: first.address.absoluteString, via: .browser) } == nil)
        #expect(host.connection == first)
        #expect(browsers(to: first, bench) == 1)
        #expect(try bench.signIns.key(for: first.address) == "a")

        try #require(await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: second.address.absoluteString, via: .browser) } == nil)
        #expect(host.connection == second)
        #expect(browsers(to: second, bench) == 1)
        #expect(bench.signIns.calls.allSatisfy { !$0.hasPrefix("signOut") }, "\(bench.signIns.calls)")
    }

    /// Writes left in a copy stay in its own store, are never sent to the Marfa switched to, and are there to send
    /// when the person returns, with that Marfa's own sign-in.
    @Test func writesLeftWaitInTheirOwnCopyUntilItsMarfaIsUsedAgain() async throws {
        let bench = bench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        let left = try #require(bench.servers.last)
        let written = try await left.storeWrites
        #expect(written.count == 2)
        left.report.set(SyncReport(waiting: 2, queueRead: true))
        bench.servers.storedWrites.withLock { $0 = 0 }

        let asked = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: second.address.absoluteString, key: "b") }
        guard case .changesWaiting = asked else { Issue.record("expected the question, got \(String(describing: asked))"); return }
        try await host.changeAddress(to: second.address.absoluteString, key: "b", choice: .keepCopy)

        #expect(host.connection == second)
        #expect(try await left.storeWrites == written)
        let firstFolder = bench.location.directory(for: first).lastPathComponent
        #expect(!host.otherCopies(of: second).contains(firstFolder), "another Marfa's copy is never sent to this one")

        try await host.changeAddress(to: first.address.absoluteString, via: .browser)
        let back = try #require(bench.servers.last)
        #expect(back !== left)
        #expect(back.store.withLock { $0 } == left.store.withLock { $0 })
        #expect(try await back.storeWrites == written)
        #expect(browsers(to: first, bench) == 1)
    }

    @Test func aSwitchThatFailsEndsOnlyASignInItMade() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "no") }

        let failed = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: second.address.absoluteString, key: "b") }
        #expect(failed != nil)
        #expect(host.connection == first)
        #expect(try bench.signIns.key(for: second.address) == nil, "the approval made for the switch is ended")
        #expect(try bench.signIns.key(for: first.address) == "a")
        #expect(signOuts(of: first, bench) == 0)
    }

    @Test func aSwitchThatFailsLeavesASignInHeldBeforeIt() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")
        try await host.changeAddress(to: first.address.absoluteString, via: .browser)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "no") }

        let failed = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: second.address.absoluteString, via: .browser) }
        #expect(failed != nil)
        #expect(host.connection == first)
        #expect(try bench.signIns.key(for: second.address) == "b", "a sign-in held before the step is the person's, not the step's")
        #expect(signOuts(of: second, bench) == 0)
    }

    /// A question asked after a held sign-in was used keeps nothing for the answer, so dropping it, or a launch after
    /// a quit, ends no sign-in.
    @Test func aDroppedQuestionNeverEndsASignInHeldBeforeIt() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")
        try await host.changeAddress(to: first.address.absoluteString, via: .browser)
        let open = try #require(bench.servers.last)
        open.report.set(SyncReport(waiting: 1, queueRead: true))
        let handOvers = Mutex(0)
        host.handOverEdits = {
            // The second hand-over comes after the sign-in, where a write made meanwhile is counted again.
            if handOvers.withLock({ $0 += 1; return $0 }) == 2 { open.report.set(SyncReport(waiting: 2, queueRead: true)) }
            return true
        }

        let asked = await problem { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: second.address.absoluteString, via: .browser, choice: .discardCopy(.fake(1)))
        }
        guard case .changesWaiting = asked else { Issue.record("expected the question, got \(String(describing: asked))"); return }
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil)
        await host.abandonPendingSignIn()
        #expect(try bench.signIns.key(for: second.address) == "b")
        #expect(signOuts(of: second, bench) == 0)
    }

    @Test func disconnectingEndsOnlyTheSignInOfTheMarfaShown() async throws {
        let bench = bench()
        let cleaned = Mutex<[String]>([])
        let host = bench.host(cleaner: { folder in cleaned.withLock { $0.append(folder) } })
        try await host.connect(address: first.address.absoluteString, key: "a")
        try await host.changeAddress(to: second.address.absoluteString, key: "b")
        let secondFolder = bench.location.directory(for: second).lastPathComponent

        try await host.disconnect()

        #expect(try bench.signIns.key(for: second.address) == nil)
        #expect(try bench.signIns.key(for: first.address) == "a")
        #expect(signOuts(of: first, bench) == 0)
        #expect(bench.hasCopy(first))
        #expect(cleaned.withLock { $0 } == [secondFolder], "only the Marfa left has its files and pictures removed")

        // The Marfa kept opens again from the connect page with its own sign-in.
        bench.signIns.script(browser: [.failure(SignInError.canceled)])
        try await host.connect(address: first.address.absoluteString, via: .browser)
        #expect(host.connection == first)
        #expect(browsers(to: first, bench) == 1)
    }

    @Test func discardingTheCopyLeftOnASwitchKeepsItsSignIn() async throws {
        let bench = bench()
        let cleaned = Mutex<[String]>([])
        let host = bench.host(cleaner: { folder in cleaned.withLock { $0.append(folder) } })
        try await host.connect(address: first.address.absoluteString, key: "a")
        let firstFolder = bench.location.directory(for: first).lastPathComponent

        try await host.changeAddress(to: second.address.absoluteString, key: "b", choice: .discardNothing)

        #expect(!bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == "a")
        #expect(cleaned.withLock { $0 } == [firstFolder])
    }

    /// Writes that reach the copy after the last count are kept with it, and the person is told they wait.
    @Test func writesMadeAsTheSwitchClosesTheCopyAreKeptAndTold() async throws {
        let bench = bench()
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        let open = try #require(bench.servers.last)
        let handOvers = Mutex(0)
        host.handOverEdits = {
            // The third hand-over is the close's own, after both counts.
            if handOvers.withLock({ $0 += 1; return $0 }) == 3 { open.report.set(SyncReport(waiting: 1, queueRead: true)) }
            return true
        }
        host.notices.answerAll()

        try await host.changeAddress(to: second.address.absoluteString, key: "b")

        #expect(host.connection == second)
        #expect(bench.hasCopy(first))
        #expect(open.calls.contains("close"))
        #expect(host.notices.waiting.contains { $0.title == Words.changesWaitTitle })
    }

    /// The same Marfa at another address uses a sign-in that address already holds, and a failure leaves it held.
    @Test func anotherAddressOfTheSameMarfaUsesItsHeldSignIn() async throws {
        let bench = bench()
        let alias = try MarfaConnection(address: "http://alias.test:8210")
        bench.servers.instances.withLock { $0[alias] = "instance-a" }
        let host = bench.host()
        try await host.connect(address: first.address.absoluteString, key: "a")
        bench.signIns.save("alias", for: alias.address)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "no") }

        let failed = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: alias.address.absoluteString, via: .browser) }
        #expect(failed != nil)
        #expect(try bench.signIns.key(for: alias.address) == "alias")
        #expect(browsers(to: alias, bench) == 0)

        bench.servers.failure.withLock { $0 = nil }
        try await host.changeAddress(to: alias.address.absoluteString, via: .browser)
        #expect(host.connection == alias)
        #expect(browsers(to: alias, bench) == 0)
        #expect(try bench.signIns.key(for: alias.address) == "alias")
    }
}
