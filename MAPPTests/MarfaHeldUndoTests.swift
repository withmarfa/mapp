import Foundation
import Marfa
import Synchronization
import struct MarfaCore.Edit
import struct MarfaCore.Draft
import struct MarfaCore.Item
import Testing
@testable import MAPP

/// An Undo or Redo pressed while the copy is brought up to date is held by the engine and made once the copy is whole
/// (`MarfaEngine+Holding`), and put back for the person where it can't be.
@Suite struct MarfaHeldUndoTests {
    /// A copy that is whole only when the test says so: edge reads and writes are refused until then, as they are
    /// while the copy hydrates again after an item moved.
    private nonisolated final class Catchup: MarfaReading {
        let read: MarfaRead
        let whole = Mutex(false)
        /// Every write the engine tried, refused or not.
        let attempts = Mutex<[ItemWrite]>([])

        init(copy: WorkingCopy) { read = MarfaRead(copy: copy) }

        func status() async throws -> Status {
            whole.withLock { $0 } ? Status(hydration: .complete) : Status(hydration: .inProgress)
        }

        func items() async throws -> Rows<Marfa.Item> {
            let rows = try await read.items()
            return Rows(rows.rows, completeness: whole.withLock { $0 } ? .complete : .partial)
        }

        func edges(ofTypes types: [String]) async throws -> [Marfa.Edge] {
            try refuseUntilWhole()
            return try await read.edges(ofTypes: types)
        }

        func edges(touching id: String) async throws -> [Marfa.Edge] {
            try refuseUntilWhole()
            return try await read.edges(touching: id)
        }

        func views() async throws -> Rows<LibraryView> { try await read.views() }
        func items(inView id: String) async throws -> [Marfa.Item] { try await read.items(inView: id) }

        func refuseUntilWhole() throws {
            if !whole.withLock({ $0 }) { throw MarfaError.hydrationIncomplete(message: "The copy is not whole") }
        }

        func refusal(_ write: ItemWrite) -> MarfaError? {
            attempts.withLock { $0.append(write) }
            return whole.withLock { $0 } ? nil : .hydrationIncomplete(message: "The copy is not whole")
        }
    }

    private struct Scene {
        let store: TemporaryMarfaCopy
        let copy: WorkingCopy
        let reads: Catchup
        let source: MarfaSource
        let log: ChangeLog
        let item: MAPP.Item

        func title() async throws -> String? {
            try await copy.items.get(item.id.rawValue)?.properties["title"]?.string
        }

        func rename(to title: String) async throws {
            let version = try #require(await copy.items.get(item.id.rawValue)?.version)
            _ = try await copy.items.update(item.id.rawValue, Edit(properties: JSONObject([("title", .string(title))]), baseVersion: version))
        }

        /// What an Undo of the rename to "Second" writes, made as the library makes it.
        func undo(to title: String = "First", as group: UndoGroup) async throws -> WriteID {
            let version = try #require(await copy.items.get(item.id.rawValue)?.version)
            let id = WriteID()
            source.submit(
                .editProperties(item.id, ["title": .string(title)], base: ItemVersion(version), undoing: nil), as: id, undoing: group)
            return id
        }

        func becomeWhole() {
            reads.whole.withLock { $0 = true }
            source.events.yield(.change(Change(origin: .refreshed(.hydrated), itemId: nil, edgeId: nil)))
        }

        func held() async -> Int { await source.engine.held.count }
    }

