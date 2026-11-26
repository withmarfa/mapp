import Foundation
import Marfa
import MarfaTesting
import Synchronization
import Testing
@testable import MarfaMac

/// One Marfa is one copy: known by the instance it says it is, whatever its address is typed as or moves to, with
/// each sign-in kept for its own origin and every change a copy holds kept until it is sent or the person discards it.
@Suite(.hangLimit)
@MainActor struct MarfaHostCopiesTests {
    private let bare = try! MarfaConnection(address: "https://marfa.test")
    private let withPort = try! MarfaConnection(address: "https://marfa.test:443")
    private let moved = try! MarfaConnection(address: "https://moved.test")

    /// Makes a copy with `count` unsent changes in `folder`, as the person's writes leave one.
    private func makeCopy(_ bench: HostBench, in folder: URL, unsent count: Int) async throws -> URL {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = folder.appending(path: "copy.sqlite")
        let copy = try await WorkingCopy.open(store: store)
        for index in 0..<count {
            _ = try await copy.items.create(Draft(type: "core.note", properties: ["body": .string("unsent \(index)")]))
        }
        await copy.close()
        return store
    }

    private func unsent(_ store: URL) async throws -> Int {
        try await WorkingCopy.unsentWrites(in: store).writes.count
    }

    @Test func eitherSpellingOfTheDefaultPortFindsTheCopyTheOtherMade() async throws {
        let bench = HostBench()
        #expect(bench.location.directory(for: bare) != bench.location.directory(for: moved))
        let made = bench.location.directory(for: withPort)
        _ = try await makeCopy(bench, in: made, unsent: 1)
        #expect(bench.location.directory(for: bare) == made)
        #expect(bench.location.directory(for: withPort) == made)
        let other = try MarfaConnection(address: "https://marfa.test:8443")
        #expect(bench.location.directory(for: other) != made, "another port is another origin until the app knows otherwise")
    }

    @Test func aLaunchOpensTheKnownCopyOfAnotherSpellingAtOnceWithoutAskingTheServer() async throws {
        let bench = HostBench()
        let store = try await makeCopy(bench, in: bench.location.directory(for: withPort), unsent: 2)
        bench.defaults.set(bare.address.absoluteString, forKey: "MarfaAddress")
        bench.signIns.save("k", for: bare.address)
        let host = bench.host()
        await host.launch()
        let source = try #require(bench.servers.last)
        #expect(host.source === source)
        #expect(source.store.withLock { $0 } == store)
        #expect(try await unsent(store) == 2)
        #expect(host.state == .connecting, "the fake never answers, so the launch did not wait on it")
    }

