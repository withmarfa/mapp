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
@Suite(.hangLimit) struct MarfaHeldUndoTests {
    /// A copy that is whole only when the test says so. Until then it refuses what the package refuses while a fill is
    /// under way: an edge write, and a write to a row it does not hold yet. A write to a row it holds is queued as usual.
    private nonisolated final class Catchup: MarfaReading {
        let read: MarfaRead
        let whole = Mutex(true)
        /// The rows the copy has not received yet.
        let missing = Mutex<Set<String>>([])
        /// Every write the engine tried, refused or not.
        let attempts = Mutex<[ItemWrite]>([])
        /// How many times the engine read every row.
        let fullReads = Mutex(0)

        init(copy: WorkingCopy) { read = MarfaRead(copy: copy) }

        func status() async throws -> Status {
            whole.withLock { $0 } ? Status(hydration: .complete) : Status(hydration: .inProgress)
        }

        func items() async throws -> Rows<Marfa.Item> {
            fullReads.withLock { $0 += 1 }
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
        func links(in id: String) async throws -> BodyLinks { try await read.links(in: id) }
        func items(inView id: String) async throws -> [Marfa.Item] { try await read.items(inView: id) }

        func refuseUntilWhole() throws {
            if !whole.withLock({ $0 }) { throw notWhole }
        }

        private var notWhole: MarfaError { .hydrationIncomplete(message: "The copy is not whole") }

        func refusal(_ write: ItemWrite) -> MarfaError? {
            attempts.withLock { $0.append(write) }
            if whole.withLock({ $0 }) { return nil }
            switch write {
            case .link, .unlink, .moveEdge:
                return notWhole
            case .editProperties(let id, _, _, _), .editBody(let id, _, _, _), .retype(let id, _, _, _), .retier(let id, _, _),
                .transition(let id, _), .tag(let id, _, _):
                return missing.withLock { $0.contains(id.rawValue) } ? notWhole : nil
            case .create, .purge:
                return nil
            }
        }
    }

    private struct Scene {
        let store: TemporaryMarfaCopy
        let copy: WorkingCopy
        let reads: Catchup
        let source: MarfaSource
        let log: ChangeLog
        /// The item an undo or redo writes to, and the item it is linked under.
        let item: MAPP.Item
        let parent: MAPP.Item
        let edge: EdgeID

        func title() async throws -> String? {
            try await copy.items.get(item.id.rawValue)?.properties["title"]?.string
        }

        func rename(to title: String) async throws {
            let version = try #require(await copy.items.get(item.id.rawValue)?.version)
            _ = try await copy.items.update(item.id.rawValue, Edit(properties: JSONObject([("title", .string(title))]), baseVersion: version))
        }

        func links() async throws -> Int {
            try await copy.edges.from(parent.id.rawValue).count
        }

        /// What an Undo of the link writes, made as the library makes it.
        @discardableResult
        func unlink(as group: UndoGroup) -> WriteID {
            let id = WriteID()
            source.submit(.unlink(edge), as: id, undoing: group)
            return id
        }

        @discardableResult
        func relink(as group: UndoGroup) -> WriteID {
            let id = WriteID()
            let draft = EdgeDraft(type: MarfaMapping.parentEdge, source: parent.id, target: item.id)
            source.submit(.link(draft, undoing: nil), as: id, undoing: group)
            return id
        }

        @discardableResult
        func retitle(to title: String, as group: UndoGroup) async throws -> WriteID {
            let version = try #require(await copy.items.get(item.id.rawValue)?.version)
            let id = WriteID()
            source.submit(
                .editProperties(item.id, ["title": .string(title)], base: ItemVersion(version), undoing: nil), as: id, undoing: group)
            return id
        }

        /// The fill that follows an item's move has begun: edges can't be written until it ends.
        func beginFill() { reads.whole.withLock { $0 = false } }

        func becomeWhole() {
            reads.whole.withLock { $0 = true }
            reads.missing.withLock { $0 = [] }
            source.hear(Change(origin: .refreshed(.hydrated), itemId: nil, edgeId: nil))
        }

        func held() async -> Int { await source.engine.held.count }

        /// Returns once the engine has finished holding, which it does after it counts the write as held: it asks the
        /// copy to catch up, then tells itself to read the copy. That read is a whole one if the copy is whole by then,
        /// which would make the write. The engine takes events in order, so the first call returns once it has gone on
        /// to the next event, by which time it has told the read, and the second returns once the read is taken.
        func engineSettled() async {
            await source.engineTook()
            await source.engineTook()
        }
    }

    private func makeScene() async throws -> Scene {
        let store = try TemporaryMarfaCopy()
        let copy = try await store.open()
        try await copy.declareTypes([[
            "id": "example.note", "label": "Note", "title_field": "title", "body_field": "body",
            "fields": ["title": ["type": "string"], "body": ["type": "string"]],
        ]])
        let child = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Second", "body": "Text"]))
        let folder = try await copy.items.create(Draft(type: "example.note", properties: ["title": "Folder"]))
        let folderID = try #require(folder.itemId)
        let childID = try #require(child.itemId)
        _ = try await copy.edges.create(from: folderID, to: childID, type: MarfaMapping.parentEdge)
        let edge = try #require(await copy.edges.from(folderID).first)
        let reads = Catchup(copy: copy)
        let source = MarfaSource(copy: copy, connection: try MarfaConnection(address: "http://127.0.0.1:9"), reading: reads)
        await source.engine.whenRefusing { reads.refusal($0) }
        let log = ChangeLog(source)
        source.events.yield(.paint)
        let painted = try #require(await log.wait { $0.item(titled: "Second") != nil && $0.item(titled: "Folder") != nil })
        let scene = Scene(
            store: store, copy: copy, reads: reads, source: source, log: log, item: try #require(painted.item(titled: "Second")),
            parent: try #require(painted.item(titled: "Folder")), edge: EdgeID(edge.id))
        // The edges were read while the copy was whole; the fill that now begins is the one the undo meets.
        scene.beginFill()
        reads.attempts.withLock { $0 = [] }
        return scene
    }

    private func finish(_ scene: Scene) async {
        await scene.source.close()
        scene.store.remove()
    }

    @Test func anUndoDuringACatchUpIsMadeOnceTheCopyIsWhole() async throws {
        let scene = try await makeScene()
        let id = scene.unlink(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })
        #expect(try await scene.links() == 1)

        scene.becomeWhole()
        try #require(try await eventuallyAsking { try await scene.links() == 0 })
        #expect(await scene.held() == 0)
        #expect(scene.log.current.answer(to: id) == nil)

        // Time for a second reading to make the write again, which it must not.
        scene.becomeWhole()
        try await Task.sleep(for: .milliseconds(300))
        #expect(scene.reads.attempts.withLock { $0 } == [.unlink(scene.edge), .unlink(scene.edge)], "refused once, made once")
        await finish(scene)
    }

    @Test func aHeldUndoWaitsForAWholeReadNotARereadOfWhatItTouches() async throws {
        let scene = try await makeScene()
        scene.unlink(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })
        await scene.engineSettled()

        // The copy is whole again, but a server change reads only the item: what the step touches may still be
        // arriving elsewhere, so only a read of the whole copy may make it.
        scene.reads.whole.withLock { $0 = true }
        scene.source.hear(Change(origin: .server(event: "item.updated", cursor: "1"), itemId: scene.item.id.rawValue, edgeId: nil))
        await scene.source.engineTook()
        #expect(await scene.held() == 1)
        #expect(try await scene.links() == 1)

        // A whole read of a copy still filling does not make it either.
        scene.reads.whole.withLock { $0 = false }
        scene.source.hear(Change(origin: .refreshed(.hydrated), itemId: nil, edgeId: nil))
        await scene.source.engineTook()
        #expect(await scene.held() == 1)

        scene.becomeWhole()
        try #require(try await eventuallyAsking { try await scene.links() == 0 })
        #expect(await scene.held() == 0)
        await finish(scene)
    }

