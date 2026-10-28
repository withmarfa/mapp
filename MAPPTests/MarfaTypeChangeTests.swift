import Foundation
import Marfa
import MarfaTesting
import struct MarfaCore.Item
import struct MarfaCore.KeptFetch
import Testing
@testable import MAPP

/// Changing an item's type through `MarfaLibrary`: what it sends, what it refuses before sending, and its undo.
@MainActor
@Suite(.hangLimit) struct MarfaTypeChangeTests {
    typealias F = TypeChangeFixture
    private static let launch = ItemID("launch")

    private static func note(_ id: ItemID, title: String, version: Int64 = 1, type: TypeID = F.note, properties: [Property] = []) -> MAPP.Item {
        let date = Date(timeIntervalSince1970: 1_000_000)
        return MAPP.Item(
            id: id, type: type, title: title, titleRule: .property("title"),
            properties: [Property(key: "title", value: .string(title))] + properties, version: ItemVersion(version),
            created: date, modified: date)
    }

    private func loaded(_ items: [MAPP.Item], bodies: [ItemID: String]) async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        for (id, text) in bodies { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source, notices: Notices())
        // Pages other suites leave open are not this test's to wait on.
        library.handOverEdits = { $0(true) }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private let start: PropertyValue = .string("2026-10-26T09:00:00Z")

