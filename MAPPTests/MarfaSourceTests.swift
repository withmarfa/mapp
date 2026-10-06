import Foundation
import Marfa
import Synchronization
import Testing
@testable import MAPP

/// Everything a source has told one reader, and the library as that reader would hold it.
nonisolated final class ChangeLog: Sendable {
    nonisolated struct State {
        var changes: [SourceChange] = []
        var snapshot: SourceSnapshot?

        func item(titled title: String) -> MAPP.Item? {
            snapshot?.items.first { $0.title == title }
        }

        func answer(to id: WriteID) -> WriteOutcome? {
            for case .answered(id, let outcome) in changes { return outcome }
            return nil
        }
    }

    private nonisolated final class Box: Sendable {
        let state = Mutex(State())
    }

    private let box: Box
    private let reading: Task<Void, Never>

    init(_ source: MarfaSource) {
        let changes = source.changes()
        let box = Box()
        self.box = box
        reading = Task {
            for await change in changes {
                box.state.withLock { state in
                    state.changes.append(change)
                    if case .loaded(let snapshot) = change { state.snapshot = snapshot } else { state.snapshot?.apply(change) }
                }
            }
        }
    }

    deinit { reading.cancel() }

    var current: State { box.state.withLock { $0 } }

    /// Waits for `condition` to hold, and answers the state that met it, or nil when it never did.
    func wait(for timeout: Duration = .seconds(30), until condition: (State) -> Bool) async -> State? {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            let current = self.current
            if condition(current) { return current }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }
}