    private func makeScene() async throws -> Scene {
        let store = try TemporaryMarfaCopy()
        let copy = try await store.open()
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        _ = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Second", "body": "Text"]))
        let reads = Catchup(copy: copy)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "http://127.0.0.1:9"), reading: reads)
        await source.engine.whenRefusing { reads.refusal($0) }
        let log = ChangeLog(source)
        source.events.yield(.paint)
        let painted = try #require(await log.wait { $0.item(titled: "Second") != nil })
        return Scene(store: store, copy: copy, reads: reads, source: source, log: log, item: try #require(painted.item(titled: "Second")))
    }

    private func finish(_ scene: Scene) async {
        await scene.source.close()
        scene.store.remove()
    }

    @Test func anUndoDuringACatchUpIsMadeOnceTheCopyIsWhole() async throws {
        let scene = try await makeScene()
        let id = try await scene.undo(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })
        #expect(try await scene.title() == "Second")

        scene.becomeWhole()
        try #require(try await eventuallyAsking { try await scene.title() == "First" })
        #expect(await scene.held() == 0)
        #expect(scene.log.current.answer(to: id) == nil)

        // Time for a second reading to make the write again, which it must not.
        scene.becomeWhole()
        try await Task.sleep(for: .milliseconds(300))
        #expect(scene.reads.attempts.withLock { $0.count } == 2, "refused once, made once")
        await finish(scene)
    }

    @Test func anUndoOfAnItemThatChangedMeanwhileIsNotMadeAndIsAnswered() async throws {
        let scene = try await makeScene()
        let id = try await scene.undo(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })

        // Another device changes the title while the copy catches up.
        try await scene.rename(to: "Elsewhere")
        scene.becomeWhole()
        let state = try #require(await scene.log.wait { $0.answer(to: id) != nil })
        let problem = try #require(state.refusal(to: id))
        #expect(problem.code == MarfaEngine.heldChangedCode)
        #expect(try await scene.title() == "Elsewhere", "newer text is never overwritten")
        #expect(scene.reads.attempts.withLock { $0.count } == 1, "never made")
        await finish(scene)
    }

    @Test func anUndoThenARedoHeldTogetherAreMadeInOrder() async throws {
        let scene = try await makeScene()
        _ = try await scene.undo(to: "First", as: UndoGroup())
        _ = try await scene.undo(to: "Second", as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 2 })

        scene.becomeWhole()
        try #require(try await eventuallyAsking { await scene.held() == 0 })
        #expect(try await scene.title() == "Second")
        #expect(scene.reads.attempts.withLock { $0.count } == 4)
        await finish(scene)
    }

    @Test func aCatchUpThatNeverEndsGivesTheUndoBack() async throws {
        let scene = try await makeScene()
        await scene.source.engine.setHoldLimit(.milliseconds(200))
        let id = try await scene.undo(as: UndoGroup())
        let state = try #require(await scene.log.wait { $0.answer(to: id) != nil })
        let problem = try #require(state.refusal(to: id))
        #expect(problem.code == MarfaEngine.heldTimeoutCode)
        #expect(await scene.held() == 0)
        #expect(try await scene.title() == "Second")
        await finish(scene)
    }

    @Test func aLibraryThatClosesGivesBackWhatItHeld() async throws {
        let scene = try await makeScene()
        let id = try await scene.undo(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })
        await scene.source.close()
        let state = try #require(await scene.log.wait { $0.answer(to: id) != nil })
        let problem = try #require(state.refusal(to: id))
        #expect(problem.code == MarfaEngine.closedCode)
        scene.store.remove()
    }
}

/// How the library marks the writes of an undo or a redo, and puts back the step the engine could not make.
@MainActor
@Suite struct MarfaUndoGiveBackTests {
    private static let launch = ItemID("launch")

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let date = Date(timeIntervalSince1970: 1_000_000)
        let item = MAPP.Item(
            id: Self.launch, type: TypeChangeFixture.note, title: "Launch", titleRule: .property("title"),
            properties: [Property(key: "title", value: .string("Launch"))], version: ItemVersion(1), created: date, modified: date)
        source.send(.loaded(SourceSnapshot(items: [item], catalogue: TypeChangeFixture.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func refuse(_ write: WriteID, _ source: FakeItemSource, code: String = MarfaEngine.heldChangedCode) {
        source.send(.answered(write, .refused(SyncProblem(code: code, message: MarfaEngine.heldChanged, notQueued: true))))
    }

    @Test func onlyTheWritesOfAnUndoCarryItsGroup() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setFavorite([Self.launch], true, undoManager: undo)
        undo.undo()
        undo.redo()
        #expect(source.submitted.map { $0.undoing != nil } == [false, true, true])
        #expect(source.submitted[1].undoing != source.submitted[2].undoing)
    }

    @Test func anUndoNotMadeGoesBackOnTheStackAndIsTold() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setFavorite([Self.launch], true, undoManager: undo)
        undo.undo()
        #expect(!undo.canUndo)

        refuse(try #require(source.submitted.last?.id), source)
        try #require(await eventually { library.notices.told == 1 })
        #expect(library.notices.waiting.last?.message.contains(String(localized: "Choose Undo again to try it as things are now.")) == true)
        #expect(undo.canUndo, "the entry is kept")
        #expect(!undo.canRedo, "the redo of a change that was never undone is gone")

        // Choosing it again is an ordinary undo, made as things are now.
        undo.undo()
        #expect(source.submitted.count == 3)
    }

    @Test func aRedoNotMadeLeavesNothingThatWouldUndoIt() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setFavorite([Self.launch], true, undoManager: undo)
        undo.undo()
        undo.redo()
        refuse(try #require(source.submitted.last?.id), source)
        try #require(await eventually { library.notices.told == 1 })
        #expect(library.notices.waiting.last?.message.contains(String(localized: "Choose Undo again to try it as things are now.")) == false)

        // The Undo it registered goes with a change that was not made, so it writes nothing.
        undo.undo()
        try #require(await eventually { library.notices.told == 2 })
        #expect(source.submitted.count == 3)
    }
}

private extension ChangeLog.State {
    func refusal(to id: WriteID) -> SyncProblem? {
        if case .refused(let problem) = answer(to: id) { problem } else { nil }
    }
}
