import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

@Suite(.hangLimit)
@MainActor struct MarfaHostTests {
    private let first = try! MarfaConnection(address: "http://first.test:8210")
    private let second = try! MarfaConnection(address: "http://second.test:8210")

    private func expect(_ problem: MarfaHost.Problem, _ work: () async throws(MarfaHost.Problem) -> Void) async {
        do {
            try await work()
            Issue.record("expected \(problem)")
        } catch {
            #expect(error == problem)
        }
    }

    @Test func connectingKeepsTheAddressAndKeyAndPaintsBeforeTheServer() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: " HTTP://First.test:8210/ ", key: "key-1")
        #expect(host.connection == first)
        #expect(bench.savedAddress == "http://first.test:8210")
        #expect(try bench.signIns.key(for: first.address) == "key-1")
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.state == .connecting)
        #expect(source.calls == [])
        source.state.set(.online)
        #expect(await eventually { host.state == .online })
        source.state.set(.offline(reason: "network: refused"))
        #expect(await eventually { host.state == .offline(reason: "network: refused") })
        source.state.set(.unavailable(message: "The store is damaged."))
        #expect(await eventually { host.state == .unavailable(message: "The store is damaged.") })
    }

    /// The library is the one subscriber to the copy's connection states, so each change reaches it once; the host
    /// reads the state from the library, and reads the server's name again once for each return to the server.
    @Test func aConnectionChangeIsDeliveredOnceAndTheHostReadsItFromTheLibrary() async throws {
        let bench = try HostBench()
        bench.servers.names.withLock { $0[first] = "Home Marfa" }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        let library = try #require(host.library)
        func reads() -> Int { bench.servers.reads.withLock { $0 } }
        #expect(source.stateSubscriptions.withLock { $0 } == 1)
        #expect(await eventually { reads() == 1 }, "attaching the copy reads the name")

        source.state.set(.online)
        #expect(await eventually { library.connection == .online && host.state == .online })
        #expect(await eventually { reads() == 2 })
        source.state.set(.offline(reason: nil))
        #expect(await eventually { host.state == .offline(reason: nil) })
        source.state.set(.online)
        #expect(await eventually { reads() == 3 })
        // Gives a second delivery of the same change time to arrive and read the name again.
        try await Task.sleep(for: .milliseconds(200))
        #expect(reads() == 3)
        #expect(source.stateSubscriptions.withLock { $0 } == 1)
    }

    /// A key sent over plain http to another machine can be read on the way, so the person is told, once in a run
    /// for each address, including one switched to. The host remembers each address for the whole process, so
    /// these are made up for this test.
    @Test func aPlainHTTPAddressOnAnotherMachineIsToldOnce() async throws {
        let address = "http://plain-\(UUID().uuidString.lowercased()).test:8210"
        let switched = "http://plain-\(UUID().uuidString.lowercased()).test"
        let host = try HostBench().host()
        try await host.connect(address: address, key: "k")
        #expect(host.notices.waiting.map { [$0.title, $0.message] } == [[Words.plainHTTPTitle, Words.plainHTTP(origin: address)]])
        host.notices.answerAll()

        try await host.changeAddress(to: switched, key: "k")
        #expect(host.notices.waiting.map(\.message) == [Words.plainHTTP(origin: switched)])

        let again = try HostBench().host()
        try await again.connect(address: address, key: "k")
        #expect(again.notices.waiting.isEmpty)
    }

    @Test func aNoticeStillWaitingIsNotReplacedByTheNext() async throws {
        let first = "http://plain-\(UUID().uuidString.lowercased()).test:8210"
        let second = "http://plain-\(UUID().uuidString.lowercased()).test"
        let host = try HostBench().host()
        try await host.connect(address: first, key: "k")
        try await host.changeAddress(to: second, key: "k")
        #expect(host.notices.waiting.map(\.message) == [Words.plainHTTP(origin: first), Words.plainHTTP(origin: second)])
    }

    @Test func thisMachineAndHTTPSAreNotTold() async throws {
        for address in ["http://localhost:8210", "http://127.0.0.1:8210", "http://[::1]:8210", "https://\(UUID().uuidString.lowercased()).test"] {
            let host = try HostBench().host()
            try await host.connect(address: address, key: "k")
            #expect(host.notices.waiting.isEmpty, "\(address)")
        }
    }

    @Test func aBadAddressIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        for address in ["not a server", "ftp://first.test", "http://user:pass@first.test", ""] {
            await expect(.notAServer) { () throws(MarfaHost.Problem) in try await host.connect(address: address, key: "k") }
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func aCopyThatCannotBeOpenedIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The store is damaged.") }
        await expect(.unavailable(message: "The store is damaged.")) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    /// The copy stays on disk and the person decides: keeping it loses nothing, and a discard needs the answer to
    /// the question about the changes in it.
    @Test func aCopyADifferentVersionMadeKeepsItsChangesUntilThePersonChooses() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 3), message: "The package’s words.") }
        let host = bench.host()

        await host.launch()
        #expect(host.state == .otherVersion(unsent: 3))
        #expect(host.source == nil)
        #expect(host.waitingChanges == 3)
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: host.state, isLaunching: false, isBusy: false) == .failed)

        await expect(.changesWaiting(nil)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == first)
        #expect(bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == "k")

        try await host.disconnect(.keepCopy)
        #expect(host.connection == nil)
        #expect(bench.hasCopy(first), "keeping the copy leaves it for the version that can send what it holds")
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    @Test func aCopyAnotherCopyOfTheAppHoldsIsLeftForThePersonToQuitIt() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .inUse, message: "The package’s words.") }
        let host = bench.host()

        await host.launch()
        #expect(host.state == .inUse)
        #expect(host.source == nil)
        #expect(bench.hasCopy(first))
        #expect(Libraries.mode(hasSource: false, isConfigured: true, state: host.state, isLaunching: false, isBusy: false) == .failed)
    }

    /// Discarding the copy takes it from under nobody: while another process writes it, it stays, marked to go.
    @Test
    func discardingACopyAnotherProcessWritesLeavesIt() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        await (try await WorkingCopy.open(store: store)).close()
        let holder: OtherProcessLock
        do {
            holder = try await OtherProcessLock(store)
        } catch OtherProcessLock.Failure.notStarted(let reason) {
            Issue.record("The test sandbox forbids starting /usr/bin/sqlite3, so another process can't hold the lock here: \(reason)")
            return
        }
        defer { holder.release() }
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 1), message: "The package’s words.") }
        let host = bench.host()
        await host.launch()
        try #require(host.state == .otherVersion(unsent: 1))

        await expect(.notRemoved(signIn: nil, copy: Words.inUse)) { () throws(MarfaHost.Problem) in
            try await host.disconnect(.discardCopy(nil))
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
    }

    /// The package removes a copy only against a count of its changes, so a copy that can't be opened, and whose
    /// changes nobody could count, is never discarded: the person is told where it is, and nothing is left.
    @Test
    func aCopyThatCannotBeOpenedIsNotDiscardedAndThePersonIsToldWhereItIs() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 8192).write(to: store)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The package’s words.") }
        let host = bench.host()
        await host.launch()

        await expect(.cannotDiscard(folder: bench.location.directory(for: first).path)) { () throws(MarfaHost.Problem) in
            try await host.disconnect(.discardCopy(nil))
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(host.connection == first, "nothing was left")
        #expect(try bench.signIns.key(for: first.address) == "k")
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies") == nil)
    }

    /// Even when a count was shown, a copy the package can't read to count is kept, and not marked to go: the
    /// next connection opens or refuses it as it did.
    @Test
    func aCopyThePackageCannotCountIsKeptWhateverTheCountShown() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 8192).write(to: store)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 2), message: "The package’s words.") }
        let host = bench.host()
        await host.launch()

        await expect(.copyKept(.unreadable(folder: bench.location.directory(for: first).path), signIn: nil)) { () throws(MarfaHost.Problem) in
            try await host.disconnect(.discardCopy(nil))
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true)
    }

    /// The person agreed to lose the number of changes they were shown. A copy holding another number is kept,
    /// and they are told the number it holds.
    @Test
    func aCopyHoldingOtherChangesThanThePersonWasShownIsKept() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: store)
        for index in 0..<2 {
            _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": .string("unsent \(index)")]))
        }
        await copy.close()
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 1), message: "The package’s words.") }
        let host = bench.host()
        await host.launch()
        try #require(host.state == .otherVersion(unsent: 1))

        await expect(.copyKept(.changed(now: 2), signIn: nil)) { () throws(MarfaHost.Problem) in
            try await host.disconnect(.discardCopy(nil))
        }
        let kept = try await WorkingCopy.open(store: store)
        #expect(try await kept.queue.all().count == 2, "no change was lost")
        await kept.close()
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true, "it is not marked to go")
    }

    /// A copy marked to go that has since gained changes is not removed when its address is opened again either.
    @Test
    func aCopyMarkedToGoThatHoldsOtherChangesIsKeptWhenItsAddressIsOpened() async throws {
        let bench = try HostBench()
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: store)
        _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": "unsent"]))
        await copy.close()
        bench.defaults.set(["http://first.test:8210": 0], forKey: "MarfaDiscardedCopies")
        let host = bench.host()

        await expect(.copyKept(.changed(now: 1), signIn: nil)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(host.connection == nil)
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true, "the next connection opens it")
    }

    /// A discard interrupted after the store went leaves a marked folder with no store. It holds nothing, so
    /// whatever count was agreed, it is removed and the address opens.
    @Test
    func aMarkedCopyWhoseStoreIsAlreadyGoneIsRemovedWhateverWasAgreed() async throws {
        let bench = try HostBench()
        let directory = bench.location.directory(for: first)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("left behind".utf8).write(to: directory.appending(path: "leftover"))
        bench.defaults.set(["http://first.test:8210": 3], forKey: "MarfaDiscardedCopies")
        let host = bench.host()

        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(!FileManager.default.fileExists(atPath: bench.location.store(for: first).path))
        #expect(host.connection == first)
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true)
    }

    /// A shown write may be sent while the sheet is open, so the copy holds fewer than the person agreed to
    /// lose. Nothing beyond what they agreed is lost, so the discard goes through.
    @Test
    func aCopyHoldingFewerChangesThanThePersonAgreedToLoseIsRemoved() async throws {
        let bench = try HostBench()
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: store)
        _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": "unsent"]))
        await copy.close()
        bench.defaults.set(["http://first.test:8210": 2], forKey: "MarfaDiscardedCopies")
        let host = bench.host()

        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(!FileManager.default.fileExists(atPath: store.path), "the old copy is gone before the address opens")
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true)
    }

    /// The retry is made once, with the count the copy held: a copy that gains a change between the two asks is
    /// kept, not asked again without end.
    @Test
    func aRetryThatFindsMoreChangesKeepsTheCopy() async throws {
        let bench = try HostBench()
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.defaults.set(["http://first.test:8210": 3], forKey: "MarfaDiscardedCopies")
        let asked = Mutex<[UInt64]>([])
        let host = bench.host(remover: { _, agreed in
            asked.withLock { $0.append(agreed) }
            let held: UInt64 = agreed == 3 ? 1 : 2
            throw MarfaError.unsentDiffers(path: "p", unsent: held, agreed: agreed, message: "")
        })

        await expect(.copyKept(.changed(now: 2), signIn: nil)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(asked.withLock { $0 } == [3, 1])
    }

    /// The package refuses a folder's store, which can't be made here, so its answer is given to the host. The
    /// copy stays, its mark is dropped, and the person is told it isn't MAPP's.
    @Test
    func aMarkedStoreThatIsAFoldersIsLeftAndToldSo() async throws {
        let bench = try HostBench()
        let directory = bench.location.directory(for: first)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        bench.defaults.set(["http://first.test:8210": 0], forKey: "MarfaDiscardedCopies")
        let host = bench.host(remover: { _, _ in throw MarfaError.invalid(message: "is a folder’s store") })

        await expect(.copyKept(.notMapps(folder: directory.path), signIn: nil)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(FileManager.default.fileExists(atPath: directory.path))
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies")?.isEmpty ?? true)
    }

    /// An earlier version of the app may still be writing a copy this version refuses, so it stays too.
    @Test
    func discardingACopyADifferentVersionWritesLeavesIt() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        let copy = try await WorkingCopy.open(store: store)
        _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": "unsent"]))
        await copy.close()
        try MarfaSourceOfflineTests.makeItAnEarlierVersion(store)
        let holder: OtherProcessLock
        do {
            holder = try await OtherProcessLock(store)
        } catch OtherProcessLock.Failure.notStarted(let reason) {
            Issue.record("The test sandbox forbids starting /usr/bin/sqlite3, so another process can't hold the lock here: \(reason)")
            return
        }
        defer { holder.release() }
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 1), message: "The package’s words.") }
        let host = bench.host()
        await host.launch()

        await expect(.notRemoved(signIn: nil, copy: Words.inUse)) { () throws(MarfaHost.Problem) in
            try await host.disconnect(.discardCopy(nil))
        }
        #expect(FileManager.default.fileExists(atPath: store.path))
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies") as? [String: Int] == ["http://first.test:8210": 1])

        // Once that process lets go, the copy marked to go is removed before the address opens again.
        holder.release()
        bench.servers.failure.withLock { $0 = nil }
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(!FileManager.default.fileExists(atPath: store.path))
    }

    @Test func connectingToAServerWhoseCopyADifferentVersionMadeIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: nil), message: "The package’s words.") }
        await expect(.otherVersion(unsent: nil)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", key: "k")
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    @Test func aSignedOutLibraryIsSignedInAgainAndItsCopyOpensAgain() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })

        try await host.signInAgain(via: host.scripted("new"))
        #expect(try bench.signIns.key(for: first.address) == "new")
        #expect(source.calls == ["close"], "the copy is closed, never discarded, so its queue stays")
        #expect(bench.servers.opened.count == 2)
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)

        // Connecting to the same address again only signs in again.
        try await host.connect(address: "http://first.test:8210/", key: "again")
        #expect(try bench.signIns.key(for: first.address) == "again")
        #expect(bench.servers.opened.count == 3)
        #expect(bench.signIns.calls.filter { $0.hasPrefix("browser") }.count == 3)
    }

    @Test func aSignInThePersonCancelsChangesNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        bench.signIns.script(browser: [.failure(CancellationError())])
        await expect(.signIn(.canceled)) { () throws(MarfaHost.Problem) in try await host.signInAgain(via: .browser) }
        bench.signIns.script(browser: [.failure(SignInError.canceled)])
        await expect(.signIn(.canceled)) { () throws(MarfaHost.Problem) in try await host.signInAgain(via: .browser) }
        #expect(try bench.signIns.key(for: first.address) == "old")
        #expect(source.calls.isEmpty, "the open copy was not touched")
        #expect(bench.servers.opened.count == 1)
        #expect(host.source === source)
    }

    @Test(arguments: [
        (SignInError.denied, SignInOutcome.denied),
        (.expired, .expired),
        (.refused(code: "invalid_grant", message: "No."), .refused(SignInError.refused(code: "invalid_grant", message: "No.").description)),
        (.unavailable(message: "offline"), .unreachable("offline")),
        (.unreadable(message: "locked"), .refused("locked")),
        (.unavailable(message: "another process is using the sign-in"), .inUse),
    ])
    func aSignInThatDoesNotFinishLeavesTheOldOneAndTheCopyAlone(_ error: SignInError, _ outcome: SignInOutcome) async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        bench.signIns.script(browser: [.failure(error)])
        await expect(.signIn(outcome)) { () throws(MarfaHost.Problem) in try await host.signInAgain(via: .browser) }
        #expect(try bench.signIns.key(for: first.address) == "old")
        #expect(source.calls.isEmpty)
        #expect(host.source === source)
    }

    /// Edits typed in a page are in the copy before a sign-in that may take minutes starts, as when switching.
    @Test func signingInAgainHandsOverEditsBeforeTheSignInStarts() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let order = Mutex<[String]>([])
        host.handOverEdits = { order.withLock { $0.append("edits") }; return true }
        bench.signIns.onBrowser.withLock { $0 = { order.withLock { $0.append("browser") } } }
        try await host.signInAgain(via: host.scripted("new"))
        #expect(order.withLock { $0 }.first == "edits")
    }

    @Test func anEditorThatCannotHandOverStopsASignInAgainBeforeItStarts() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        host.handOverEdits = { false }
        await expect(.unavailable(message: "Finish editing the current note before changing libraries.")) { () throws(MarfaHost.Problem) in
            try await host.signInAgain(via: host.scripted("new"))
        }
        #expect(bench.signIns.calls == ["browser http://first.test:8210"], "only the first sign-in was made")
        #expect(try bench.signIns.key(for: first.address) == "old")
    }

    /// Writes made while the person approves a switch on another server are counted again once the approval is
    /// in, and they are asked about with the sign-in kept, so the approval is not wasted.
    @Test func writesMadeDuringASwitchSignInAreAskedAboutWithoutLosingTheApproval() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.signIns.onBrowser.withLock { $0 = { old.report.set(SyncReport(waiting: 1, queueRead: true)) } }

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(try bench.signIns.key(for: second.address) == "two", "the new approval is kept for the answer")
        #expect(!bench.signIns.calls.contains("signOut http://second.test:8210"))

        bench.signIns.onBrowser.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", key: "other", choice: .discardCopy(.fake(1)))
        #expect(host.connection == second)
        #expect(try bench.signIns.key(for: second.address) == "two", "the answer used the approval already made")
        #expect(bench.signIns.calls.filter { $0 == "browser http://second.test:8210" }.count == 1)
    }

    @Test func aQuestionTheyDoNotAnswerEndsTheApprovalKeptForIt() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.signIns.onBrowser.withLock { $0 = { old.report.set(SyncReport(waiting: 1, queueRead: true)) } }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        await host.abandonPendingSignIn()
        #expect(try bench.signIns.key(for: second.address) == nil)
        #expect(host.connection == first)
    }

    /// The kept approval is out of the host's hands the moment an answer arrives, so a step that stops before using it
    /// ends it.
    @Test func anAnswerThatStopsBeforeUsingTheKeptApprovalEndsIt() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.signIns.onBrowser.withLock { $0 = { old.report.set(SyncReport(waiting: 1, queueRead: true)) } }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        #expect(try bench.signIns.key(for: second.address) == "two")

        host.handOverEdits = { false }
        await expect(.unavailable(message: "Finish editing the current note before changing libraries.")) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "other", choice: .discardCopy(.fake(1)))
        }
        #expect(try bench.signIns.key(for: second.address) == nil, "nothing is left live for a question no one holds")
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil)
        #expect(host.connection == first)
    }

    @Test func aKeptApprovalIsRecordedForALaunchUntilItIsUsedOrDropped() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.signIns.onBrowser.withLock { $0 = { old.report.set(SyncReport(waiting: 1, queueRead: true)) } }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == "http://second.test:8210")

        bench.signIns.onBrowser.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", key: "other", choice: .discardCopy(.fake(1)))
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil, "the answer used it")
        #expect(host.connection == second)
    }

    @Test func aDroppedQuestionClearsItsRecord() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        bench.signIns.onBrowser.withLock { $0 = { old.report.set(SyncReport(waiting: 1, queueRead: true)) } }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") != nil)
        await host.abandonPendingSignIn()
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil)
    }

    /// Quitting with the question open leaves its approval in the Keychain; the next launch ends it.
    @Test func aLaunchEndsTheApprovalAQuitLeftForAQuestion() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.defaults.set("http://second.test:8210", forKey: "MarfaPendingSignIn")
        bench.signIns.save("one", for: first.address)
        bench.signIns.save("two", for: second.address)
        let host = bench.host()
        await host.launch()
        #expect(try bench.signIns.key(for: second.address) == nil)
        #expect(try bench.signIns.key(for: first.address) == "one", "the sign-in the app is connected with stays")
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil)
        #expect(host.connection == first)
    }

    @Test func aLaunchNeverEndsTheSignInOfTheAddressItConnectsTo() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.defaults.set("http://first.test:8210", forKey: "MarfaPendingSignIn")
        bench.signIns.save("one", for: first.address)
        let host = bench.host()
        await host.launch()
        #expect(try bench.signIns.key(for: first.address) == "one")
        #expect(bench.defaults.string(forKey: "MarfaPendingSignIn") == nil)
        #expect(host.source === bench.servers.last)
    }

    /// Only the Keychain's own errors are told as the Keychain's; anything else that ends a sign-in is a sign-in
    /// that could not be finished.
    @Test func anErrorThatIsNotTheKeychainsIsNotToldAsOne() {
        struct Other: Error, LocalizedError { var errorDescription: String? { "Odd." } }
        #expect(SignInOutcome(Other()) == .unreachable("Odd."))
        #expect(SignInOutcome(MemorySignIns.Unreadable()) == .keychain(String(describing: MemorySignIns.Unreadable())))
    }

    @Test func aKeychainThatWillNotKeepTheSignInIsToldAsThat() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.signIns.script(browser: [.failure(MemorySignIns.Unreadable())])
        await expect(.signIn(.keychain(String(describing: MemorySignIns.Unreadable())))) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", via: .browser)
        }
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    @Test func aFirstSignInThatIsCanceledLeavesNothingBehind() async throws {
        let bench = try HostBench()
        let host = bench.host()
        bench.signIns.script(browser: [.failure(SignInError.canceled)])
        await expect(.signIn(.canceled)) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://first.test:8210", via: .browser)
        }
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(bench.savedAddress == nil)
        #expect(!bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    @Test func aCodeIsShownWhileItWaitsAndTheSignInIsKeptOnceApproved() async throws {
        let bench = try HostBench()
        let host = bench.host()
        let shown = Mutex<[String]>([])
        let signIns = bench.signIns
        let address = first.address
        signIns.script(code: [.success(CodeSignIn(
            code: "ABCD-1234", address: URL(string: "http://first.test:8210/device")!, completeAddress: nil,
            expiresAt: .distantFuture, finish: { signIns.save("approved", for: address) }))])
        try await host.connect(address: "http://first.test:8210", via: .code(shown: { code in shown.withLock { $0.append(code.code) } }))
        #expect(shown.withLock { $0 } == ["ABCD-1234"])
        #expect(try signIns.key(for: first.address) == "approved")
        #expect(host.source === bench.servers.last)
        #expect(signIns.calls == ["code http://first.test:8210"])
    }

    @Test func aCodeThatExpiresOrIsDeniedKeepsNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        for (error, outcome) in [(SignInError.expired, SignInOutcome.expired), (.denied, .denied)] {
            bench.signIns.script(code: [.success(CodeSignIn(
                code: "X", address: URL(string: "http://first.test:8210/device")!, completeAddress: nil,
                expiresAt: .distantFuture, finish: { throw error }))])
            await expect(.signIn(outcome)) { () throws(MarfaHost.Problem) in
                try await host.connect(address: "http://first.test:8210", via: .code(shown: { _ in }))
            }
        }
        #expect(host.connection == nil)
        #expect(try bench.signIns.key(for: first.address) == nil)
        #expect(bench.servers.opened.isEmpty)
    }

    /// The new sign-in is kept, since the server gave it; only the copy could not be opened, and nothing in it is lost.
    @Test func aCopyThatCannotOpenAfterSigningInAgainIsToldAndKeepsTheSignIn() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The copy closed.") }
        await expect(.unavailable(message: "The copy closed.")) { () throws(MarfaHost.Problem) in
            try await host.signInAgain(via: host.scripted("new"))
        }
        #expect(try bench.signIns.key(for: first.address) == "new")
        #expect(host.connection == first)
        #expect(bench.hasCopy(first))
    }

    @Test func aSignInThatEndsWhileTheAppRunsIsSignedInAgainWithoutDiscardingAnything() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })
        #expect(host.waitingChanges == 2)
        try await host.signInAgain(via: host.scripted("new"))
        #expect(bench.hasCopy(first))
        #expect(!bench.signIns.calls.contains { $0.hasPrefix("signOut") })
    }

    @Test func leavingWithWritesWaitingNeedsAChoice() async throws {
        let bench = try HostBench()
        bench.servers.storedWrites.withLock { $0 = 2 }
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        source.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })

        await expect(.changesWaiting(.fake(2))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.connection == first)
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        try await host.disconnect(.keepCopy)
        #expect(host.state == .disconnected)
        #expect(host.connection == nil)
        #expect(host.source == nil)
        #expect(host.report == SyncReport())
        #expect(source.calls.last == "close")
        #expect(bench.savedAddress == nil)
        #expect(try bench.signIns.key(for: first.address) == nil)
        #expect(bench.hasCopy(first))

        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        try await host.disconnect(.discardCopy(.fake(2)))
        #expect(!bench.hasCopy(first))
    }

    /// Text a page hands over as the copy is left reaches the copy before it reads its queue and closes, so it is
    /// asked about rather than lost.
    @Test func editsHandedOverAsACopyIsLeftAreInItWhenItCloses() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(bench.servers.last)
        host.handOverEdits = { source.report.set(SyncReport(waiting: 1, queueRead: true)); return true }

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "k2")
        }
        #expect(host.connection == first)
        #expect(!source.calls.contains("close"))
    }

    @Test func aRejectedEditorFlushKeepsTheCurrentLibraryOpen() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let source = try #require(host.source as? FakeMarfaSource)
        host.handOverEdits = { false }
        do { try await host.disconnect(.keepCopy); Issue.record("Leaving was approved after the editor rejected saving") }
        catch { if case .unavailable = error {} else { Issue.record("Unexpected failure: \(error)") } }
        #expect(host.source === source)
        #expect(!source.calls.contains("close"))
        #expect(!host.isBusy)
    }

    @Test func refusedWritesCountAsWaiting() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        let refused = SyncProblemEntry(
            id: .write("w"), itemID: ItemID("i"), kind: .refused, change: .create, reason: SyncProblem(code: "x"),
            content: SyncContent(title: "Kept"), actions: [.discard])
        try #require(bench.servers.last).report.set(SyncReport(problems: [refused], queueRead: true))
        #expect(await eventually { host.report.problems == [refused] })
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func leavingWithNothingWaitingRemovesTheCopy() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        #expect(host.waitingChanges == 0)
        try await host.disconnect()
        #expect(!bench.hasCopy(first))
        #expect(try bench.signIns.key(for: first.address) == nil)
    }

    /// Until the copy's queue is read, nothing is known of what waits in it.
    @Test func aCopyNotYetReadNeedsAChoice() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "k")
        try #require(bench.servers.last).report.set(SyncReport())
        #expect(await eventually { host.waitingChanges == nil })
        await expect(.changesWaiting(nil)) { () throws(MarfaHost.Problem) in try await host.disconnect() }
    }

    @Test func anotherAddressWarnsAndKeepsTheFirstUntilTheSecondOpens() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "one")
        let old = try #require(bench.servers.last)
        old.report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { host.waitingChanges == 1 })

        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two")
        }
        await expect(.changesWaiting(.fake(1))) { () throws(MarfaHost.Problem) in
            try await host.connect(address: "http://second.test:8210", key: "two")
        }
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "No room.") }
        await expect(.unavailable(message: "No room.")) { () throws(MarfaHost.Problem) in
            try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .keepCopy)
        }
        #expect(host.connection == first)
        #expect(host.source === old)
        #expect(try bench.signIns.key(for: first.address) == "one")
        #expect(try bench.signIns.key(for: second.address) == nil)

        bench.servers.failure.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .keepCopy)
        #expect(host.connection == second)
        #expect(host.source === bench.servers.last)
        #expect(bench.savedAddress == "http://second.test:8210")
        #expect(try bench.signIns.key(for: first.address) == nil)
        #expect(try bench.signIns.key(for: second.address) == "two")
        #expect(old.calls.last == "close")
        #expect(bench.hasCopy(first))
    }

    @Test func aDebugTestServerIsOpenedByTheNextLaunchWithItsKeyHeldInMemory() async throws {
        let bench = try HostBench()
        bench.signIns.save("test-key", for: first.address)
        let host = bench.host()
        host.presetTestServer(first)
        #expect(host.configuredConnection == first)

        await host.launch()
        #expect(host.connection == first)
        #expect(host.source === bench.servers.last)
    }

    @Test func aLaunchReconnectsFromTheCopyWithoutWaitingOnTheServer() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.signIns.save("k", for: first.address)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.connection == first)
        // The fake never answers, so a launch that waited on the server would not have returned.
        #expect(host.state == .connecting)
        #expect(source.calls == [])
        await host.launch()
        #expect(bench.servers.opened.count == 1)
    }

    @Test func aLaunchWithoutASignInAsksForOne() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let host = bench.host()
        await host.launch()
        #expect(host.state == .keyRefused)
        #expect(host.connection == first)
        #expect(host.source == nil)
        try await host.signInAgain(via: host.scripted("k"))
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)
    }

    @Test func aLaunchWithNothingSavedDoesNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        await host.launch()
        #expect(host.state == .disconnected)
        #expect(bench.servers.opened.isEmpty)
        await expect(.notConnected) { () throws(MarfaHost.Problem) in try await host.signInAgain(via: .browser) }
    }
}