nonisolated func waitForConnection(
    _ source: MarfaSource, for timeout: Duration = .seconds(30), until condition: (MarfaConnectionState) -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let end = clock.now + timeout
    while clock.now < end {
        if condition(source.connectionState) { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return false
}

private func scratch() -> URL {
    URL.temporaryDirectory.appending(path: "MarfaSourceTests-\(UUID().uuidString)", directoryHint: .isDirectory)
}

/// A server that refuses every connection, so a copy made for it never hears from it.
@Suite(.serialized)
struct MarfaSourceOfflineTests {
    @Test(.timeLimit(.minutes(1)))
    func aCopyPaintsAndKeepsWritesWithoutTheServer() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        let keys = MemoryKeyStore([connection: "unused"])
        let location = try MarfaStoreLocation(root: root)

        let source = try await MarfaSource.open(connection, keys: keys, location: location)
        let log = ChangeLog(source)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        guard case .loaded(let first) = painted.changes.first else { Issue.record("the first change is not loaded"); return }
        #expect(first.items.isEmpty)
        #expect(first.catalogue.itemTypes[TypeID("core.note")] != nil)
        #expect(source.connectionState == .connecting)

        source.refresh()
        #expect(await waitForConnection(source) { if case .offline = $0 { true } else { false } })

        let write = WriteID()
        let id = ItemID.mint()
        source.submit(.create(id: id, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST offline", body: "Kept")), as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MAPPTEST offline") != nil })
        #expect(queued.item(titled: "MAPPTEST offline")?.id == id)
        #expect(queued.item(titled: "MAPPTEST offline")?.sync == .waiting(writes: 1))
        #expect(queued.answer(to: write) == nil)
        await source.flush()
        await source.close()

        let reopened = try await MarfaSource.open(connection, keys: keys, location: location)
        let again = ChangeLog(reopened)
        let repainted = try #require(await again.wait { $0.snapshot != nil })
        let kept = try #require(repainted.item(titled: "MAPPTEST offline"))
        #expect(kept.sync == .waiting(writes: 1))
        #expect(try await reopened.body(of: kept.id).text == "Kept")
        #expect(reopened.connectionState == .connecting)
        await reopened.close()
    }

    @Test func aMissingKeyIsDenied() async throws {
        let connection = try MarfaConnection(address: "http://127.0.0.1:9")
        await #expect(throws: SourceFailure.self) {
            _ = try await MarfaSource.open(connection, keys: MemoryKeyStore(), location: try MarfaStoreLocation(root: scratch()))
        }
    }

    private func open(_ root: URL, at address: String = "http://127.0.0.1:9") async throws -> MarfaSource {
        let connection = try MarfaConnection(address: address)
        return try await MarfaSource.open(
            connection, keys: MemoryKeyStore([connection: "unused"]), location: try MarfaStoreLocation(root: root))
    }

    /// An address nothing answers holds a connection open until it times out, which must not hold up a write.
    @Test(.timeLimit(.minutes(3)))
    func aWriteIsQueuedAtOnceWhileTheServerHangs() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root, at: "http://10.255.255.1:8210")
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.refresh()
        try await Task.sleep(for: .milliseconds(200))
        let clock = ContinuousClock()
        let start = clock.now
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST hanging", body: "Queued")), as: WriteID())
        let shown = await log.wait(for: .seconds(2)) { $0.item(titled: "MAPPTEST hanging") != nil }
        #expect(shown != nil, "the write waited \(clock.now - start) behind the network")
        #expect(source.connectionState == .connecting)
        await source.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func aSecondOpenerOfTheSameCopyIsRefused() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await open(root)
        await #expect(throws: SourceFailure.self) { _ = try await open(root) }
        await first.close()
        let again = try await open(root)
        await again.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func aBodyForATypeWithoutABodyFieldIsRefused() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        let painted = try #require(await log.wait { $0.snapshot != nil })
        let entity = try #require(painted.snapshot?.catalogue.itemTypes[TypeID("core.entity")])
        #expect(entity.bodyField == nil)
        let write = WriteID()
        source.submit(.create(id: .mint(), ItemDraft(type: entity.id, title: "Ada", body: "Typed text")), as: write)
        let answered = try #require(await log.wait { $0.answer(to: write) != nil })
        #expect(answered.answer(to: write) == .refused(SyncProblem(code: "unsupported", message: MarfaEngine.noText)))
        #expect(try await source.copy.queue.all().isEmpty)
        await source.close()
    }

    /// The child is queued and answered as itself; a parent link that cannot be made is told on its own.
    @Test(.timeLimit(.minutes(1)))
    func aCreateIsKeptWhateverBecomesOfItsParentLink() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        let write = WriteID()
        let child = ItemID.mint()
        source.submit(
            .create(id: child, ItemDraft(type: TypeID("core.note"), title: "MAPPTEST child", body: "Queued", parent: ItemID("not-an-item"))),
            as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MAPPTEST child") != nil })
        #expect(queued.item(titled: "MAPPTEST child")?.id == child)
        #expect(queued.answer(to: write) == nil)
        let creates = try await source.copy.queue.all().filter { $0.kind == .createItem }
        #expect(creates.map(\.itemId) == [child.rawValue])
        await source.close()
    }

    /// A read that fails says so and keeps what was shown, rather than emptying the library or settling it.
    @Test(.timeLimit(.minutes(1)))
    func aReadThatFailsKeepsWhatWasShown() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST kept", body: "Queued")), as: WriteID())
        _ = try #require(await log.wait { $0.item(titled: "MAPPTEST kept") != nil })

        await source.copy.close()
        source.events.yield(.change(Change(origin: .refreshed(.caughtUp), itemId: nil, edgeId: nil)))
        let failed = try #require(await log.wait { state in
            state.changes.contains { if case .unavailable = $0 { true } else { false } }
        })
        #expect(failed.item(titled: "MAPPTEST kept")?.sync == .waiting(writes: 1))
        await source.close()
    }

    /// The follow stops when the copy expires, and only a new hydration starts it again.
    @Test(.timeLimit(.minutes(1)))
    func anExpiredCopyIsHydratedAgain() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        _ = try #require(await log.wait { $0.snapshot != nil })
        #expect(source.connectionState == .connecting)
        let expired = MarfaError.copyExpired(reason: "read_view_changed", message: "the copy expired")
        source.events.yield(.change(Change(origin: .stopped(expired), itemId: nil, edgeId: nil)))
        // Hydrating again against a closed port fails at once, which shows the hydration was tried.
        #expect(await waitForConnection(source, for: .seconds(8)) { if case .offline = $0 { true } else { false } })
        await source.close()
    }

    @Test func aWriteToACopyBeingBroughtUpToDateIsRefusedPlainly() {
        for error in [
            MarfaError.hydrationIncomplete(message: "hydration did not complete; hydrate again before reading"),
            MarfaError.copyExpired(reason: "catchup_too_old", message: "the copy expired")
        ] {
            #expect(MarfaEngine.problem(for: error) == SyncProblem(code: error.code(), message: MarfaEngine.notCurrent))
        }
        let other = MarfaError.validation(code: "invalid_properties", message: "body: Required field is missing")
        #expect(MarfaEngine.problem(for: other) == SyncProblem(code: other.code(), message: other.message))
    }

    @Test func aDrainIsJudgedByWhatItCouldNotSend() {
        #expect(MarfaSync.result(of: DrainReport()) == .idle)
        #expect(MarfaSync.result(of: DrainReport(answered: 2)) == .online)
        // The core answers a refused key `blocked`, which counts as answered, and then parks the queue.
        #expect(MarfaSync.result(of: DrainReport(answered: 1, stopped: "credential_refused")) == .parked("credential_refused"))
        #expect(MarfaSync.result(of: DrainReport(answered: 1, undelivered: 2, unavailable: "network: timeout")) ==
            .offline("network: timeout"))
        #expect(MarfaSync.result(of: DrainReport(undelivered: 1, unavailable: "io: refused")) == .offline("io: refused"))
    }

    @Test func aRetryWaitsLongerAfterEachFailureUpToFiveMinutes() {
        #expect(MarfaSync.delay(after: 1) == .seconds(5))
        #expect(MarfaSync.delay(after: 2) == .seconds(10))
        #expect(MarfaSync.delay(after: 7) == .seconds(300))
        #expect(MarfaSync.delay(after: 100) == .seconds(300))
    }
}

