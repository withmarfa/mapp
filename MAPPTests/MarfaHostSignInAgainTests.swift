import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// Signing in again to the address connected to: the open copy is given the new sign-in where it is, and is never
/// detached, closed or opened again for it.
@Suite(.hangLimit)
@MainActor struct MarfaHostSignInAgainTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")

    private func expect(_ problem: MarfaHost.Problem, _ work: () async throws(MarfaHost.Problem) -> Void) async {
        do {
            try await work()
            Issue.record("expected \(problem)")
        } catch {
            #expect(error == problem)
        }
    }

    @Test func aSignedOutLibraryKeepsItsCopyOpenAndIsGivenTheNewSignIn() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        let library = try #require(host.library)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })

        // The library is there for every moment the copy takes to change, so a window showing it never meets none.
        let seen = Mutex<[Bool]>([])
        source.onUse.withLock {
            $0 = { await MainActor.run { seen.withLock { $0.append(host.library === library && host.source === source) } } }
        }
        try await host.signInAgain(via: host.scripted("new"))

        #expect(try bench.signIns.key(for: first.address) == "new")
        #expect(source.calls == ["use"], "the copy is given the sign-in, never closed")
        #expect(source.given == ["new"])
        #expect(seen.withLock { $0 } == [true])
        #expect(host.library === library, "the library is not replaced")
        #expect(host.source === source)
        #expect(bench.servers.opened.count == 1)
        #expect(host.waitingChanges == 2, "what waits in the queue is kept")
        #expect(bench.hasCopy(first))
    }

    /// The package asks for the call after a sign-in that ended even where the credential is the one it had.
    @Test func aSignInAgainThatLeavesTheCredentialUnchangedStillGivesItToTheCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "same")
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        try await host.signInAgain(via: host.scripted("same"))
        #expect(source.given == ["same"])
        #expect(host.source === source)
    }

    @Test func connectingToTheSameAddressAgainOnlySignsInAgain() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        try await host.connect(address: "http://first.test:8210/", key: "again")
        #expect(source.given == ["again"])
        #expect(bench.servers.opened.count == 1)
        #expect(bench.signIns.calls.filter { $0.hasPrefix("browser") }.count == 2)
    }

    /// An address that now reaches another instance is told by the sync's hydration, which finds it (`wrongServer`),
    /// as in `MarfaSyncFailureTests`; the host only keeps the library and shows that state.
    @Test func aServerThatIsNowAnotherInstanceLeavesTheLibraryAndItsOtherServerWords() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        let library = try #require(host.library)
        source.report.set(SyncReport(waiting: 3, queueRead: true))
        source.state.set(.keyRefused)
        try await host.signInAgain(via: host.scripted("new"))
        source.state.set(.unavailable(message: Words.otherServer(unsent: 3)))
        #expect(await eventually { host.state == .unavailable(message: Words.otherServer(unsent: 3)) })
        #expect(host.library === library)
        #expect(host.source === source)
        #expect(host.waitingChanges == 3)
        #expect(Words.otherServer(unsent: 3).contains("3 changes"))
    }

    /// The server forgot the sign-in: the one kept is refused, the person signs in again, and the copy goes on with it.
    @Test func aSignInTheServerForgotIsReplacedAndTheCopyGoesOnWithTheNewOne() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "forgotten")
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })
        #expect(host.canRefresh == false)

        try await host.signInAgain(via: host.scripted("approved"))
        source.state.set(.online)
        #expect(await eventually { host.state == .online })
        #expect(source.given == ["approved"])
        #expect(try bench.signIns.key(for: first.address) == "approved")
        #expect(host.canRefresh)
    }

    @Test func aCopyThatCouldNotBeGivenTheSignInIsClosedAndTold() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.useFailure.withLock { $0 = MarfaError.closed(message: "The copy closed.") }
        await expect(.unavailable(message: "The copy closed.")) { () throws(MarfaHost.Problem) in
            try await host.signInAgain(via: host.scripted("new"))
        }
        #expect(host.source == nil)
        #expect(host.library == nil)
        #expect(source.calls == ["use", "close"])
        #expect(host.state == .unavailable(message: "The copy closed."))
        #expect(bench.savedAddress == "http://first.test:8210", "the address stays, so Settings offers a sign-in")
        #expect(try bench.signIns.key(for: first.address) == "new", "the sign-in is kept, since the server gave it")
        #expect(host.connection == first)
        #expect(bench.hasCopy(first), "nothing in the copy is lost")
    }

    @Test func aServerAtAnotherAddressIsRefusedAndTheLibraryStaysOpen() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.useFailure.withLock { $0 = MarfaError.wrongServer(expected: "a", got: "b", message: "Another server.") }
        await expect(.unavailable(message: "Another server.")) { () throws(MarfaHost.Problem) in
            try await host.signInAgain(via: host.scripted("new"))
        }
        #expect(host.source === source)
        #expect(source.calls == ["use"])
    }

    /// A library that is not open, because its launch failed, is opened on the new sign-in.
    @Test func aLibraryThatIsNotOpenIsOpenedOnTheNewSignIn() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let host = bench.host()
        await host.launch()
        #expect(host.source == nil)
        #expect(host.state == .keyRefused)

        try await host.signInAgain(via: host.scripted("new"))
        #expect(host.source === bench.servers.last)
        #expect(bench.servers.opened.count == 1)
        #expect(try bench.signIns.key(for: first.address) == "new")
    }
}