    @Test func theTitleAndTextMoveInTheEditThatChangesTheType() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        library.changeType([Self.launch], to: F.event, filling: ["starts_at": start], undoManager: nil)
        #expect(source.writes == [
            .retype(Self.launch, F.event, ["body": F.gone, "description": .string("Agenda"), "starts_at": start], base: ItemVersion(1)),
        ])

        // Where the keys are the same, only the type changes.
        source.clearWrites()
        library.changeType([Self.launch], to: F.task, filling: [:], undoManager: nil)
        #expect(source.writes == [.retype(Self.launch, F.task, [:], base: ItemVersion(1))])
    }

    @Test func aChangeMissingARequiredValueOrWithNoPlaceForTheTextIsNotSent() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        library.changeType([Self.launch], to: F.event, filling: [:], undoManager: nil)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Change Type"))
        library.changeType([Self.launch], to: F.entity, filling: [:], undoManager: nil)
        #expect(library.notices.told == 2)
        #expect(source.writes.isEmpty)
        #expect(library.item(Self.launch)?.type == F.note)
    }

    @Test func aRefusedChangeIsTold() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        library.changeType([Self.launch], to: F.task, filling: [:], undoManager: nil)
        let write = try #require(source.submitted.first?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "type_not_permitted", message: "This key can’t write tasks."))))
        #expect(await eventually { library.notices.waiting.last?.title == String(localized: "Can’t Change Type") })
        #expect(library.notices.waiting.last?.message.contains("This key can’t write tasks.") == true)
    }

    @Test func undoPutsBackExactlyWhatTheChangeMoved() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        let undo = UndoManager()
        library.changeType([Self.launch], to: F.event, filling: ["starts_at": start], undoManager: undo)
        #expect(undo.undoActionName == String(localized: "Change Type"))

        // The copy shows the change.
        source.setBody("Agenda", of: Self.launch, version: 2)
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 2, type: F.event, properties: [Property(key: "starts_at", value: start)])]))
        #expect(await eventually { library.item(Self.launch)?.type == F.event })

        undo.undo()
        #expect(source.writes.last == .retype(
            Self.launch, F.note, ["body": .string("Agenda"), "description": F.gone, "starts_at": F.gone], base: ItemVersion(2)))

        source.setBody("Agenda", of: Self.launch, version: 3)
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 3)]))
        #expect(await eventually { library.item(Self.launch)?.type == F.note })
        undo.redo()
        #expect(source.writes.last == .retype(
            Self.launch, F.event, ["body": F.gone, "description": .string("Agenda"), "starts_at": start], base: ItemVersion(3)))
    }

    @Test func undoAfterTypingMovesTheNewTextBack() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        let undo = UndoManager()
        library.changeType([Self.launch], to: F.event, filling: ["starts_at": start], undoManager: undo)
        source.setBody("Agenda, edited", of: Self.launch, version: 3)
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 3, type: F.event, properties: [Property(key: "starts_at", value: start)])]))
        #expect(await eventually { library.body(of: Self.launch)?.text == "Agenda, edited" })

        undo.undo()
        // The typing is kept, and the start stays on the item, which a note does not use.
        #expect(source.writes.last == .retype(
            Self.launch, F.note, ["description": F.gone, "body": .string("Agenda, edited")], base: ItemVersion(3)))
    }

    @Test func undoAfterALaterChangeOfTypeMovesBackFromTheTypeItIsNow() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        let undo = UndoManager()
        library.changeType([Self.launch], to: F.event, filling: ["starts_at": start], undoManager: undo)

        // Another device makes it a highlight, which keeps its title in `text` and its text in `note`.
        source.setBody("Agenda, edited", of: Self.launch, version: 3)
        let date = Date(timeIntervalSince1970: 1_000_000)
        source.send(.upserted([MAPP.Item(
            id: Self.launch, type: F.highlight, title: "Launch", titleRule: .property("text"),
            properties: [Property(key: "text", value: .string("Launch")), Property(key: "starts_at", value: start)],
            version: ItemVersion(3), created: date, modified: date)]))
        #expect(await eventually { library.item(Self.launch)?.type == F.highlight })
        try #require(await eventually { library.body(of: Self.launch)?.text == "Agenda, edited" })

        undo.undo()
        #expect(await eventually { source.writes.count == 2 })
        #expect(source.writes.last == .retype(
            Self.launch, F.note, ["text": F.gone, "title": .string("Launch"), "note": F.gone, "body": .string("Agenda, edited")],
            base: ItemVersion(3)))
    }

    @Test func valuesTypedForAChangeRefusedBeforeQueueingAreGivenBack() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: ""])
        #expect(library.changeType([Self.launch], to: F.message, filling: ["from": .string("Ada Lovelace")], undoManager: nil))
        let write = try #require(source.submitted.last?.id)
        let problem = SyncProblem(code: "hydration_incomplete", message: "Try again in a moment.", notQueued: true)
        source.send(.answered(write, .refused(problem)))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.last?.text?.contains("Ada Lovelace") == true)

        // A change refused before anything is sent says so, so the sheet stays open with what was typed.
        #expect(!library.changeType([Self.launch], to: F.event, filling: [:], undoManager: nil))
    }

    @Test func undoWaitsForTheOpenPagesToHandOverTheirLastEdit() async throws {
        let (library, source) = try await loaded([Self.note(Self.launch, title: "Launch")], bodies: [Self.launch: "Agenda"])
        var handingOver: [(Bool) -> Void] = []
        library.handOverEdits = { handingOver.append($0) }
        let undo = UndoManager()
        library.changeType([Self.launch], to: F.task, filling: [:], undoManager: undo)
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 2, type: F.task)]))
        #expect(await eventually { library.item(Self.launch)?.type == F.task })

        undo.undo()
        #expect(source.writes.count == 1)
        #expect(undo.canRedo)
        try #require(handingOver.count == 1)
        handingOver[0](true)
        #expect(source.writes.last == .retype(Self.launch, F.note, [:], base: ItemVersion(2)))

        // A page that cannot hand over its edit stops the redo, and says so.
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 3)]))
        #expect(await eventually { library.item(Self.launch)?.type == F.note })
        undo.redo()
        try #require(handingOver.count == 2)
        handingOver[1](false)
        #expect(source.writes.count == 2)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Change Type"))
    }

    @Test func severalItemsChangeTogetherAndUndoAsOne() async throws {
        let other = ItemID("other")
        let (library, source) = try await loaded(
            [Self.note(Self.launch, title: "Launch"), Self.note(other, title: "Other", type: F.task)],
            bodies: [Self.launch: "Agenda", other: ""])
        // The empty task could become an entity, which the note with text could not, so the entity is offered and the note skipped.
        #expect(Set(library.typeChangeOptions(for: [Self.launch, other]).map(\.id)) == [F.entity, F.event, F.message, F.note, F.task])
        let undo = UndoManager()
        library.changeType([Self.launch, other], to: F.task, filling: [:], undoManager: undo)
        // The task already is one.
        #expect(source.writes == [.retype(Self.launch, F.task, [:], base: ItemVersion(1))])
        source.send(.upserted([Self.note(Self.launch, title: "Launch", version: 2, type: F.task)]))
        #expect(await eventually { library.item(Self.launch)?.type == F.task })
        undo.undo()
        #expect(source.writes.count == 2)
        #expect(source.writes.last == .retype(Self.launch, F.note, [:], base: ItemVersion(2)))
    }
}

/// A change of type through the package's fake working copy, as the engine queues it.
@MainActor
@Suite(.hangLimit) struct MarfaTypeChangeCopyTests {
    private static let stamp = "2026-10-26T00:00:00Z"