    @Test func anUndoOfAnItemThatChangedMeanwhileIsNotMadeAndIsAnswered() async throws {
        let scene = try await makeScene()
        let id = scene.unlink(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })

        // Another device trashes the item the link is under while the copy catches up.
        _ = try await scene.copy.items.delete(scene.parent.id.rawValue)
        scene.becomeWhole()
        let state = try #require(await scene.log.wait { $0.answer(to: id) != nil })
        let problem = try #require(state.refusal(to: id))
        #expect(problem.code == MarfaEngine.heldChangedCode)
        #expect(try await scene.links() == 1, "newer state is never overwritten")
        #expect(scene.reads.attempts.withLock { $0.count } == 1, "never made")
        await finish(scene)
    }

    @Test func aStepWithALinkAndAnEditIsMadeInOrderAndOnce() async throws {
        let scene = try await makeScene()
        let group = UndoGroup()
        let unlink = scene.unlink(as: group)
        let edit = try await scene.retitle(to: "First", as: group)
        try #require(try await eventuallyAsking { await scene.held() == 2 })
        // The package would queue the edit at once, which would leave the step made in part and out of order.
        #expect(try await scene.title() == "Second")
        #expect(try await scene.links() == 1)
        #expect(scene.reads.attempts.withLock { $0 } == [.unlink(scene.edge)], "the edit waits unattempted behind the link")

        scene.becomeWhole()
        try #require(try await eventuallyAsking { await scene.held() == 0 })
        // The held count falls when the edit is taken, not when the copy has it.
        try #require(try await eventuallyAsking { try await scene.title() == "First" })
        try #require(try await eventuallyAsking { try await scene.links() == 0 })
        scene.becomeWhole()
        try await Task.sleep(for: .milliseconds(300))
        let attempts = scene.reads.attempts.withLock { $0 }
        #expect(attempts.count == 3, "each made once: \(attempts)")
        #expect(attempts.first == .unlink(scene.edge) && attempts.dropFirst().first == .unlink(scene.edge))
        if case .editProperties(let id, _, _, _)? = attempts.last { #expect(id == scene.item.id) } else { Issue.record("\(attempts)") }
        #expect(scene.log.current.answer(to: unlink) == nil && scene.log.current.answer(to: edit) == nil)
        await finish(scene)
    }

    @Test func aStepWhoseLaterWriteTouchesAnItemThatChangedIsMadeInNoPart() async throws {
        let scene = try await makeScene()
        let group = UndoGroup()
        let unlink = scene.unlink(as: group)
        let edit = try await scene.retitle(to: "First", as: group)
        try #require(try await eventuallyAsking { await scene.held() == 2 })

        try await scene.rename(to: "Elsewhere")
        scene.becomeWhole()
        let state = try #require(await scene.log.wait { $0.answer(to: unlink) != nil && $0.answer(to: edit) != nil })
        #expect(state.refusal(to: unlink)?.code == MarfaEngine.heldChangedCode)
        #expect(state.refusal(to: edit)?.code == MarfaEngine.heldChangedCode)
        #expect(try await scene.links() == 1, "the link is not removed either")
        #expect(try await scene.title() == "Elsewhere")
        await finish(scene)
    }

    @Test func anItemEditToARowTheCopyHoldsIsNotHeld() async throws {
        let scene = try await makeScene()
        try await scene.retitle(to: "First", as: UndoGroup())
        try #require(try await eventuallyAsking { try await scene.title() == "First" })
        #expect(await scene.held() == 0)
        await finish(scene)
    }

    @Test func anItemEditToARowTheCopyDoesNotHoldYetWaitsForTheCopyToBeWhole() async throws {
        let scene = try await makeScene()
        scene.reads.missing.withLock { $0 = [scene.item.id.rawValue] }
        try await scene.retitle(to: "First", as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 1 })
        #expect(try await scene.title() == "Second")

        scene.becomeWhole()
        try #require(try await eventuallyAsking { try await scene.title() == "First" })
        await finish(scene)
    }

    @Test func anUndoThenARedoHeldTogetherAreMadeInOrder() async throws {
        let scene = try await makeScene()
        scene.unlink(as: UndoGroup())
        // The redo is another group, and a link the package would refuse if it were tried.
        scene.relink(as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 2 })
        #expect(scene.reads.attempts.withLock { $0.count } == 1, "the redo waits behind the undo")

        scene.becomeWhole()
        try #require(try await eventuallyAsking { await scene.held() == 0 })
        // The held count falls when the writes are taken, not when they are made. The third attempt begins only once the
        // unlink is made, so the link is back only after it.
        try #require(try await eventuallyAsking { try await scene.links() == 1 && scene.reads.attempts.withLock { $0.count } == 3 })
        await finish(scene)
    }

    @Test func anEditAfterAHeldUndoWaitsBehindIt() async throws {
        let scene = try await makeScene()
        scene.unlink(as: UndoGroup())
        try await scene.retitle(to: "First", as: UndoGroup())
        try #require(try await eventuallyAsking { await scene.held() == 2 })
        #expect(try await scene.title() == "Second", "made after the undo it follows, not before")
        await finish(scene)
    }

    @Test func aStepOfManyWritesAsksTheCopyToCatchUpOnce() async throws {
        let scene = try await makeScene()
        let reads = scene.reads.fullReads.withLock { $0 }
        let group = UndoGroup()
        for _ in 0..<200 { scene.unlink(as: group) }
        try #require(try await eventuallyAsking { await scene.held() == 200 })
        try await Task.sleep(for: .milliseconds(300))
        #expect(scene.reads.attempts.withLock { $0.count } == 1, "only the first is tried")
        let made = scene.reads.fullReads.withLock { $0 } - reads
        #expect(made < 10, "\(made) full reads for 200 held writes")
        await finish(scene)
    }

    @Test func aCatchUpThatNeverEndsGivesTheUndoBack() async throws {
        let scene = try await makeScene()
        await scene.source.engine.setHoldLimit(.milliseconds(200))
        let id = scene.unlink(as: UndoGroup())
        let state = try #require(await scene.log.wait { $0.answer(to: id) != nil })
        let problem = try #require(state.refusal(to: id))
        #expect(problem.code == MarfaEngine.heldTimeoutCode)
        #expect(await scene.held() == 0)
        #expect(try await scene.links() == 1)
        await finish(scene)
    }

    @Test func aLibraryThatClosesGivesBackWhatItHeld() async throws {
        let scene = try await makeScene()
        let id = scene.unlink(as: UndoGroup())
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
@Suite(.hangLimit) struct MarfaUndoGiveBackTests {
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

    @Test func aRedoNotMadeKeepsTheTextItCarried() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.setItemProperty(Self.launch, key: "title", value: .string("Renamed"), undoManager: undo))
        undo.undo()
        undo.redo()
        try #require(source.submitted.count == 3)
        refuse(try #require(source.submitted.last?.id), source)
        try #require(await eventually { library.notices.told == 1 })

        let notice = try #require(library.notices.waiting.last)
        #expect(notice.isNotKept)
        #expect(notice.text == "Renamed", "the text is given back, not lost")
        #expect(notice.message.contains(MarfaEngine.heldChanged))
    }

    @Test func anUndoNotMadeIsToldAndNotGivenBackAsText() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.setItemProperty(Self.launch, key: "title", value: .string("Renamed"), undoManager: undo))
        undo.undo()
        refuse(try #require(source.submitted.last?.id), source)
        try #require(await eventually { library.notices.told == 1 })

        let notice = try #require(library.notices.waiting.last)
        #expect(!notice.isNotKept, "the undo is on the stack to choose again, so nothing is lost")
        #expect(undo.canUndo)
    }
}

private extension ChangeLog.State {
    func refusal(to id: WriteID) -> SyncProblem? {
        if case .refused(let problem) = answer(to: id) { problem } else { nil }
    }
}