extension LiveMarfaTests {
    /// Runs against the test instance only when `MARFA_TEST_URL` and `MARFA_TEST_MAPP_KEY` are in the environment
    /// (passed to xcodebuild as `TEST_RUNNER_MARFA_TEST_URL` and `TEST_RUNNER_MARFA_TEST_MAPP_KEY`). Every item it
    /// makes has a title starting `MAPPTEST ` and is purged when the test ends, passed or not, over HTTP with the key's
    /// `items.purge`, since the package cannot purge yet.
    @Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
    struct MarfaSourceLiveTests {
        private static let note = TypeID("core.note")

        private func open(_ root: URL) async throws -> MarfaSource {
            let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
            return try await MarfaSource.open(
                connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
                location: try MarfaStoreLocation(root: root))
        }

        /// Runs `body` with a fresh copy, already refreshed, and purges every id it mints, however it ends.
        private func withSource(
            _ body: (MarfaSource, ChangeLog, LiveMarfa.Made) async throws -> Void
        ) async throws {
            let root = scratch()
            let made = LiveMarfa.Made()
            let source = try await open(root)
            let log = ChangeLog(source)
            do {
                source.refresh()
                #expect(await waitForConnection(source) { $0 == .online })
                _ = try #require(await log.wait { ($0.snapshot?.items.count ?? 0) > 100 })
                try await body(source, log, made)
            } catch {
                await source.close()
                await LiveMarfa.purge(made.ids)
                try? FileManager.default.removeItem(at: root)
                throw error
            }
            await source.close()
            await LiveMarfa.purge(made.ids)
            try? FileManager.default.removeItem(at: root)
        }

