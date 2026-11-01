import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// The Marfa section of Settings, through the model the view holds, so its steps and words are tested without a
/// window. The host is on fakes, in memory, and a temporary store location: never the Keychain, and never the
/// default location.
@Suite(.hangLimit)
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

    private func connect(_ model: MarfaSettingsModel, to address: String = "http://first.test:8210", key: String = "key-1") async {
        model.address = address
        _ = model.host.scripted(key)
        await model.connect()
    }

    // MARK: Connecting

    @Test func connectingNeedsOnlyAnAddressAndHandsOverEditsFirst() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        #expect(!model.canConnect)
        model.address = " http://first.test:8210/ "
        #expect(model.canConnect, "the sign-in is made in the browser, so no key is typed")
        _ = model.host.scripted("key-1")

        await model.connect()
        #expect(model.host.connection == first)
        #expect(try bench.signIns.key(for: first.address) == "key-1")
        #expect(bench.signIns.calls == ["browser http://first.test:8210"])
        #expect(model.address == "")
        #expect(model.notice == nil)
        #expect(flushed.count == 1)
        #expect(model.isConnected)
        #expect(model.code == nil)
    }

    @Test func anAddressThatIsNoServerIsToldInWords() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        await connect(model, to: "marfa.example", key: "k")
        let notice = try #require(model.notice)
        #expect(notice.title == "Check the Address")
        #expect(notice.message == "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://.")
        #expect(model.address == "marfa.example", "what was typed is kept for another try")
        #expect(!model.isConnected)
        #expect(bench.servers.opened.isEmpty)
        #expect(flushed.count == 0, "nothing changed, so nothing was handed over")
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
        #expect(try bench.signIns.key(for: first.address) == nil, "a sign-in for a server that did not open is not kept")
        #expect(bench.signIns.calls == ["browser http://first.test:8210", "signOut http://first.test:8210"])
    }

    @Test(arguments: [
        MarfaHost.Problem.notSignedIn, .signIn(.denied), .signIn(.expired), .signIn(.refused("The server refused it.")),
        .signIn(.unreachable("Could not connect.")), .signIn(.inUse), .signIn(.keychain("SecItemAdd failed: -25299.")),
        .notRevoked, .notRemoved(signIn: "errSecItemNotFound", copy: nil),
        .notRemoved(signIn: nil, copy: "NSCocoaErrorDomain 513"), .notConnected, .busy, .notAServer,
        .otherVersion(unsent: 2), .otherVersion(unsent: nil), .inUse,
        .copyKept(.changed(now: 2), signIn: nil), .copyKept(.unreadable(folder: "/Library/Marfa/ab12"), signIn: "errSecItemNotFound"),
        .copyKept(.notMapps(folder: "/Library/Marfa/ab12"), signIn: nil), .cannotDiscard(folder: "/Library/Marfa/ab12")
    ])
    func everyProblemIsToldAsWhatHappenedAndWhatToDo(problem: MarfaHost.Problem) throws {
        let notice = try #require(MarfaSettingsModel.notice(for: problem))
        #expect(!notice.title.isEmpty)
        #expect(notice.message.hasSuffix("."))
        for raw in ["-25299", "SecItem", "errSec", "NSCocoa", "network:", "Domain"] {
            #expect(!notice.message.contains(raw), "“\(notice.message)” shows “\(raw)”")
        }
    }

    @Test func aSignInThePersonStoppedIsNotToldBack() {
        #expect(MarfaSettingsModel.notice(for: .signIn(.canceled)) == nil)
    }

    @Test func eachWayASignInEndsHasItsOwnWords() throws {
        func title(_ outcome: SignInOutcome) throws -> String {
            try #require(MarfaSettingsModel.notice(for: .signIn(outcome))).title
        }
        #expect(try title(.denied) == "MAPP Wasn’t Approved")
        #expect(try title(.expired) == "The Code Expired")
        #expect(try title(.refused("No.")) == "The Server Refused the Sign-In")
        #expect(try title(.unreachable("Offline.")) == "Can’t Reach the Server")
        #expect(try title(.keychain("Denied.")) == "Can’t Keep the Sign-In")
        #expect(try title(.inUse) == "The Sign-In Is in Use")
        let revoke = try #require(MarfaSettingsModel.notice(for: .notRevoked))
        #expect(revoke.title == "Disconnected, but MAPP Is Still Approved")
        #expect(revoke.message.contains("Connected apps"))
        #expect(revoke.message.contains("Disconnect"))
    }

    @Test func theQuestionAboutWaitingChangesIsAskedNotTold() {
        #expect(MarfaSettingsModel.notice(for: .changesWaiting(.fake(2))) == nil)
    }

    // MARK: Signing in

    @Test func aCanceledBrowserSignInSaysNothingAndKeepsWhatWasTyped() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.signIns.script(browser: [.failure(SignInError.canceled)])
        model.address = "http://first.test:8210"
        await model.connect()
        #expect(model.notice == nil)
        #expect(model.address == "http://first.test:8210")
        #expect(!model.isConnected)
        #expect(!model.isWorking)
    }

    @Test func aSignInTheServerRefusesIsToldWithTheServersWords() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.signIns.script(browser: [.failure(SignInError.refused(code: "invalid_client", message: "This app is not known."))])
        model.address = "http://first.test:8210"
        await model.connect()
        #expect(model.notice?.title == "The Server Refused the Sign-In")
        #expect(model.notice?.message.hasPrefix("Nothing changed.") == true)
        #expect(!model.isConnected)
    }

    @Test func aSignInAgainOnlyReopensTheCopyAndLeavesNoNotice() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { model.host.state == .keyRefused })
        #expect(model.status.title == "Signed out")
        #expect(model.status.isProblem)

        _ = model.host.scripted("key-2")
        await model.signInAgain()
        #expect(model.notice == nil)
        #expect(try bench.signIns.key(for: first.address) == "key-2")
        #expect(model.host.source === bench.servers.last)
        #expect(bench.servers.opened.count == 2)
    }

    @Test func aCodeIsShownWhileTheModelWaitsAndForgottenAfterwards() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        let signIns = bench.signIns
        let address = first.address
        let (approved, approve) = AsyncStream<Void>.makeStream()
        signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "http://first.test:8210/device")!, completeAddress: nil,
            expiresAt: .distantFuture,
            finish: { for await _ in approved {}; signIns.save("approved", for: address) }))])
        model.address = "http://first.test:8210"
        let task = model.start(.connect(usingCode: true))
        #expect(await eventually { model.code?.code == "ABCD-1234" })
        #expect(model.isWorking)
        approve.finish()
        await task.value
        #expect(model.code == nil)
        #expect(model.isConnected)
        #expect(try signIns.key(for: first.address) == "approved")
    }

    @Test func cancellingWhileWaitingForACodeStopsWithoutANoticeAndKeepsNothing() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        let (never, hold) = AsyncStream<Void>.makeStream()
        defer { hold.finish() }
        bench.signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "http://first.test:8210/device")!, completeAddress: nil,
            expiresAt: .distantFuture, finish: { for await _ in never {}; try Task.checkCancellation() }))])
        model.address = "http://first.test:8210"
        let task = model.start(.connect(usingCode: true))
        #expect(await eventually { model.code != nil })
        model.cancelSignIn()
        await task.value
        #expect(model.code == nil)
        #expect(model.notice == nil)
        #expect(!model.isConnected)
        #expect(!model.isWorking)
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    @Test func aCodeThatExpiredIsToldAndCanBeAskedForAgain() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.signIns.script(code: [.success(CodeSignIn(
            code: "X", address: URL(string: "http://first.test:8210/device")!, completeAddress: nil,
            expiresAt: .now, finish: { throw SignInError.expired }))])
        model.address = "http://first.test:8210"
        await model.connect(usingCode: true)
        #expect(model.notice?.title == "The Code Expired")
        #expect(model.code == nil)
        #expect(!model.isConnected)
        #expect(model.canConnect)
    }

    @Test func aCopyThatCannotOpenAfterSigningInAgainIsToldAsSuch() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }
        _ = model.host.scripted("key-2")
        await model.signInAgain()
        #expect(model.notice?.title == "Can’t Open the Library")
        #expect(model.notice?.message == "You are signed in again, but the copy of your library on this Mac can’t be opened. The store is damaged.")
        #expect(try bench.signIns.key(for: first.address) == "key-2")
    }

    /// A switch that is done but for removing the old server's sign-in says it switched rather than disconnected.
    @Test func aSwitchThatLeavesTheOldSignInBehindSaysItSwitched() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        bench.signIns.script(signOut: .failure(SourceFailure(kind: .denied, message: "The keychain refused.")))
        model.otherAddress = "http://second.test:8210"
        _ = model.host.scripted("key-2")
        await model.switchServer()

        #expect(model.host.connection == second)
        #expect(model.otherAddress == "")
        let notice = try #require(model.notice)
        #expect(notice.title == "Switched Servers, but Not Everything Was Removed")
        #expect(notice.message == "The previous server’s sign-in is still in your Keychain. Remove it in Keychain Access.")
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
        #expect(try bench.signIns.key(for: first.address) == nil)
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

        await model.answer(.keepCopy)
        #expect(model.departure == nil)
        #expect(!model.isConnected)
        #expect(bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == nil, "the sign-in goes, the copy stays")
    }

    @Test func discardingPassesTheChangesThePersonWasShownAndRemovesTheCopy() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        await model.disconnect()
        #expect(model.departure?.unsent == .fake(2))

        await model.answer(.discardCopy)
        #expect(model.departure == nil)
        #expect(model.notice == nil)
        #expect(!model.isConnected)
        #expect(!bench.hasCopy(first))
    }

    /// A write that lands while the person decides is not one they were shown, so they are asked again.
    @Test func aChangeThatArrivesAfterTheQuestionIsAskedAgainAndTheCopyIsKept() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 2 })
        await model.disconnect()
        #expect(model.departure?.unsent?.count == 2)

        source.report.set(SyncReport(waiting: 3, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 3 })
        let store = bench.location.store(for: first)
        let copy = try await WorkingCopy.open(store: store)
        _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": .string("late")]))
        await copy.close()
        await model.answer(.discardCopy)
        let departure = try #require(model.departure)
        #expect(departure.isAskedAgain)
        #expect(departure.unsent?.count == 3)
        #expect(model.isConnected)
        #expect(bench.hasCopy(first), "nothing is discarded that the person was not shown")

        await model.answer(.discardCopy)
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
        #expect(try bench.signIns.key(for: first.address) == "key-1")
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
        _ = model.host.scripted("key-2")
        await model.switchServer()
        #expect(model.departure?.kind == .switchServer(usingCode: false))
        #expect(model.host.connection == first, "nothing moved yet")
        #expect(flushed.count == before + 1)

        await model.answer(.keepCopy)
        #expect(model.departure == nil)
        #expect(model.host.connection == second)
        #expect(bench.hasCopy(first))
        #expect(model.otherAddress == "")
    }

    // MARK: Canceling

    /// The answer to the question about waiting changes starts the sign-in on the other server, which Cancel stops
    /// like any other, and the question is gone from over it.
    @Test func aSwitchAnsweredAfterTheQuestionCanBeCanceledFromTheCodeSection() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        try #require(bench.servers.last).report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { model.host.waitingChanges == 1 })
        model.otherAddress = "http://second.test:8210"
        await model.switchServer()
        #expect(model.departure != nil)

        let signIns = bench.signIns
        signIns.onBrowser.withLock { $0 = { try await Task.sleep(for: .seconds(3)) } }
        let answering = Task { await model.answer(.keepCopy) }
        #expect(await eventually { signIns.calls.contains("browser http://second.test:8210") })
        #expect(model.departure == nil, "the question does not stay over the sign-in")
        #expect(model.canCancelSignIn)

        model.cancelSignIn()
        await answering.value
        #expect(model.notice == nil)
        #expect(model.host.connection == first)
        #expect(try signIns.key(for: second.address) == nil)
        #expect(bench.hasCopy(first))
    }

    /// Once the person has approved, the sign-in is being used to open the copy: stopping then would revoke it.
    @Test func cancelingWhileTheCopyOpensAfterTheApprovalChangesNothing() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        bench.servers.slow.withLock { $0 = true }
        _ = model.host.scripted("key-1")
        model.address = "http://first.test:8210"
        let task = model.start(.connect(usingCode: false))
        #expect(await eventually { bench.servers.opening.withLock { $0 } })

        #expect(!model.canCancelSignIn, "Cancel is not offered once the approval is being used")
        model.cancelSignIn()
        bench.servers.slow.withLock { $0 = false }
        await task.value
        #expect(model.notice == nil)
        #expect(model.isConnected)
        #expect(try bench.signIns.key(for: first.address) == "key-1")
        #expect(!bench.signIns.calls.contains("signOut http://first.test:8210"))
    }

    // MARK: A sign-in the server ended

    @Test func aSignedOutLibraryCanBeLeftByDisconnectingAndStartingAgain() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { model.host.state == .keyRefused })

        model.requestDisconnect()
        #expect(model.isConfirmingDisconnect)
        await model.disconnect()
        #expect(model.host.configuredConnection == nil, "the connect page is back")
        #expect(try bench.signIns.key(for: first.address) == nil)
        #expect(bench.savedAddress == nil)
    }

    @Test func disconnectingTellsWhenTheServerCouldNotEndTheApproval() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        bench.signIns.script(signOut: .success(false))
        await model.disconnect()
        #expect(!model.isConnected)
        #expect(bench.savedAddress == nil)
        #expect(model.notice?.title == "Disconnected, but MAPP Is Still Approved")
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
        async let one: Void = model.connect()
        #expect(await eventually { model.isWorking })
        #expect(!model.canConnect)
        await model.connect()
        #expect(flushed.count == 1)
        bench.servers.slow.withLock { $0 = false }
        await one
        #expect(model.isConnected)
    }
}
