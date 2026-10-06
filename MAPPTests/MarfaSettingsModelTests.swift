import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// The Marfa section of Settings, through the model the view holds, so its steps and words are tested without a
/// window. The host is on fakes, in memory, and a temporary store location: never the Keychain, and never the
/// default location.
@MainActor struct MarfaSettingsModelTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    /// A model on a host, counting how often the host asked the pages to hand over their edits.
    private func model(_ bench: HostBench) -> (MarfaSettingsModel, flushed: Counter) {
        let flushed = Counter()
        let host = bench.host()
        host.handOverEdits = { flushed.count += 1 }
        return (MarfaSettingsModel(host: host), flushed)
    }

    @MainActor final class Counter {
        var count = 0
    }

    private func connect(_ model: MarfaSettingsModel, to address: String = "http://first.test:8210", key: String = "key-1") async {
        model.address = address
        model.key = key
        await model.connect()
    }

    // MARK: Connecting

    @Test func connectingKeepsTheKeyOutOfTheFormAndHandsOverEditsFirst() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        #expect(!model.canConnect)
        model.address = " http://first.test:8210/ "
        #expect(!model.canConnect, "a key is needed")
        model.key = "  "
        #expect(!model.canConnect, "a blank key is no key")
        model.key = "key-1"
        #expect(model.canConnect)

        await model.connect()
        #expect(model.host.connection == first)
        #expect(bench.keys.key(for: first) == "key-1")
        #expect(model.key == "", "the key is never shown again")
        #expect(model.address == "")
        #expect(model.notice == nil)
        #expect(flushed.count == 1)
        #expect(model.isConnected)
    }

    @Test func anAddressThatIsNoServerIsToldInWords() async throws {
        let bench = try HostBench()
        let (model, flushed) = model(bench)
        await connect(model, to: "marfa.example", key: "k")
        let notice = try #require(model.notice)
        #expect(notice.title == "Check the Address")
        #expect(notice.message == "That doesn’t look like a Marfa server. Use an address that starts with http:// or https://.")
        #expect(model.key == "k", "what was typed is kept for another try")
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
        #expect(bench.keys.key(for: first) == nil, "a key for a server that did not open is not kept")
    }

    @Test(arguments: [
        MarfaHost.Problem.noKey, .keyStore(message: "SecItemAdd failed: -25299"), .keyRefused,
        .serverUnreachable(reason: "network: refused"), .notRemoved(key: "errSecItemNotFound", copy: nil),
        .notRemoved(key: nil, copy: "NSCocoaErrorDomain 513"), .notConnected, .busy, .notAServer
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
    }

    // MARK: The connect review

    /// A copy that cannot take the new key is closed and opened again, so the pages hand over their edits right
    /// before it closes, after the wait on the server, when the person may have typed more.
    @Test func aCopyClosedOnANewKeyTakesThePagesEditsRightBeforeItCloses() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.closesOn.withLock { $0 = ["key-2"] }
        var seen: [[String]] = []
        model.host.handOverEdits = { seen.append(source.calls) }
        model.newKey = "key-2"
        await model.replaceKey()
        #expect(seen == [["refresh", "tryKey key-2"]])
        #expect(source.calls == ["refresh", "tryKey key-2", "close"])
    }

    // MARK: Forgetting a new key the host holds

    /// The old key was refused, so the new one is kept even though the copy closed on it; the field forgets it,
    /// and the person is told the key is kept and the library open again.
    @Test func aNewKeyKeptAsTheCopyOpensAgainIsForgottenAndToldAsKept() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        source.closesOn.withLock { $0 = ["key-2"] }
        model.newKey = "key-2"
        await model.replaceKey()

        #expect(bench.keys.key(for: first) == "key-2")
        #expect(model.host.source != nil)
        #expect(model.newKey == "", "the host holds the key, so the form does not")
        #expect(model.notice?.title == "Can’t Check the Key")
        #expect(model.notice?.message == "MAPP kept the new key and opened your library again, but couldn’t check the key with the server. The copy closed.")
    }

    /// A key that works is kept, so a new key the copy closed on is not, and stays in the field for another try.
    @Test func aNewKeyNotKeptStaysInTheFieldAndIsToldAsNotUsed() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.closesOn.withLock { $0 = ["key-2"] }
        model.newKey = "key-2"
        await model.replaceKey()

        #expect(bench.keys.key(for: first) == "key-1")
        #expect(model.newKey == "key-2")
        #expect(model.notice?.title == "Can’t Use the New Key")
        #expect(model.notice?.message == "MAPP couldn’t try the new key, so your library opened again with the key you had. Try again. The copy closed.")
    }

    /// With no copy open and no old key, the new key is kept though the copy still cannot be opened.
    @Test func aNewKeyKeptWhileTheCopyCannotOpenIsForgotten() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let (model, _) = model(bench)
        await model.host.launch()
        #expect(model.host.state == .keyRefused)
        #expect(model.host.source == nil)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }

        model.newKey = "key-2"
        await model.replaceKey()
        #expect(bench.keys.key(for: first) == "key-2")
        #expect(model.newKey == "")
        #expect(model.notice?.title == "Can’t Open the Library")
        #expect(model.notice?.message == "MAPP kept the new key, but the copy of your library on this Mac can’t be opened. The store is damaged.")
    }

    /// A switch that is done but for removing the old server's key forgets the new key it was given, and says it
    /// switched rather than disconnected.
    @Test func aSwitchThatLeavesTheOldKeyBehindForgetsTheNewKeyAndSaysItSwitched() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        bench.keys.failsDelete.withLock { $0 = true }
        model.otherAddress = "http://second.test:8210"
        model.otherKey = "key-2"
        await model.switchServer()

        #expect(model.host.connection == second)
        #expect(model.otherKey == "", "the key is held by the host, not the form")
        #expect(model.otherAddress == "")
        let notice = try #require(model.notice)
        #expect(notice.title == "Switched Servers, but Not Everything Was Removed")
        #expect(notice.message == "The previous server’s key is still in your Keychain. Remove it in Keychain Access.")
    }

    @Test func aCopyLeftBehindIsToldAgainstWhatTheStepDid() throws {
        let problem = MarfaHost.Problem.notRemoved(key: nil, copy: "NSCocoaErrorDomain 513")
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
        #expect(bench.keys.key(for: first) == nil)
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
        #expect(bench.keys.key(for: first) == nil, "the key goes, the copy stays")
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

        await model.answer(.discardCopy)
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
        #expect(bench.keys.key(for: first) == "key-1")
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
        model.otherKey = "key-2"
        await model.switchServer()
        #expect(model.departure?.kind == .switchServer)
        #expect(model.host.connection == first, "nothing moved yet")
        #expect(flushed.count == before + 1)

        await model.answer(.keepCopy)
        #expect(model.departure == nil)
        #expect(model.host.connection == second)
        #expect(bench.hasCopy(first))
        #expect(model.otherKey == "")
        #expect(model.otherAddress == "")
    }

    // MARK: Keys

    @Test func aRefusedKeyShowsAsSuchAndTakesANewOne() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { model.host.state == .keyRefused })
        #expect(model.status.title == "Key refused")
        #expect(model.status.isProblem)

        #expect(!model.canReplaceKey)
        model.newKey = "key-2"
        #expect(model.canReplaceKey)
        await model.replaceKey()
        #expect(model.notice == nil)
        #expect(model.newKey == "")
        #expect(bench.keys.key(for: first) == "key-2")
    }

    @Test func aNewKeyTheServerRefusesIsToldAndTheOldOneKept() async throws {
        let bench = try HostBench()
        let (model, _) = model(bench)
        await connect(model)
        let source = try #require(bench.servers.last)
        source.verdicts.withLock { $0["bad"] = .refused }
        model.newKey = "bad"
        await model.replaceKey()
        #expect(model.notice?.title == "Key refused")
        #expect(bench.keys.key(for: first) == "key-1")
        #expect(model.newKey == "bad", "what was typed is kept for another try")
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
        model.key = "key"
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