        @Test(.timeLimit(.minutes(2)))
        func readsTheLibraryAndPaintsItAgainBeforeTheNetwork() async throws {
            let root = scratch()
            defer { try? FileManager.default.removeItem(at: root) }
            let source = try await open(root)
            let log = ChangeLog(source)
            source.refresh()
            let hydrated = try #require(await log.wait { state in
                (state.snapshot?.items.count ?? 0) > 100 && state.snapshot?.catalogue.itemTypes[MarfaMapping.projectType] != nil
            })
            #expect(await waitForConnection(source) { $0 == .online })
            let snapshot = try #require(hydrated.snapshot)
            let catalogue = snapshot.catalogue
            #expect(catalogue.itemTypes[MarfaMapping.projectType]?.titleField == "title")
            #expect(catalogue.edgeTypes["parent-of"]?.reverseName == "child-of")
            #expect(snapshot.items.allSatisfy { !$0.title.isEmpty })

            // A project lists itself and its children, which hold it as `child-of`.
            let projects = snapshot.places.compactMap { place -> ItemID? in
                if case .beneath(let id) = place.id { id } else { nil }
            }
            let project = try #require(projects.first { id in
                snapshot.items.contains { $0.edgesOut.contains { $0.type == "child-of" && $0.target == .item(id) } }
            })
            let children = snapshot.items.filter { item in
                item.edgesOut.contains { $0.type == "child-of" && $0.target == .item(project) }
            }
            let beneath = try await source.copy.items.list(ListFilters(beneath: project.rawValue)).map { ItemID($0.id) }
            #expect(!children.isEmpty)
            #expect(Set(children.map(\.id)).isSubset(of: Set(beneath)))

            let projectItem = try #require(snapshot.items.first { $0.id == project })
            let body = try await source.body(of: project)
            #expect(body.version == projectItem.version)
            #expect(projectItem.properties.allSatisfy { $0.key != "body" })

            let word = try #require(projectItem.title.split(separator: " ").first { $0.count > 3 }.map(String.init))
            let found = try await source.search(word, in: ItemQuery(types: [MarfaMapping.projectType]))
            #expect(found.contains(project))
            #expect(found.allSatisfy { id in snapshot.items.first { $0.id == id }?.type == MarfaMapping.projectType })
            let count = snapshot.items.count
            await source.close()

            let reopened = try await open(root)
            let again = ChangeLog(reopened)
            let repainted = try #require(await again.wait { $0.snapshot != nil })
            #expect(repainted.snapshot?.items.count == count)
            #expect(reopened.connectionState == .connecting)
            await reopened.close()
        }

        @Test(.timeLimit(.minutes(2)))
        func favoritesEditsArchivesAndBinsItsOwnItem() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST favorite \(UUID().uuidString.prefix(8))"
                let created = WriteID()
                let id = made.mint()
                source.submit(
                    .create(id: id, ItemDraft(type: Self.note, title: title, body: "Made by the MAPP tests.", tags: ["mapptest"])),
                    as: created)
                let answered = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
                #expect(answered.answer(to: created) == .accepted)
                let item = try #require(answered.item(titled: title))
                #expect(item.id == id)
                #expect(item.tags == ["mapptest"])
                #expect(item.properties.map(\.key) == ["title"])

                func apply(_ write: ItemWrite) async throws -> ChangeLog.State {
                    let id = WriteID()
                    source.submit(write, as: id)
                    let answered = try #require(await log.wait { $0.answer(to: id) != nil })
                    #expect(answered.answer(to: id) == .accepted, "\(write)")
                    return try #require(await log.wait { $0.item(titled: title)?.sync == .settled })
                }

                var state = try await apply(.tag(item.id, ItemTag.favorite, on: true))
                #expect(state.item(titled: title)?.isFavorite == true)
                let favorites = try #require(state.snapshot?.places.first { $0.id == .favorites }?.query)
                let favorite = try #require(state.item(titled: title))
                #expect(favorites.matches(favorite, catalogue: try #require(state.snapshot?.catalogue)))

                state = try await apply(.editBody(item.id, "Edited by the MAPP tests.", base: favorite.version, merge: .ifUnchanged))
                #expect(try await source.body(of: item.id).text == "Edited by the MAPP tests.")

                state = try await apply(.tag(item.id, ItemTag.favorite, on: false))
                #expect(state.item(titled: title)?.isFavorite == false)

                state = try await apply(.transition(item.id, .archived))
                #expect(state.item(titled: title)?.state == .archived)
                state = try await apply(.transition(item.id, .active))
                #expect(state.item(titled: title)?.state == .active)

                let unsupported = WriteID()
                source.submit(.retype(item.id, TypeID("core.task"), base: item.version), as: unsupported)
                let refused = try #require(await log.wait { $0.answer(to: unsupported) != nil })
                guard case .refused(let problem) = refused.answer(to: unsupported) else {
                    Issue.record("a retype was not refused")
                    return
                }
                #expect(problem.code == "unsupported")

                // Marfa cannot list or restore the bin once the delete is sent, so the item leaves the copy.
                let binned = WriteID()
                source.submit(.transition(item.id, .trashed), as: binned)
                let gone = try #require(await log.wait { $0.answer(to: binned) != nil && $0.item(titled: title) == nil })
                #expect(gone.answer(to: binned) == .accepted)
            }
        }

        /// An editor that read the item before another device's edit arrived saves twice from that read: the first is
        /// merged against what it read, and the second follows the first rather than conflicting with it.
        @Test(.timeLimit(.minutes(2)))
        func editsReadBeforeAnotherDevicesEditAreMerged() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST as read \(UUID().uuidString.prefix(8))"
                let id = made.mint()
                let created = WriteID()
                source.submit(.create(id: id, ItemDraft(type: Self.note, title: title, body: "One")), as: created)
                let read = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
                let version = try #require(read.item(titled: title)?.version)

                let otherRoot = scratch()
                defer { try? FileManager.default.removeItem(at: otherRoot) }
                try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
                let address = try #require(LiveMarfa.address.flatMap { URL(string: $0) })
                let key = try #require(LiveMarfa.key)
                let other = try await WorkingCopy.open(
                    store: otherRoot.appending(path: "other.sqlite"), server: Server(url: address, key: key))
                _ = try await other.hydrate(types: ["core.*"], tier: .library)
                let row = try #require(try await other.items.get(id.rawValue))
                _ = try await other.items.update(id.rawValue, Edit(properties: ["description": "From another device"], baseVersion: row.version))
                _ = try await other.queue.drain()
                await other.close()
                _ = try #require(await log.wait { ($0.item(titled: title)?.version ?? version) > version })

                let first = WriteID(), second = WriteID()
                source.submit(.editBody(id, "Two", base: version, merge: .asRead), as: first)
                source.submit(.editBody(id, "Three", base: version, merge: .asRead), as: second)
                let answered = try #require(await log.wait {
                    $0.answer(to: first) != nil && $0.answer(to: second) != nil && $0.item(titled: title)?.sync == .settled
                })
                for write in [first, second] {
                    switch answered.answer(to: write) {
                    case .accepted, .merged: break
                    case let other: Issue.record("an edit read earlier was answered \(String(describing: other))")
                    }
                }
                #expect(try await source.body(of: id).text == "Three")
                #expect(answered.item(titled: title)?.value(of: "description") == .string("From another device"))
                source.submit(.transition(id, .trashed), as: WriteID())
                await source.flush()
            }
        }

        /// A conflict answered in an earlier launch, and not yet forgotten, stays shown through later writes.
        @Test(.timeLimit(.minutes(2)))
        func aConflictFromAnEarlierLaunchStaysShown() async throws {
            let root = scratch()
            let made = LiveMarfa.Made()
            defer { try? FileManager.default.removeItem(at: root) }
            do {
                try await conflictFromAnEarlierLaunch(root, made)
            } catch {
                await LiveMarfa.purge(made.ids)
                throw error
            }
            await LiveMarfa.purge(made.ids)
        }

        private func conflictFromAnEarlierLaunch(_ root: URL, _ made: LiveMarfa.Made) async throws {
            let address = try #require(LiveMarfa.address), key = try #require(LiveMarfa.key)
            let connection = try MarfaConnection(address: address)
            let location = try MarfaStoreLocation(root: root)
            let keys = MemoryKeyStore([connection: key])
            let a = made.mint(), b = made.mint()
            let tag = UUID().uuidString.prefix(8)

            var source = try await MarfaSource.open(connection, keys: keys, location: location)
            var log = ChangeLog(source)
            source.refresh()
            _ = try #require(await log.wait { ($0.snapshot?.items.count ?? 0) > 100 })
            source.submit(.create(id: a, ItemDraft(type: Self.note, title: "MAPPTEST earlier A \(tag)", body: "One")), as: WriteID())
            source.submit(.create(id: b, ItemDraft(type: Self.note, title: "MAPPTEST earlier B \(tag)", body: "One")), as: WriteID())
            let both = try #require(await log.wait { state in
                [a, b].allSatisfy { id in state.snapshot?.items.first { $0.id == id }?.sync == .settled }
            })
            let version = try #require(both.snapshot?.items.first { $0.id == a }?.version)
            await source.close()

            let otherRoot = scratch()
            defer { try? FileManager.default.removeItem(at: otherRoot) }
            try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
            let other = try await WorkingCopy.open(store: otherRoot.appending(path: "other.sqlite"), server: connection.server(key: key))
            _ = try await other.hydrate(types: ["core.*"], tier: .library)
            let row = try #require(try await other.items.get(a.rawValue))
            _ = try await other.items.update(a.rawValue, Edit(properties: ["body": "Another device"], baseVersion: row.version))
            _ = try await other.queue.drain()
            await other.close()

            // The app's own store, edited from the version it holds, drained, and closed before it forgot the answer.
            let raw = try await WorkingCopy.open(store: location.store(for: connection), server: connection.server(key: key))
            _ = try await raw.items.update(a.rawValue, Edit(properties: ["body": "This device"], baseVersion: version.rawValue))
            let report = try await raw.queue.drain()
            let sibling = report.verdicts.compactMap { answer -> String? in
                if case .conflicted(let sibling, _)? = answer.verdict { sibling } else { nil }
            }.first
            if let sibling { made.add(ItemID(sibling)) }
            await raw.close()
            _ = try #require(sibling)

            source = try await MarfaSource.open(connection, keys: keys, location: location)
            log = ChangeLog(source)
            let reopened = try #require(await log.wait { $0.snapshot != nil })
            guard case .conflicted? = reopened.snapshot?.items.first(where: { $0.id == a })?.sync else {
                Issue.record("the earlier conflict is not shown")
                await source.close()
                return
            }
            source.refresh()
            #expect(await waitForConnection(source) { $0 == .online })
            let tagged = WriteID()
            source.submit(.tag(b, ItemTag.favorite, on: true), as: tagged)
            _ = try #require(await log.wait { $0.answer(to: tagged) != nil })
            await source.flush()
            let after = try #require(await log.wait { state in
                state.snapshot?.items.first { $0.id == b }?.sync == .settled
            })
            guard case .conflicted? = after.snapshot?.items.first(where: { $0.id == a })?.sync else {
                Issue.record("a later write cleared the earlier conflict")
                await source.close()
                return
            }
            await source.close()
        }

        /// A second drain forgetting answers the engine has not taken yet could lose them, so the next drain waits.
        @Test(.timeLimit(.minutes(2)))
        func aDrainWaitsUntilTheLastAnswersAreTaken() async throws {
            try await withSource { source, log, made in
                let title = "MAPPTEST drains \(UUID().uuidString.prefix(8))"
                let id = made.mint()
                let created = WriteID()
                source.submit(.create(id: id, ItemDraft(type: Self.note, title: title, body: "One")), as: created)
                _ = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })

                let holding = LiveMarfa.Flag()
                await source.engine.whenAnswering {
                    holding.set()
                    try? await Task.sleep(for: .seconds(2))
                }
                let before = await source.engine.sync.drains
                let tagged = WriteID()
                source.submit(.tag(id, ItemTag.favorite, on: true), as: tagged)
                #expect(await LiveMarfa.until { holding.isSet })
                await source.engine.sync.drain()
                try await Task.sleep(for: .milliseconds(800))
                #expect(await source.engine.sync.drains == before + 1)
                await source.engine.whenAnswering(nil)
                _ = try #require(await log.wait { $0.answer(to: tagged) != nil })
                #expect(await LiveMarfa.until { await source.engine.sync.drains == before + 2 })
                source.submit(.transition(id, .trashed), as: WriteID())
                await source.flush()
            }
        }

        @Test(.timeLimit(.minutes(1)))
        func aRefusedWriteIsReportedAndKept() async throws {
            try await withSource { source, log, made in
                // The server makes no items of its own reserved types, so this is refused and nothing is made.
                let write = WriteID()
                source.submit(.create(id: made.mint(), ItemDraft(type: TypeID("system.folder"), title: "MAPPTEST refused")), as: write)
                let answered = try #require(await log.wait { $0.answer(to: write) != nil })
                guard case .refused(let problem) = answered.answer(to: write) else {
                    Issue.record("the create was not refused: \(String(describing: answered.answer(to: write)))")
                    return
                }
                #expect(problem.code == "type_not_permitted")
                let held = try await source.copy.queue.all().filter { write in
                    if case .refused = write.verdict { write.kind == .createItem } else { false }
                }
                #expect(held.count == 1)
                #expect(held.first?.body.isEmpty == false)
                for write in held { _ = try await source.copy.queue.discard(write.id) }
            }
        }
    }
}

