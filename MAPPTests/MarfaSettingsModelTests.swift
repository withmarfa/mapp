import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// The Marfa section of Settings, through the model the view holds, so its steps and words are tested without a
/// window. The host is on fakes, in memory, and a temporary store location: never the Keychain, a browser, or the
/// default location.
@MainActor struct MarfaSettingsModelTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    /// A model on a host, counting how often the host asked the pages to hand over their edits.
    private func model(_ bench: HostBench) -> (MarfaSettingsModel, flushed: Counter) {
        let flushed = Counter()
        let host = bench.host()
        host.handOverEdits = { flushed.count += 1; return true }
        return (MarfaSettingsModel(host: host), flushed)
    }

    @MainActor final class Counter {
        var count = 0
    }

    private func connect(_ model: MarfaSettingsModel, to address: String = "http://first.test:8210") async {
        model.address = address
        await model.signIn(with: testBrowser)
    }

    // MARK: Signing in

    @Test func signingInClearsTheFormAndHandsOverEditsFirst() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        #expect(!model.canSignIn)
        model.address = "   "
        #expect(!model.canSignIn, "a blank address is no address")
        model.address = " HTTP://First.test:8210/ "
        #expect(model.canSignIn)

        await model.signIn(with: testBrowser)
        #expect(model.host.connection == first)
        #expect(bench.signIns.calls == ["signIn http://first.test:8210"])
        #expect(model.address == "")
        #expect(model.notice == nil)
        #expect(flushed.count == 1)
        #expect(model.isConnected)
    }

    @Test func anAddressThatIsNoServerIsToldInWords() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        await connect(model, to: "marfa.example")
        let notice = try #require(model.notice)
        #expect(notice.title == "Check the Address")
        #expect(notice.message == "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://.")
        #expect(model.address == "marfa.example", "what was typed is kept for another try")
        #expect(!model.isConnected)
        #expect(bench.signIns.calls.isEmpty, "the browser never opened")
        #expect(bench.servers.opened.isEmpty)
        #expect(flushed.count == 0, "nothing changed, so nothing was handed over")
    }

    /// Closing the browser is the person's own choice, so it is not told as a problem.
    @Test func aCanceledSignInSaysNothingAndKeepsTheAddress() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.signIns.answers.withLock { $0 = [.canceled] }
        await connect(model)
        #expect(model.notice == nil)
        #expect(model.address == "http://first.test:8210")
        #expect(!model.isConnected)
    }

    @Test func aDeclinedSignInSaysHowToApproveMAPP() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.signIns.answers.withLock { $0 = [.denied] }
        await connect(model)
        #expect(model.notice?.title == "MAPP Wasn’t Approved")
        #expect(model.notice?.message == "To use your library in MAPP, sign in again and approve MAPP.")
        #expect(!model.isConnected)
    }

    @Test func aFailureToOpenTheCopyIsToldWithoutRawErrorText() async throws {
        let bench = try HostBench()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }
        let (model, _) = model(bench)
        await connect(model)
        let notice = try #require(model.notice)
        #expect(notice.title == "Can’t Open the Library")
        #expect(notice.message == "The copy of your library on this Mac can’t be opened. The store is damaged.")
        #expect(!model.isConnected)
        #expect(bench.signIns.token(for: first) == nil, "a sign-in for a server that did not open is not kept")
    }

    @Test(arguments: [
        MarfaHost.Problem.notApproved, .signInFailed(message: "network: refused"), .signedOut,
        .keychain(message: "SecItemCopyMatching failed: -25300"), .notRemoved(signIn: "errSecItemNotFound", copy: nil),
        .notRemoved(signIn: nil, copy: "NSCocoaErrorDomain 513"), .notConnected, .busy, .notAServer,
        .unavailable(message: ""),
    ])
    func everyProblemIsToldAsWhatHappenedAndWhatToDo(problem: MarfaHost.Problem) throws {
        let notice = try #require(MarfaSettingsModel.notice(for: problem))
        #expect(!notice.title.isEmpty)
        #expect(notice.message.hasSuffix("."))
        for raw in ["-25299", "SecItem", "errSec", "NSCocoa", "network:", "Domain"] {
            #expect(!notice.message.contains(raw), "“\(notice.message)” shows “\(raw)”")
        }
    }

    @Test func theQuestionAboutWaitingChangesIsAskedNotTold() {
        #expect(MarfaSettingsModel.notice(for: .changesWaiting(.fake(2))) == nil)
        #expect(MarfaSettingsModel.notice(for: .signInCanceled) == nil)
    }

    // MARK: Signing in again

    /// Signing in again closes the copy and opens it on the new sign-in, so the pages hand over their edits right
    /// before it closes, after the browser, when the person may have typed more.
    @Test func signingInAgainTakesThePagesEditsRightBeforeTheCopyCloses() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.signedOut)
        #expect(await eventually { model.isSignedOut })
        var seen: [[String]] = []
        model.host.handOverEdits = { seen.append(source.calls + bench.signIns.calls); return true }
        await model.signInAgain(with: testBrowser)
        #expect(seen == [["refresh", "signIn http://first.test:8210", "signIn http://first.test:8210"]])
        #expect(source.calls == ["refresh", "close"])
    }

    @Test func aSignedOutLibraryShowsAsSuchAndSignsInAgain() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.signedOut)
        #expect(await eventually { model.host.state == .signedOut })
        #expect(model.isSignedOut)
        #expect(model.status.title == "Signed out")
        #expect(model.status.detail == "MAPP needs your approval again. Sign in again to approve MAPP. Your changes stay on this Mac and are sent once you do.")
        #expect(model.status.isProblem)

        await model.signInAgain(with: testBrowser)
        #expect(model.notice == nil)
        #expect(!model.isSignedOut)
        #expect(model.host.source === bench.servers.last)
        #expect(bench.servers.opened.count == 2)
    }

    @Test func aSignInAgainThatOpensNoCopyIsToldAsSignedIn() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let (model, _) = model(bench)
        await model.host.launch()
        #expect(model.isSignedOut)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }

        await model.signInAgain(with: testBrowser)
        #expect(bench.signIns.token(for: first) != nil)
        #expect(model.notice?.title == "Can’t Open the Library")
        #expect(model.notice?.message == "MAPP signed in again, but the copy of your library on this Mac can’t be opened. The store is damaged.")
    }

    /// A switch that is done but for signing out of the old server says it switched rather than disconnected.
    @Test func aSwitchThatLeavesTheOldSignInBehindSaysItSwitched() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        bench.signIns.failsSignOut.withLock { $0 = true }
        model.otherAddress = "http://second.test:8210"
        await model.switchServer(with: testBrowser)

        #expect(model.host.connection == second)
        #expect(model.otherAddress == "")
        let notice = try #require(model.notice)
        #expect(notice.title == "Switched Servers, but Not Everything Was Removed")
        #expect(notice.message == "MAPP is still signed in to the previous server. To remove MAPP’s access, revoke it on that server.")
    }

    @Test func aCopyLeftBehindIsToldAgainstWhatTheStepDid() throws {
        let problem = MarfaHost.Problem.notRemoved(signIn: nil, copy: "NSCocoaErrorDomain 513")
        #expect(MarfaSettingsModel.notice(for: problem, reached: .left)?.title == "Disconnected, but Not Everything Was Removed")
        #expect(MarfaSettingsModel.notice(for: problem, reached: .switched)?.title == "Switched Servers, but Not Everything Was Removed")
        let notOpened = try #require(MarfaSettingsModel.notice(for: problem, reached: .notOpened))
        #expect(notOpened.title == "Can’t Open the Library")
        #expect(!notOpened.message.contains("NSCocoa"))
    }

    // MARK: Leaving a copy

    @Test func disconnectingWithNothingWaitingAsksOnceThenRemovesTheCopy() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        await connect(model)
        let before = flushed.count

        model.requestDisconnect()
        #expect(model.isConfirmingDisconnect)
        #expect(model.isConnected, "asking changes nothing")
        #expect(flushed.count == before)

        await model.disconnect()
        #expect(!model.isConnected)
        #expect(!bench.hasCopy(first))
        #expect(bench.signIns.token(for: first) == nil)
        #expect(model.departure == nil)
        #expect(flushed.count == before + 1)
    }

    @Test func disconnectingWithChangesWaitingAsksWhatToDoAndShowsWhatWouldBeLost() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.unsentTexts.withLock { $0 = [SyncContent(title: "Trip to Lisbon", body: "Book the hotel")] }
        source.report.set(SyncReport(waiting: 3, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 3 })

        model.requestDisconnect()
        #expect(!model.isConfirmingDisconnect, "the question about the changes is the confirmation")
        #expect(await eventually { model.departure != nil })
        let departure = try #require(model.departure)
        #expect(departure.kind == .disconnect)
        #expect(departure.isAskedAgain == false)
        let unsent = try #require(departure.unsent)
        #expect(unsent.count == 3)
        #expect(unsent.texts.map(\.content.plainText) == ["Trip to Lisbon\n\nBook the hotel"])
        #expect(Words.moreNotShown(unsent.count - unsent.texts.count) == "And 2 more changes whose text can’t be shown.")
        #expect(model.isConnected, "nothing is left until the person chooses")
        #expect(bench.hasCopy(first))
    }

    @Test func keepingTheCopyLeavesItOnDiskForTheSameServerToResume() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        await model.disconnect()
        #expect(model.departure != nil)

        await model.answer(.keepCopy, with: testBrowser)
        #expect(model.departure == nil)
        #expect(!model.isConnected)
        #expect(bench.hasCopy(first))
        #expect(bench.signIns.token(for: first) == nil, "the sign-in goes, the copy stays")
    }

    @Test func discardingPassesTheChangesThePersonWasShownAndRemovesTheCopy() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        await model.disconnect()
        #expect(model.departure?.unsent == .fake(2))

        await model.answer(.discardCopy, with: testBrowser)
        #expect(model.departure == nil)
        #expect(model.notice == nil)
        #expect(!model.isConnected)
        #expect(!bench.hasCopy(first))
    }

    /// A write that lands while the person decides is not one they were shown, so they are asked again.
    @Test func aChangeThatArrivesAfterTheQuestionIsAskedAgainAndTheCopyIsKept() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        await model.disconnect()
        #expect(model.departure?.unsent?.count == 2)

        source.report.set(SyncReport(waiting: 3, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 3 })
        await model.answer(.discardCopy, with: testBrowser)
        let departure = try #require(model.departure)
        #expect(departure.isAskedAgain)
        #expect(departure.unsent?.count == 3)
        #expect(model.isConnected)
        #expect(bench.hasCopy(first), "nothing is discarded that the person was not shown")

        await model.answer(.discardCopy, with: testBrowser)
        #expect(model.departure == nil)
        #expect(!bench.hasCopy(first))
    }

    @Test func aCopyThatCannotBeReadIsAskedAboutWithoutACount() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        try #require(bench.servers.last).report.set(SyncReport())
        #expect(await eventually { model.host.report.queueRead == false })

        await model.disconnect()
        let departure = try #require(model.departure)
        #expect(departure.unsent == nil)
        #expect(bench.hasCopy(first))
    }

    @Test func cancellingLeavesEverythingAsItWas() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        await model.disconnect()
        model.cancelDeparture()
        #expect(model.departure == nil)
        #expect(model.isConnected)
        #expect(model.host.source != nil)
        #expect(bench.signIns.token(for: first) != nil)
        #expect(bench.hasCopy(first))
    }

    @Test func switchingServerAsksAboutTheCopyItLeavesAndKeepsItOnRequest() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        await connect(model)
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        let before = flushed.count

        model.otherAddress = "http://second.test:8210"
        await model.switchServer(with: testBrowser)
        #expect(model.departure?.kind == .switchServer)
        #expect(!bench.signIns.calls.contains("signIn http://second.test:8210"), "the browser waits for the answer")
        #expect(model.host.connection == first, "nothing moved yet")
        #expect(flushed.count == before + 1)

        await model.answer(.keepCopy, with: testBrowser)
        #expect(model.departure == nil)
        #expect(model.host.connection == second)
        #expect(bench.hasCopy(first))
        #expect(bench.signIns.calls.contains("signIn http://second.test:8210"))
        #expect(model.otherAddress == "")
    }

    // MARK: Words and what shows

    @Test func theStatusFollowsTheHost() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        #expect(model.status.title == "Not connected")
        await connect(model)
        let source = try #require(bench.servers.last)
        #expect(model.status.title == "Connecting…")
        source.state.set(.online)
        #expect(await eventually { model.status.title == "Connected" })
        source.state.set(.offline(reason: "network: refused"))
        #expect(await eventually { model.status.title == "Offline" })
    }

    @Test func aStepAlreadyUnderWayIsNotStartedTwice() async throws {
        let bench = try HostBench()
        bench.servers.slow.withLock { $0 = true }
        let (model, flushed) = model(bench)
        model.address = "http://first.test:8210"
        async let one: Void = model.signIn(with: testBrowser)
        #expect(await eventually { model.isWorking })
        #expect(!model.canSignIn)
        await model.signIn(with: testBrowser)
        #expect(flushed.count == 1)
        bench.servers.slow.withLock { $0 = false }
        await one
        #expect(model.isConnected)
    }
}
