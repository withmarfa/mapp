import Foundation
import Marfa
import struct MarfaCore.Draft
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
        try await host.connect(address: " HTTP://First.test:8210/ ", key: " key-1 ")
        #expect(host.connection == first)
        #expect(bench.savedAddress == "http://first.test:8210")
        #expect(bench.keys.key(for: first) == "key-1")
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        source.state.set(.online)
        #expect(await eventually { host.state == .online })
        source.state.set(.offline(reason: "network: refused"))
        #expect(await eventually { host.state == .offline(reason: "network: refused") })
        source.state.set(.stopped(code: "store", message: "The store is damaged."))
        #expect(await eventually { host.state == .unavailable(message: "The store is damaged.") })
    }

    /// A key sent over plain http to another machine can be read on the way, so the person is told, once in a run
    /// for each address, including one switched to. The package remembers each address for the whole test run, so
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

    @Test func aBadAddressOrAMissingKeyIsAPlainProblem() async throws {
        let bench = try HostBench()
        let host = bench.host()
        for address in ["not a server", "ftp://first.test", "http://user:pass@first.test", ""] {
            await expect(.notAServer) { () throws(MarfaHost.Problem) in try await host.connect(address: address, key: "k") }
        }
        await expect(.noKey) { () throws(MarfaHost.Problem) in try await host.connect(address: "http://first.test", key: "  ") }
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
        #expect(bench.keys.key(for: first) == nil)
    }

    /// The copy stays on disk and the person decides: keeping it loses nothing, and a discard needs the answer to
    /// the question about the changes in it.
    @Test func aCopyADifferentVersionMadeKeepsItsChangesUntilThePersonChooses() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
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
        #expect(bench.keys.key(for: first) == "k")

        try await host.disconnect(.keepCopy)
        #expect(host.connection == nil)
        #expect(bench.hasCopy(first), "keeping the copy leaves it for the version that can send what it holds")
        #expect(bench.keys.key(for: first) == nil)
    }

    @Test func aCopyAnotherCopyOfTheAppHoldsIsLeftForThePersonToQuitIt() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
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
        bench.keys.save("k", for: first)
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

        await expect(.notRemoved(key: nil, copy: Words.inUse)) { () throws(MarfaHost.Problem) in
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
        bench.keys.save("k", for: first)
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
        #expect(bench.keys.key(for: first) == "k")
        #expect(bench.defaults.dictionary(forKey: "MarfaDiscardedCopies") == nil)
    }

    /// Even when a count was shown, a copy the package can't read to count is kept, and not marked to go: the
    /// next connection opens or refuses it as it did.
    @Test
    func aCopyThePackageCannotCountIsKeptWhateverTheCountShown() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        bench.keys.save("k", for: first)
        let store = bench.location.store(for: first)
        try FileManager.default.createDirectory(at: bench.location.directory(for: first), withIntermediateDirectories: true)
        try Data(repeating: 0x5A, count: 8192).write(to: store)
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .otherVersion(unsent: 2), message: "The package’s words.") }
        let host = bench.host()
        await host.launch()

        await expect(.copyKept(.unreadable(folder: bench.location.directory(for: first).path), key: nil)) { () throws(MarfaHost.Problem) in
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
        bench.keys.save("k", for: first)
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

        await expect(.copyKept(.changed(now: 2), key: nil)) { () throws(MarfaHost.Problem) in
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

        await expect(.copyKept(.changed(now: 1), key: nil)) { () throws(MarfaHost.Problem) in
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

        await expect(.copyKept(.changed(now: 2), key: nil)) { () throws(MarfaHost.Problem) in
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

        await expect(.copyKept(.notMapps(folder: directory.path), key: nil)) { () throws(MarfaHost.Problem) in
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
        bench.keys.save("k", for: first)
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

        await expect(.notRemoved(key: nil, copy: Words.inUse)) { () throws(MarfaHost.Problem) in
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
        #expect(bench.keys.key(for: first) == nil)
    }

    @Test func aRefusedKeyIsReplacedInPlace() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "wrong")
        let source = try #require(bench.servers.last)
        source.state.set(.keyRefused)
        #expect(await eventually { host.state == .keyRefused })

        try await host.replaceKey("right")
        #expect(bench.keys.key(for: first) == "right")
        #expect(source.calls == ["refresh", "tryKey right"])
        #expect(bench.servers.opened.count == 1)
        source.state.set(.online)
        #expect(await eventually { host.state == .online })

        // Connecting to the same address again only changes the key.
        try await host.connect(address: "http://first.test:8210/", key: "again")
        #expect(source.calls.last == "tryKey again")
        #expect(bench.servers.opened.count == 1)
    }

    /// The new key was never answered for, so the copy opens again with the old one, and the person is told.
    @Test func aCopyThatCannotTakeTheKeyOpensAgainWithTheOldOne() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "old")
        let source = try #require(bench.servers.last)
        source.refusesKeys.withLock { $0 = true }
        await expect(.unavailable(message: "The copy closed.")) { () throws(MarfaHost.Problem) in try await host.replaceKey("new") }
        #expect(source.calls == ["refresh", "tryKey new", "close"])
        #expect(bench.servers.opened.count == 2)
        #expect(host.source === bench.servers.last)
        #expect(bench.keys.key(for: first) == "old")
    }

    @Test func aKeyTheServerRefusesIsNotKept() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.verdicts.withLock { $0["typo"] = .refused }
        await expect(.keyRefused) { () throws(MarfaHost.Problem) in try await host.replaceKey("typo") }
        #expect(bench.keys.key(for: first) == "good")
        #expect(source.calls == ["refresh", "tryKey typo", "tryKey good"])
    }

    @Test func aKeyTheServerCannotBeAskedAboutIsKeptOnlyInPlaceOfARefusedOne() async throws {
        let bench = try HostBench()
        let host = bench.host()
        try await host.connect(address: "http://first.test:8210", key: "good")
        let source = try #require(bench.servers.last)
        source.state.set(.online)
        source.verdicts.withLock { $0["later"] = .unanswered("network: down") }
        await expect(.serverUnreachable(reason: "network: down")) { () throws(MarfaHost.Problem) in
            try await host.replaceKey("later")
        }
        #expect(bench.keys.key(for: first) == "good")
        #expect(source.calls.last == "tryKey good")

        source.state.set(.keyRefused)
        try await host.replaceKey("later")
        #expect(bench.keys.key(for: first) == "later")
        #expect(source.calls.last == "tryKey later")
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
        #expect(bench.keys.key(for: first) == nil)
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
        #expect(bench.keys.key(for: first) == nil)
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
        #expect(bench.keys.key(for: first) == "one")
        #expect(bench.keys.key(for: second) == nil)

        bench.servers.failure.withLock { $0 = nil }
        try await host.changeAddress(to: "http://second.test:8210", key: "two", choice: .keepCopy)
        #expect(host.connection == second)
        #expect(host.source === bench.servers.last)
        #expect(bench.savedAddress == "http://second.test:8210")
        #expect(bench.keys.key(for: first) == nil)
        #expect(bench.keys.key(for: second) == "two")
        #expect(old.calls.last == "close")
        #expect(bench.hasCopy(first))
    }

    @Test func aDebugTestServerIsOpenedByTheNextLaunchWithItsKeyHeldInMemory() async throws {
        let bench = try HostBench()
        bench.keys.save("test-key", for: first)
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
        bench.keys.save("k", for: first)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(host.connection == first)
        // The fake never answers, so a launch that waited on the server would not have returned.
        #expect(host.state == .connecting)
        #expect(source.calls == ["refresh"])
        await host.launch()
        #expect(bench.servers.opened.count == 1)
    }

    @Test func aLaunchWithoutAKeyAsksForOne() async throws {
        let bench = try HostBench()
        bench.defaults.set("http://first.test:8210", forKey: "MarfaAddress")
        let host = bench.host()
        await host.launch()
        #expect(host.state == .keyRefused)
        #expect(host.connection == first)
        #expect(host.source == nil)
        try await host.replaceKey("k")
        #expect(host.source === bench.servers.last)
        #expect(host.state == .connecting)
    }

    @Test func aLaunchWithNothingSavedDoesNothing() async throws {
        let bench = try HostBench()
        let host = bench.host()
        await host.launch()
        #expect(host.state == .disconnected)
        #expect(bench.servers.opened.isEmpty)
        await expect(.notConnected) { () throws(MarfaHost.Problem) in try await host.replaceKey("k") }
    }
}