    @Test func theSameMarfaAtAnotherAddressKeepsItsCopyAndItsChangesWithItsOwnSignIn() async throws {
        let bench = HostBench()
        bench.servers.instances.withLock { $0 = [bare: "instance-x", moved: "instance-x"] }
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "old-origin")
        let first = try #require(bench.servers.last)
        let folder = bench.location.directory(for: bare)
        let key = host.libraryKey(for: bare)
        #expect(key == "marfa:instance-x")
        first.report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { host.waitingChanges == 1 })

        // No question about the waiting change: it stays in the copy the new address opens.
        try await host.changeAddress(to: moved.address.absoluteString, key: "new-origin")
        #expect(host.connection == moved)
        #expect(bench.location.directory(for: moved) == folder)
        #expect(first.calls.last == "close")
        let second = try #require(bench.servers.last)
        #expect(second !== first)
        #expect(host.source === second)
        #expect(host.libraryKey(for: moved) == key)
        // Each origin's sign-in is its own: the new address was signed in to, the old one's was never sent to it, and
        // the old one's stays for a return.
        #expect(try bench.signIns.key(for: moved.address) == "new-origin")
        #expect(try bench.signIns.key(for: bare.address) == "old-origin")
        #expect(!bench.signIns.calls.contains("signOut https://marfa.test"))
        #expect(bench.signIns.calls.contains("browser https://moved.test"))
        #expect(bench.savedAddress == "https://moved.test")
    }

    @Test func anAddressThatDoesNotSayWhichMarfaItIsCannotTakeAnotherAddresssCopy() async throws {
        let bench = HostBench()
        bench.servers.instances.withLock { $0 = [bare: "instance-x"] }
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "old-origin")
        let first = try #require(bench.servers.last)
        first.report.set(SyncReport(waiting: 1, queueRead: true))
        #expect(await eventually { host.waitingChanges == 1 })
        do {
            try await host.changeAddress(to: moved.address.absoluteString, key: "new-origin")
            Issue.record("an address not known as the same Marfa is another library")
        } catch {
            guard case .changesWaiting = error else { throw error }
        }
        #expect(host.source === first)
        #expect(bench.location.directory(for: moved) != bench.location.directory(for: bare))
    }

    @Test func anotherMarfaAtAnAddressUsedBeforeGetsItsOwnCopyAndTheFirstKeepsItsChanges() async throws {
        let bench = HostBench()
        let oldFolder = bench.location.directory(for: bare)
        let oldStore = try await makeCopy(bench, in: oldFolder, unsent: 2)
        try bench.location.copies.change { $0.instances[oldFolder.lastPathComponent] = "instance-x" }
        bench.servers.instances.withLock { $0 = [bare: "instance-y"] }
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "k")
        let opened = try #require(bench.servers.last)
        let newStore = try #require(opened.store.withLock { $0 })
        #expect(newStore.deletingLastPathComponent().standardizedFileURL != oldFolder.standardizedFileURL)
        #expect(try await unsent(oldStore) == 2)
        #expect(host.libraryKey(for: bare) == "marfa:instance-y")
        #expect(bench.location.copies.instance(ofFolder: oldFolder.lastPathComponent) == "instance-x")
    }

    @Test func aCopyThatCannotBeReadIsNeverGivenToAnotherAddress() async throws {
        let bench = HostBench()
        let folder = bench.location.directory(for: bare)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let damaged = folder.appending(path: "copy.sqlite")
        try Data("not a store".utf8).write(to: damaged)
        bench.servers.instances.withLock { $0 = [moved: "instance-x"] }
        let host = bench.host()
        try await host.connect(address: moved.address.absoluteString, key: "k")
        #expect(bench.location.directory(for: moved) != folder)
        #expect(try Data(contentsOf: damaged) == Data("not a store".utf8))
    }

    @Test func aCopyThatCannotBeReadNowIsNotTakenForTheInstanceTheServerClaims() async throws {
        let bench = HostBench()
        let folder = bench.location.directory(for: bare)
        let store = try await makeCopy(bench, in: folder, unsent: 1)
        let holder = try await WorkingCopy.open(store: store)
        bench.servers.instances.withLock { $0 = [bare: "instance-y"] }
        bench.servers.copiesSayInstance.withLock { $0 = false }
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "k")
        await holder.close()
        #expect(bench.location.copies.instance(ofFolder: folder.lastPathComponent) == nil)
        #expect(try await unsent(store) == 1)
    }

    @Test func anotherSpellingsCopyOfAnotherInstanceIsNotSentToThisOne() async throws {
        let bench = HostBench()
        let mine = bench.location.directory(for: bare)
        _ = try await makeCopy(bench, in: mine, unsent: 0)
        let otherFolder = Self.folder(of: withPort)
        let otherStore = try await makeCopy(bench, in: bench.location.directory(named: otherFolder), unsent: 1)
        try bench.location.copies.change {
            $0.instances[mine.lastPathComponent] = "instance-y"
            $0.instances[otherFolder] = "instance-x"
        }
        let host = bench.host()
        #expect(host.otherCopies(of: bare).isEmpty)
        #expect(try await unsent(otherStore) == 1)
    }

    @Test func aMarkUnderOneSpellingIsTheMarkOfTheOther() async throws {
        let bench = HostBench()
        _ = try await makeCopy(bench, in: bench.location.directory(for: bare), unsent: 0)
        let host = bench.host()
        host.markDiscarded(withPort, agreed: MarfaHost.Agreed(ids: []))
        #expect(host.discardMark(for: bare) != nil)
        host.markDiscarded(bare, agreed: nil)
        #expect(host.discardMark(for: withPort) == nil)
        #expect(host.discarded.isEmpty)
    }

    // MARK: A discard that could not finish

    /// The copy of instance A is discarded while another program holds it, so it stays, marked. The address then serves
    /// instance B: B's new copy is not taken for A's mark. Back on A, A's copy is removed by its mark, and nothing it
    /// held is opened or sent; B's copy stays.
    @Test func aDiscardThatCouldNotFinishStaysWithItsCopyWhileTheAddressServesAnotherMarfa() async throws {
        let bench = HostBench()
        bench.servers.instances.withLock { $0 = [bare: "instance-a"] }
        bench.servers.storedWrites.withLock { $0 = 2 }
        let busy = Mutex(true)
        let host = bench.host(remover: { store, agreed in
            if busy.withLock({ $0 }) { throw MarfaError.storeBusy(message: "Another program holds it.") }
            try await MarfaHost.removeStore(store, agreedToLose: agreed)
        })
        try await host.connect(address: bare.address.absoluteString, key: "a")
        let first = try #require(bench.servers.last)
        let storeA = try #require(first.store.withLock { $0 })
        let folderA = storeA.deletingLastPathComponent().lastPathComponent
        first.report.set(SyncReport(waiting: 2, queueRead: true))
        #expect(await eventually { host.waitingChanges == 2 })
        bench.servers.storedWrites.withLock { $0 = 0 }

        do {
            try await discardEverything(host)
            Issue.record("a copy another program holds was removed")
        } catch {
            guard case .notRemoved? = error as? MarfaHost.Problem else { throw error }
        }
        busy.withLock { $0 = false }
        #expect(Array(host.discarded.keys) == [folderA])
        #expect(try await unsent(storeA) == 2)

        bench.servers.instances.withLock { $0 = [bare: "instance-b"] }
        try await host.connect(address: bare.address.absoluteString, key: "b")
        let storeB = try #require(bench.servers.last?.store.withLock { $0 })
        #expect(storeB.deletingLastPathComponent().lastPathComponent != folderA)
        #expect(Array(host.discarded.keys) == [folderA], "B's copy is not the copy discarded")
        #expect(try await unsent(storeA) == 2)
        try await host.disconnect(.keepCopy)

        bench.servers.instances.withLock { $0 = [bare: "instance-a"] }
        try await host.connect(address: bare.address.absoluteString, key: "a")
        let again = try #require(bench.servers.last)
        #expect(again.store.withLock { $0 } == storeA)
        #expect(try await again.storeWrites.isEmpty, "the discarded writes were removed, never opened to be sent")
        #expect(host.discarded.isEmpty)
        #expect(FileManager.default.fileExists(atPath: storeB.deletingLastPathComponent().path), "B's copy stays")
    }

    /// A mark an older build made under the address is bound to the copy that address opened then, before the address
    /// is opened for another Marfa.
    @Test func anOlderBuildsMarkIsBoundToItsCopyBeforeTheAddressOpensAnotherMarfa() async throws {
        let bench = HostBench()
        let folderA = bench.location.directory(for: bare)
        let storeA = try await makeCopy(bench, in: folderA, unsent: 1)
        let shown = try await WorkingCopy.unsentWrites(in: storeA).writes.map(\.id)
        bench.defaults.set([bare.address.absoluteString: shown], forKey: MarfaHost.discardedKey)
        bench.servers.instances.withLock { $0 = [bare: "instance-b"] }
        try bench.location.copies.change { $0.instances[folderA.lastPathComponent] = "instance-a" }
        let host = bench.host()
        #expect(host.discarded.keys.sorted() == [folderA.lastPathComponent])

        try await host.connect(address: bare.address.absoluteString, key: "b")
        #expect(bench.location.directory(for: bare) != folderA)
        #expect(host.discardMark(for: bare) == nil)
        #expect(host.discarded.keys.sorted() == [folderA.lastPathComponent])
        #expect(try await unsent(storeA) == 1)
        try await host.disconnect(.keepCopy)

        bench.servers.instances.withLock { $0 = [bare: "instance-a"] }
        try await host.connect(address: bare.address.absoluteString, key: "a")
        #expect(try await #require(bench.servers.last).storeWrites.isEmpty)
        #expect(host.discarded.isEmpty)
    }

    /// A mark whose address cannot be read is never dropped.
    @Test func aMarkThatNamesNoCopyIsKept() async throws {
        let bench = HostBench()
        bench.defaults.set(["not an address": ["w1"]], forKey: MarfaHost.discardedKey)
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "k")
        #expect(bench.defaults.dictionary(forKey: MarfaHost.discardedKey)?["not an address"] as? [String] == ["w1"])
    }

    @Test func aStepThatDoesNotOpenTheCopyPutsTheRecordBack() async throws {
        let bench = HostBench()
        bench.servers.instances.withLock { $0 = [bare: "instance-x"] }
        bench.servers.failure.withLock { $0 = SourceFailure(kind: .failed, message: "No room.") }
        let host = bench.host()
        await #expect(throws: MarfaHost.Problem.self) { try await host.connect(address: bare.address.absoluteString, key: "k") }
        #expect(bench.location.copies.current == MarfaCopies.Record())
    }

    @Test func anUnreadableRecordIsSetAsideAndTheCopiesAreFoundByTheirAddresses() async throws {
        let bench = HostBench()
        let root = bench.root.appending(path: "Unread", directoryHint: .isDirectory)
        let made = MarfaStoreLocation(root: root).directory(named: Self.folder(of: withPort))
        try FileManager.default.createDirectory(at: made, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: root.appending(path: "Copies.json"))
        let location = MarfaStoreLocation(root: root)
        #expect(location.directory(for: bare) == made)
        let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
        #expect(names.contains { $0.hasPrefix("Copies unreadable") })
        #expect(location.copies.current == MarfaCopies.Record())
    }

    // MARK: Copies made under both spellings

    @Test func anOtherSpellingsCopyThatStillHoldsChangesIsKeptAndThePersonIsToldOnce() async throws {
        let bench = HostBench()
        let mine = try await makeCopy(bench, in: bench.location.directory(for: bare), unsent: 1)
        #expect(bench.location.otherSpellings(of: bare).isEmpty)
        let withPortStore = try await makeCopy(
            bench, in: bench.root.appending(path: Self.folder(of: withPort), directoryHint: .isDirectory), unsent: 2)
        #expect(bench.location.otherSpellings(of: bare) == [Self.folder(of: withPort)])

        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "k")
        let source = try #require(bench.servers.last)
        #expect(source.store.withLock { $0 } == mine)
        source.state.set(.online)
        #expect(await eventually { host.notices.waiting.contains { $0.title == "Changes Still Waiting" } })
        // The fake server cannot be reached, so both changes wait in the other copy, untouched.
        #expect(try await unsent(withPortStore) == 2)
        #expect(try await unsent(mine) == 1)
        #expect(FileManager.default.fileExists(atPath: withPortStore.path))
    }

    @Test func anOtherSpellingsCopyWithNothingWaitingIsRemoved() async throws {
        let bench = HostBench()
        _ = try await makeCopy(bench, in: bench.location.directory(for: bare), unsent: 0)
        let otherFolder = bench.root.appending(path: Self.folder(of: withPort), directoryHint: .isDirectory)
        _ = try await makeCopy(bench, in: otherFolder, unsent: 0)
        let host = bench.host()
        try await host.connect(address: bare.address.absoluteString, key: "k")
        try #require(bench.servers.last).state.set(.online)
        #expect(await eventually { !FileManager.default.fileExists(atPath: otherFolder.path) })
    }

    @Test func anotherCopyThatAnotherProgramHoldsIsLeftAsItIs() async throws {
        let bench = HostBench()
        let otherFolder = bench.root.appending(path: Self.folder(of: withPort), directoryHint: .isDirectory)
        let store = try await makeCopy(bench, in: otherFolder, unsent: 1)
        let holder = try await WorkingCopy.open(store: store)
        let outcome = await MarfaHost.send(store, to: try Server(url: bare.address, key: "k"))
        await holder.close()
        #expect(outcome == .waiting(0))
        #expect(try await unsent(store) == 1)
    }

    /// The folder an older build named for `connection`'s spelling.
    private static func folder(of connection: MarfaConnection) -> String {
        MarfaStoreLocation(root: URL.temporaryDirectory.appending(path: UUID().uuidString)).directory(for: connection).lastPathComponent
    }
}
