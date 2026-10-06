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
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("core.note"), title: "MAPPTEST offline", body: "Kept")), as: write)
        let queued = try #require(await log.wait { $0.item(titled: "MAPPTEST offline") != nil })
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
}

/// Runs against the test instance only when `MARFA_TEST_URL` and `MARFA_TEST_MAPP_KEY` are in the environment
/// (passed to xcodebuild as `TEST_RUNNER_MARFA_TEST_URL` and `TEST_RUNNER_MARFA_TEST_MAPP_KEY`). Every item it
/// makes has a title starting `MAPPTEST ` and the tag `mapptest`, and is put in the bin before the test ends. It
/// stays in the server's bin, since the package cannot purge yet.
@Suite(.serialized, .enabled(if: LiveMarfa.isConfigured))
struct MarfaSourceLiveTests {
    private static let note = TypeID("core.note")

    private func open(_ root: URL) async throws -> MarfaSource {
        let connection = try MarfaConnection(address: try #require(LiveMarfa.address))
        return try await MarfaSource.open(
            connection, keys: MemoryKeyStore([connection: try #require(LiveMarfa.key)]),
            location: try MarfaStoreLocation(root: root))
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
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        source.refresh()
        #expect(await waitForConnection(source) { $0 == .online })
        _ = try #require(await log.wait { ($0.snapshot?.items.count ?? 0) > 100 })

        let title = "MAPPTEST favorite \(UUID().uuidString.prefix(8))"
        let created = WriteID()
        source.submit(
            .create(id: .mint(), ItemDraft(type: Self.note, title: title, body: "Made by the MAPP tests.", tags: ["mapptest"])),
            as: created)
        let made = try #require(await log.wait { $0.answer(to: created) != nil && $0.item(titled: title)?.sync == .settled })
        #expect(made.answer(to: created) == .accepted)
        let item = try #require(made.item(titled: title))
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
        await source.close()
    }

    @Test(.timeLimit(.minutes(1)))
    func aRefusedWriteIsReportedAndKept() async throws {
        let root = scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try await open(root)
        let log = ChangeLog(source)
        source.refresh()
        #expect(await waitForConnection(source) { $0 == .online })

        // The server makes no items of its own reserved types, so this is refused and nothing is made.
        let write = WriteID()
        source.submit(.create(id: .mint(), ItemDraft(type: TypeID("system.folder"), title: "MAPPTEST refused")), as: write)
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
        await source.close()
    }
}

nonisolated enum LiveMarfa {
    static var address: String? { ProcessInfo.processInfo.environment["MARFA_TEST_URL"].flatMap { $0.isEmpty ? nil : $0 } }
    static var key: String? { ProcessInfo.processInfo.environment["MARFA_TEST_MAPP_KEY"].flatMap { $0.isEmpty ? nil : $0 } }
    static var isConfigured: Bool { address != nil && key != nil }
}