/// Every suite that writes to the test instance, one after another, since each reads what the server holds and
/// another's writes would arrive in the middle.
@Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
struct LiveMarfaTests {}

nonisolated enum LiveMarfa {
    static var address: String? { ProcessInfo.processInfo.environment["MARFA_TEST_URL"].flatMap { $0.isEmpty ? nil : $0 } }
    static var key: String? { ProcessInfo.processInfo.environment["MARFA_TEST_MAPP_KEY"].flatMap { $0.isEmpty ? nil : $0 } }
    static var isConfigured: Bool { address != nil && key != nil }

    /// The ids a test minted, each of which is purged when it ends.
    final class Made: Sendable {
        private let minted = Mutex<[ItemID]>([])

        var ids: [ItemID] { minted.withLock { $0 } }

        func mint() -> ItemID {
            let id = ItemID.mint()
            add(id)
            return id
        }

        func add(_ id: ItemID) {
            minted.withLock { $0.append(id) }
        }
    }

    final class Flag: Sendable {
        private let value = Mutex(false)
        var isSet: Bool { value.withLock { $0 } }
        func set() { value.withLock { $0 = true } }
    }

    static func until(_ timeout: Duration = .seconds(20), _ condition: () async -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let end = clock.now + timeout
        while clock.now < end {
            if await condition() { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    /// Bins and then purges each item over HTTP. An item never made answers 404, which is fine.
    static func purge(_ ids: [ItemID]) async {
        guard let address, let key, let base = URL(string: address) else { return }
        for id in ids {
            for (method, path) in [("DELETE", "items/\(id.rawValue)"), ("POST", "items/\(id.rawValue)/purge")] {
                var request = URLRequest(url: base.appending(path: path))
                request.httpMethod = method
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
                let status = (try? await URLSession.shared.data(for: request))
                    .flatMap { ($0.1 as? HTTPURLResponse)?.statusCode }
                if method == "POST", let status, ![200, 204, 404].contains(status) {
                    Issue.record("purging a test item answered \(status)")
                }
            }
        }
    }
}
