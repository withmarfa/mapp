import Foundation
import Marfa
import Synchronization
import Testing
@testable import MarfaMac

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
        let bench = HostBench()
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
        let bench = HostBench()
        bench.defaults.set("https://marfa.test:443", forKey: "MarfaAddress")
        bench.signIns.hold("old", for: host443)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)

        let helper = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: typed, via: host.scripted("new")) }
        #expect(helper == nil)
        #expect(host.source === source)
        #expect(bench.servers.opened.count == 1)
        #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") }, "\(bench.signIns.calls)")
        #expect(source.given == ["new"])
        #expect(host.connection == host443, "the saved text still names the copy")
    }

    @Test func anotherServerTypedIsStillAnotherServer() async throws {
        let bench = HostBench()
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
        let bench = HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.storeBusy(message: "Busy.") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.notConfirmed))

        let told = await leaving(host)
        guard case .notRemoved(_, let copy?, let approvalAt)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(copy != "")
        #expect(approvalAt == "http://first.test:8210")
        let toldProblem = try #require(told)
        let notice = try #require(MarfaSettingsModel.notice(for: toldProblem))
        #expect(notice.message.contains("marfa apps revoke"))
        #expect(notice.message.contains("http://first.test:8210"), "the server is named by its address")
        #expect(notice.title.contains("May Still Be Approved") || notice.message.contains("ended the approval"))
    }

    @Test func anApprovalTheServerDidNotEndIsToldWhenTheCopyHeldMoreWrites() async throws {
        let bench = HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.unsentDiffers(path: "p", unsent: 3, message: "") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.notConfirmed))

        let told = await leaving(host)
        guard case .copyKept(_, _, let approvalAt)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(approvalAt == "http://first.test:8210")
    }

    @Test func aSignOutTheServerConfirmedAddsNothingToACopyThatCouldNotBeRemoved() async throws {
        let bench = HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host(remover: { _, _ in throw MarfaError.storeBusy(message: "Busy.") })
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.signIns.script(signOut: .success(.endedAtServer))

        let told = await leaving(host)
        guard case .notRemoved(_, _, let approvalAt)? = told else {
            Issue.record("\(String(describing: told))")
            return
        }
        #expect(approvalAt == nil)
    }

    /// After Use a Different Server, the words are about the server left, not the one now open.
    @Test func aSwitchThatLeavesAnApprovalNamesThePreviousServer() async throws {
        let bench = HostBench()
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
        #expect(notice.message.contains("http://first.test:8210"), "the previous server is named by its address: \(notice.message)")
        #expect(!notice.message.contains("second.test"))
        #expect(notice.message.contains("marfa apps revoke <id>"))
        #expect(!notice.message.contains("older app entry"))
        #expect(host.connection?.address.absoluteString == "http://second.test:8210")
    }

    @Test(arguments: [MarfaHost.Problem.notRevoked(address: "https://marfa.test"), .copyKept(.changed(now: 2), signIn: nil, approvalAt: "https://marfa.test"), .notRemoved(signIn: nil, copy: "x", approvalAt: "https://marfa.test")])
    func theApprovalWordsNeverClaimWhatTheServerHoldsOrThatTheAppIsSignedIn(problem: MarfaHost.Problem) throws {
        for reached in [MarfaSettingsModel.Reached.left, .switched] {
            let notice = try #require(MarfaSettingsModel.notice(for: problem, reached: reached))
            let text = notice.title + " " + notice.message
            #expect(text.contains("marfa apps list"))
            #expect(text.contains("marfa apps revoke"))
            #expect(text.contains("https://marfa.test"))
            #expect(text.contains("couldn’t confirm") || text.contains("May Still"), "\(text)")
            for claim in ["still lists", "Connected apps", "You are signed in", "Is Still Approved"] {
                #expect(!text.contains(claim), "\(reached): “\(text)” says “\(claim)”")
            }
        }
    }

    // MARK: A clean-up sign-out

    /// A connect whose copy would not open drops the sign-in it made: if the server did not confirm that, the person is told.
    @Test func aConnectThatFailsAfterSigningInTellsWhenTheApprovalMayStand() async throws {
        let bench = HostBench()
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
        let bench = HostBench()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .denied, message: "No.") }
        bench.signIns.script(signOut: .success(outcome))
        let host = bench.host()
        _ = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(host.notices.waiting.isEmpty)
    }

    // MARK: An address that is not a Marfa server

    /// A reply that is no OAuth error, such as a proxy's page, reaches the app as the package's `http_<status>`.
    @Test(arguments: ["http_404", "http_403", "http_200"])
    func anAddressThatAnswersWithAPlainStatusStartsNoSignInAndIsToldAsNotMarfa(code: String) async throws {
        let bench = HostBench()
        bench.signIns.script(browser: [.failure(SignInError.refused(code: code, message: "Not Found"))])
        let host = bench.host()
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "https://example.test", via: .browser) }
        #expect(told == .signIn(.notMarfa))
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func aSwitchToAnAddressThatIsNotAMarfaServerLeavesTheLibrary() async throws {
        let bench = HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        bench.signIns.script(browser: [.failure(SignInError.refused(code: "http_404", message: "Not Found"))])
        let told = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: "https://example.test", via: .browser) }
        #expect(told == .signIn(.notMarfa))
        #expect(host.source === source)
        #expect(host.connection?.address.absoluteString == "http://first.test:8210")
    }

    // MARK: A clean-up sign-out that throws

    /// The sign-out ran into the Keychain held elsewhere before it forgot or revoked anything: the sign-in may still be
    /// kept and the approval may stand, so the person is told, never left to find out.
    @Test func aCleanUpSignOutThatThrowsTellsThatTheSignInAndApprovalMayStand() async throws {
        let bench = HostBench()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .denied, message: "No.") }
        bench.signIns.script(signOut: .failure(SignInError.heldElsewhere))
        let host = bench.host()
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(told != nil)
        #expect(host.notices.waiting.map(\.title) == [Words.signOutFailedTitle])
        let message = try #require(host.notices.waiting.first?.message)
        #expect(message.contains("http://first.test:8210"))
        #expect(message.contains("may still be kept") && message.contains("marfa apps revoke <id>"))
        #expect(!message.contains("heldElsewhere") && !message.contains("Another process"))
    }

    @Test func anAbandonedSwitchWhoseCleanUpSignOutThrowsTellsTheSame() async throws {
        let bench = HostBench()
        let first = try MarfaConnection(address: "http://first.test:8210")
        let inner = bench.servers.opener
        let host = bench.host(opener: { connection, signIns, location in
            if connection == first { return try await inner(connection, signIns, location) }
            throw SourceFailure(kind: .denied, message: "No.")
        })
        try await host.connect(address: "http://first.test:8210", key: "k")
        bench.signIns.script(signOut: .failure(SignInError.heldElsewhere))
        _ = await problem { () throws(MarfaHost.Problem) in try await host.changeAddress(to: "http://second.test:8210", via: host.scripted("k")) }
        #expect(host.notices.waiting.map(\.title) == [Words.signOutFailedTitle])
        #expect(host.notices.waiting.first?.message.contains("http://second.test:8210") == true)
    }

    // MARK: One server, two spellings of its default port

    /// Typing the spelling with the port while connected without it is Sign In Again: no new copy, no sign-out.
    @Test func typingTheSpellingWithThePortWhileConnectedWithoutItSignsInAgain() async throws {
        let bench = HostBench()
        let host = bench.host()
        try await host.connect(address: "https://marfa.test", key: "old")
        let source = try #require(bench.servers.last)
        try await host.changeAddress(to: "https://marfa.test:443", key: "new")
        #expect(host.source === source)
        #expect(bench.servers.opened.count == 1)
        #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") }, "\(bench.signIns.calls)")
        #expect(source.given == ["new"])
        #expect(host.connection?.address.absoluteString == "https://marfa.test")
        #expect(bench.location.folders().count == 1, "no copy was made for the other spelling")
    }

    /// A copy kept under one spelling is the copy the other spelling opens, with its writes.
    @Test func aKeptCopyIsOpenedByTheOtherSpellingWithItsWrites() async throws {
        let bench = HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host()
        try await host.connect(address: "https://marfa.test:443", key: "k")
        try await host.disconnect(.keepCopy)
        let keptStore = bench.location.store(for: host443)
        #expect(try await WorkingCopy.unsentWrites(in: keptStore).writes.count == 2)
        bench.servers.storedWrites.withLock { $0 = 0 }

        try await host.connect(address: "https://marfa.test", key: "again")
        let source = try #require(bench.servers.last)
        #expect(source.connection == (try MarfaConnection(address: "https://marfa.test")))
        #expect(source.store.withLock { $0 } == keptStore)
        #expect(try await source.storeWrites.count == 2, "the kept queue is the one opened")
        #expect(bench.location.folders().count == 1)
        #expect(bench.savedAddress == "https://marfa.test")
    }

    /// A discard mark made under one spelling is honoured under the other: it names the copy, not the text.
    @Test func aDiscardMarkIsHonouredUnderTheOtherSpelling() async throws {
        let bench = HostBench()
        let folder = bench.location.directory(for: host443)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: bench.location.store(for: host443))
        await copy.close()
        let host = bench.host()
        let other = try MarfaConnection(address: "https://marfa.test")
        host.markDiscarded(host443, agreed: MarfaHost.Agreed(ids: []))
        try await host.clearDiscarded(other)
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty != false)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    // MARK: Nothing raw after a sign-in

    nonisolated private static let raw = "NSCocoaErrorDomain Code=513 errSecItemNotFound /Users/someone/Library/copy.sqlite"

    @Test func aCopyThatCannotBeMadeAfterSigningInIsToldInTheAppsWords() async throws {
        let bench = HostBench()
        let host = bench.host(opener: { _, _, _ in throw NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [NSLocalizedDescriptionKey: Self.raw]) })
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
        let toldProblem = try #require(told)
        let notice = try #require(MarfaSettingsModel.notice(for: toldProblem))
        for fragment in ["NSCocoa", "errSec", "/Users", "513"] {
            #expect(!notice.message.contains(fragment), "“\(notice.message)” shows “\(fragment)”")
        }
    }

    @Test func aCopyThatCannotBeMadeForTheServerSwitchedToIsToldInTheAppsWords() async throws {
        let bench = HostBench()
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

    @Test func aSignInAgainThatCannotReadTheCredentialIsToldInTheAppsWords() async throws {
        let bench = HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.useFailure.withLock { $0 = NSError(domain: NSOSStatusErrorDomain, code: -25300, userInfo: [NSLocalizedDescriptionKey: Self.raw]) }
        let told = await problem { () throws(MarfaHost.Problem) in try await host.signInAgain(via: host.scripted("new")) }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
        #expect(host.source === source)
    }

    /// A package error that carries the system's own words is told in the app's, whichever step it stopped.
    @Test func aStoreErrorFromThePackageIsToldInTheAppsWordsWhenTheCopyIsOpened() async throws {
        let raw = "SQLite says: disk I/O error at /Users/someone/Library/copy.sqlite"
        let bench = HostBench()
        let host = bench.host(opener: { _, _, _ in throw MarfaError.store(message: raw) })
        let told = await problem { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test:8210", key: "k") }
        #expect(told == .unavailable(message: Words.copyCouldNotBeOpened))
        let toldProblem = try #require(told)
        let notice = try #require(MarfaSettingsModel.notice(for: toldProblem))
        for fragment in ["SQLite", "/Users", "I/O"] {
            #expect(!notice.message.contains(fragment), "“\(notice.message)” shows “\(fragment)”")
        }
    }

    @Test(arguments: [
        MarfaError.io(message: "No such file /Users/someone/x"), .network(message: "connection refused (os error 61)"),
        .storageFull(message: "SQLITE_FULL"), .fault(message: "unreachable state 7"),
    ])
    func noPackageMessageIsToldAsItIs(error: MarfaError) {
        let words = Words.message(for: error)
        #expect(!words.contains(error.message), "\(words)")
    }

    // MARK: A damaged copy, an unreadable Keychain

    @Test func aDamagedCopyIsToldAsOneAndNotAsAPermissionsProblem() {
        let stopped = Words.message(for: .storeDamaged(path: "/Users/someone/Marfa/abc/copy.sqlite", reason: "malformed", unsent: 3, setAsideStopped: true, message: "SQLite"))
        #expect(stopped.contains("damaged") && stopped.contains("/Users/someone/Marfa/abc"))
        #expect(!stopped.contains("copy.sqlite") && !stopped.contains("SQLite") && !stopped.contains("change its own files"))
        #expect(stopped.contains("3 changes") && stopped.contains("stopped partway") && stopped.contains("Open the library again to finish it."))

        let whole = Words.message(for: .storeDamaged(path: "/Users/someone/Marfa/abc/copy.sqlite", reason: "malformed", unsent: nil, setAsideStopped: false, message: "SQLite"))
        #expect(whole.contains("damaged") && whole.contains("couldn’t read whether it holds changes"))
        #expect(!whole.contains("partway") && !whole.contains("Open the library again"))

        #expect(Words.message(for: .storeDamaged(path: "", reason: "r", unsent: 0, setAsideStopped: false, message: "m")).contains("holds no changes"))
    }

    @Test func aMissingKeychainIsToldAsAnUnreadableSignIn() {
        #expect(Words.message(for: .noKeychain(message: "no keychain")) == Words.signInUnreadable)
    }

    @Test func aReplacedApprovalIsToldHowToFindTheEarlierOne() {
        let words = Words.replacedApproval(address: "https://marfa.test")
        #expect(words.contains("Run “marfa apps list” with the command line signed in to https://marfa.test as the owner."))
        #expect(words.contains("Use the approval date to identify the earlier “Marfa for Mac” approval."))
        #expect(words.contains("If you can identify it, run “marfa apps revoke <id>” with that entry’s ID."))
    }
}
