import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// How a sign-in, a sign-out and a switch end: which address is which server, what the person is told when the server
/// might still hold an approval, and that nothing the package or the system said is shown.
@Suite(.hangLimit)
@MainActor struct MarfaHostSignInEndingsTests {
    private let host443 = try! MarfaConnection(address: "https://marfa.test:443")

    private func problem(_ work: () async throws(MarfaHost.Problem) -> Void) async -> MarfaHost.Problem? {
        do {
            try await work()
            return nil
        } catch {
            return error
        }
    }

    /// Leaves as a person does: asked what waits, they discard exactly that. What the step then told, if anything.
    private func leaving(_ host: MarfaHost) async -> MarfaHost.Problem? {
        let first = await problem { () throws(MarfaHost.Problem) in try await host.disconnect() }
        guard case .changesWaiting(let shown?)? = first else { return first }
        return await problem { () throws(MarfaHost.Problem) in try await host.disconnect(.discardCopy(shown)) }
    }

    // MARK: Which address is which server

    /// A saved address names its copy by the text it was saved as, so a saved port is read as saved: the copy and
    /// the writes waiting in it open, and none is orphaned.
    @Test func aSavedAddressWithTheSchemesOwnPortOpensItsOwnCopyAndKeepsItsWrites() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        bench.defaults.set("https://marfa.test:443", forKey: "MarfaAddress")
        bench.signIns.hold("k", for: host443)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last, "the saved address opened")
        #expect(source.connection.address.absoluteString == "https://marfa.test:443")
        #expect(host.connection == host443)
        #expect(bench.hasCopy(host443))
        #expect(try await source.storeWrites.count == 2, "the writes waiting in that copy are the ones it holds")
        #expect(bench.savedAddress == "https://marfa.test:443", "the saved address is not rewritten")
    }

    /// The same server typed without its port is Sign In Again: the copy stays open, nothing is signed out, and the
    /// discard marks and copy of the saved text are untouched.
    @Test(arguments: ["https://marfa.test", "https://marfa.test/", "HTTPS://Marfa.Test:443"])
    func theSameServerTypedWithoutItsPortSignsInAgainAndRevokesNothing(typed: String) async throws {
        let bench = try HostBench()
        bench.defaults.set("https://marfa.test:443", forKey: "MarfaAddress")
        bench.signIns.hold("old", for: host443)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)

        let helper = try await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: typed, via: host.scripted("new")) }
        #expect(helper == nil)
        #expect(host.source === source)
        #expect(bench.servers.opened.count == 1)
        #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") }, "\(bench.signIns.calls)")
        #expect(source.given == ["new"])
        #expect(host.connection == host443, "the saved text still names the copy")
    }

    @Test func anotherServerTypedIsStillAnotherServer() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "https://marfa.test:443", key: "a")
        try await host.changeAddress(to: "https://other.test", key: "b", choice: .discardNothing)
        #expect(bench.servers.opened.count == 2)
        #expect(host.connection?.address.absoluteString == "https://other.test")
    }

    // MARK: The sign-out told with the copy

    /// The server did not confirm the sign-out, and the copy could not be removed or held more writes than were shown:
    /// the person is told of both, not only of the copy.
    @Test func anApprovalTheServerDidNotEndIsToldWhenTheCopyCouldNotBeRemoved() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.storeBusy(message: "Busy.") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.notConfirmed))

        let told = await leaving(host)
        guard case .notRemoved(_, let copy?, let approvalStands)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(copy != "")
        #expect(approvalStands)
        let toldProblem = try #require(told)
        let notice = try #require(MarfaSettingsModel.notice(for: toldProblem))
        #expect(notice.message.contains("marfa apps revoke"))
        #expect(notice.title.contains("May Still Be Approved") || notice.message.contains("ended the approval"))
    }

    @Test func anApprovalTheServerDidNotEndIsToldWhenTheCopyHeldMoreWrites() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.unsentDiffers(path: "p", unsent: 3, message: "") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.notConfirmed))

        let told = await leaving(host)
        guard case .copyKept(_, _, let approvalStands)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(approvalStands)
    }

    @Test func aSignOutTheServerConfirmedAddsNothingToACopyThatCouldNotBeRemoved() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.storeBusy(message: "Busy.") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.endedAtServer))

        let told = await leaving(host)
        guard case .notRemoved(_, _, let approvalStands)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(!approvalStands)
    }

    /// After Use a Different Server, the words are about the server left, not the one now open.
    @Test func aSwitchThatLeavesAnApprovalNamesThePreviousServer() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.storeBusy(message: "Busy.") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.notConfirmed))

        let asked = await problem { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", via: host.scripted("k"), choice: nil)
        }
        guard case .changesWaiting(let shown?)? = asked else {
            Issue.record("\(String(describing: asked))")
            return
        }
        let told = try #require(await problem { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", via: host.scripted("k"), choice: .discardCopy(shown))
        })
        let notice = try #require(MarfaSettingsModel.notice(for: told, reached: .switched))
        #expect(notice.message.contains("previous server"), "\(notice.message)")
        #expect(notice.message.contains("marfa apps revoke"))
        #expect(host.connection?.address.absoluteString == "http://second.test:8210")
    }

    @Test(arguments: [MarfaHost.Problem.notRevoked, .copyKept(.changed(now: 2), signIn: nil, approvalStands: true), .notRemoved(signIn: nil, copy: "x", approvalStands: true)])
    func theApprovalWordsNeverClaimWhatTheServerHoldsOrThatMAPPIsSignedIn(problem: MarfaHost.Problem) throws {
        for reached in [MarfaSettingsModel.Reached.left, .switched] {
            let notice = try #require(MarfaSettingsModel.notice(for: problem, reached: reached))
            let text = notice.title + " " + notice.message
            #expect(text.contains("marfa apps list"))
            #expect(text.contains("marfa apps revoke"))
            #expect(text.contains("couldn’t confirm") || text.contains("May Still"), "\(text)")
            for claim in ["still lists", "Connected apps", "You are signed in", "Is Still Approved"] {
                #expect(!text.contains(claim), "\(reached): “\(text)” says “\(claim)”")
            }
        }
    }

    // MARK: A clean-up sign-out

    /// A connect whose copy would not open drops the sign-in it made: if the server did not confirm that, the person is told.
    @Test func aConnectThatFailsAfterSigningInTellsWhenTheApprovalMayStand() async throws {
        let bench = try HostBench()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .denied, message: "No.") }
        bench.signIns.script(signOut: .success(.notConfirmed))
        let host = bench.host()
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(told != nil)
        #expect(host.notices.waiting.map(\.title) == [Words.approvalMayStandTitle(.abandoned)])
        #expect(host.notices.waiting.first?.message.contains("marfa apps revoke") == true)
    }

    @Test(arguments: [SignOutOutcome.endedAtServer, .nothingKept])
    func aCleanUpSignOutThatEndedTheApprovalTellsNothing(outcome: SignOutOutcome) async throws {
        let bench = try HostBench()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .denied, message: "No.") }
        bench.signIns.script(signOut: .success(outcome))
        let host = bench.host()
        _ = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(host.notices.waiting.isEmpty)
    }

    // MARK: Reading the root before a sign-in

    @Test(arguments: [
        (MarfaError.unnamed(status: 404, message: "", server: nil), SignInOutcome.notMarfa),
        (MarfaError.decoding(message: "html"), .notMarfa),
        (MarfaError.network(message: "offline"), .unreachable),
    ])
    func anAddressThatIsNotAMarfaServerStartsNoSignIn(error: MarfaError, outcome: SignInOutcome) async throws {
        let bench = try HostBench()
        let host = bench.host(prober: { _ in throw error })
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "https://example.test", via: .browser) }
        #expect(told == .signIn(outcome))
        #expect(bench.signIns.calls.isEmpty, "no sign-in began")
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func aSwitchToAnAddressThatIsNotAMarfaServerStartsNoSignInAndLeavesTheLibrary() async throws {
        let bench = try HostBench()
        let probed = Mutex<[String]>([])
        let host = bench.host(prober: { connection in
            probed.withLock { $0.append(connection.address.absoluteString) }
            if connection.address.host() == "example.test" { throw MarfaError.decoding(message: "html") }
        })
        try await host.connect(address: "http://first.test:8210", key: "k")
        probed.withLock { $0 = [] }
        let source = try #require(bench.servers.last)
        let calls = bench.signIns.calls
        let told = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: "https://example.test", via: host.scripted("x")) }
        #expect(told == .signIn(.notMarfa))
        #expect(probed.withLock { $0 } == ["https://example.test"])
        #expect(bench.signIns.calls == calls)
        #expect(host.source === source)
    }

    /// Signing in again to the server already open reads no root: it is one the person already trusts.
    @Test func signingInAgainReadsNoRoot() async throws {
        let bench = try HostBench()
        let probed = Mutex(0)
        let host = bench.host(prober: { _ in probed.withLock { $0 += 1 } })
        try await host.connect(address: "http://first.test:8210", key: "k")
        let first = probed.withLock { $0 }
        try await host.connect(address: "http://first.test:8210", key: "again")
        #expect(probed.withLock { $0 } == first)
    }

    /// A root that answers as Marfa and then a sign-in the server refuses is still told as refused.
    @Test func aRefusalAfterAGoodRootReadIsToldAsRefused() async throws {
        let bench = try HostBench()
        bench.signIns.script(browser: [.failure(SignInError.refused(code: "invalid_client", message: "No."))])
        let host = bench.host()
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", via: .browser) }
        #expect(told == .signIn(.refused))
        #expect(bench.signIns.calls == ["browser http://first.test:8210"])
    }

    // MARK: Nothing raw after a sign-in

    nonisolated private static let raw = "NSCocoaErrorDomain Code=513 errSecItemNotFound /Users/someone/Library/copy.sqlite"

    @Test func aCopyThatCannotBeMadeAfterSigningInIsToldInMAPPsWords() async throws {
        let bench = try HostBench()
        let host = bench.host(opener: { _, _, _ in throw NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: Self.raw]) })
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
        let toldProblem = try #require(told)
        let notice = try #require(MarfaSettingsModel.notice(for: toldProblem))
        for fragment in ["NSCocoa", "errSec", "/Users", "513"] {
            #expect(!notice.message.contains(fragment), "“\(notice.message)” shows “\(fragment)”")
        }
    }

    @Test func aCopyThatCannotBeMadeForTheServerSwitchedToIsToldInMAPPsWords() async throws {
        let bench = try HostBench()
        let first = try MarfaConnection(address: "http://first.test:8210")
        let inner = bench.servers.opener
        let host = bench.host(opener: { connection, signIns, location in
            if connection == first { return try await inner(connection, signIns, location) }
            throw NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: Self.raw])
        })
        try await host.connect(address: "http://first.test:8210", key: "k")
        let told = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: "http://second.test:8210", via: host.scripted("k")) }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
    }

    @Test func aSignInAgainThatCannotReadTheCredentialIsToldInMAPPsWords() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.useFailure.withLock { $0 = NSError(domain: NSOSStatusErrorDomain, code: -25300, userInfo: [NSLocalizedDescriptionKey: Self.raw]) }
        let told = await problem { () throws(MarfaHost.Problem) in try await host.signInAgain(via: host.scripted("new")) }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
        #expect(host.source === source)
    }
}