    private static let itemTypes: [Marfa.ItemType] = [
        ItemType(
            id: "core.note", label: "Note",
            fields: [
                TypeField(name: "title", type: "string", declaredBy: "core.note"),
                TypeField(name: "body", type: "string", declaredBy: "core.note"),
            ], titleField: "title", bodyField: "body"),
        ItemType(
            id: "core.event", label: "Event",
            fields: [
                TypeField(name: "title", type: "string", required: true, declaredBy: "core.event"),
                TypeField(name: "description", type: "string", declaredBy: "core.event"),
            ], titleField: "title", bodyField: "description"),
    ]

    private static func open() -> (FakeCopy, MarfaSource) {
        let row = Marfa.Item(
            id: "n1", type: "core.note", properties: ["title": "Launch", "body": "Agenda\n\n- [ ] book a room", "status": "draft"],
            state: .active, tier: .library, version: 1, schemaVersion: 1, source: "test", sourceId: nil, occurredAt: stamp,
            createdAt: stamp, updatedAt: stamp, tags: [])
        let fake = WorkingCopy.fake(items: [row], itemTypes: itemTypes)
        let read = MarfaRead(copy: fake.copy)
        let source = MarfaSource(copy: fake.copy, connection: SampleLibrary.connection, reading: read, refreshing: Whole(copy: fake.copy))
        source.events.yield(.paint)
        return (fake, source)
    }

    private static let n1 = ItemID("n1")

    @Test func aChangeWaitsInTheQueueWhileTheServerIsAwayAndTheTextIsReadFromTheNewKey() async throws {
        let (fake, source) = Self.open()
        fake.verdict = { _ in nil }
        let library = MarfaLibrary(source: source, notices: Notices())
        library.handOverEdits = { $0(true) }
        try #require(await eventually { library.body(of: Self.n1)?.text == "Agenda\n\n- [ ] book a room" })
        let undo = UndoManager()

        library.changeType([Self.n1], to: TypeID("core.event"), filling: [:], undoManager: undo)
        #expect(await eventually { library.item(Self.n1)?.type == TypeID("core.event") })
        #expect(await eventually { library.body(of: Self.n1)?.text == "Agenda\n\n- [ ] book a room" })
        #expect(library.item(Self.n1)?.title == "Launch")
        // What the event does not use stays on the item.
        #expect(library.item(Self.n1)?.value(of: "status") == .string("draft"))
        #expect(library.item(Self.n1)?.value(of: "body") == nil)
        #expect(await eventually { library.syncReport.waiting > 0 })
        #expect(fake.writes.contains { $0.kind == .updateItem && $0.itemId == "n1" && $0.verdict == nil })

        undo.undo()
        #expect(await eventually { library.item(Self.n1)?.type == TypeID("core.note") })
        #expect(library.body(of: Self.n1)?.text == "Agenda\n\n- [ ] book a room")
        #expect(library.item(Self.n1)?.value(of: "description") == nil)
        #expect(library.notices.waiting.isEmpty)
        await source.close()
    }

    @Test func aRefusedChangeLeavesTheItemAsItWas() async throws {
        let (fake, source) = Self.open()
        fake.verdict = { _ in .refused(Refusal(reason: "Cannot move item", code: "invalid_properties")) }
        let library = MarfaLibrary(source: source, notices: Notices())
        try #require(await eventually { library.body(of: Self.n1) != nil })

        library.changeType([Self.n1], to: TypeID("core.event"), filling: [:], undoManager: nil)
        #expect(await eventually { fake.writes.contains { $0.kind == .updateItem && $0.verdict != nil } })
        #expect(await eventually { library.notices.waiting.last?.title == String(localized: "Can’t Change Type") })
        #expect(await eventually { library.item(Self.n1)?.type == TypeID("core.note") })
        #expect(library.body(of: Self.n1)?.text == "Agenda\n\n- [ ] book a room")
        await source.close()
    }
}

/// A copy that is always whole, so the library reads it without a fill.
nonisolated struct Whole: MarfaRefreshing {
    let copy: WorkingCopy
    func readStatus() async throws -> Status {
        Status(sliceTypes: MarfaSync.slice, sliceTier: .all, sliceEdgeTypes: MarfaSync.sliceEdgeTypes, hydration: .complete)
    }
    func hydrate(types: [String], tier: SliceTier, edgeTypes: [String]) async throws -> HydrateReport {
        throw FakeCopyError.unsupported(call: "hydrate")
    }
    func catchUp() async throws {}
    func fetchKept() async throws -> KeptFetch { KeptFetch(fetched: 0, fetchedBytes: 0, attachments: nil) }
}
