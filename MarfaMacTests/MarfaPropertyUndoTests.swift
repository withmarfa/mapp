import Foundation
import Marfa
import Testing
@testable import MarfaMac

/// An Undo or Redo of a property edit is made only while the item holds exactly what the step before it left, and an
/// Undo puts back what the person had on screen, once any earlier edit of this Mac's it came from is known to be made
/// (`MarfaLibrary+PropertyEdits`).
@MainActor
@Suite(.hangLimit) struct MarfaPropertyUndoTests {
    typealias F = LibraryFixture

    private static let card = TypeID("user.card"), memo = TypeID("user.memo")
    private static let c1 = ItemID("c1")

    /// The fixture, with a type that keeps a summary, numbers and a list, and one that keeps its text in the summary.
    private static var catalogue: Catalogue {
        var catalogue = F.catalogue
        let stops = ListShape(members: [
            .init(key: "name", label: "Name", kind: .text(nil)), .init(key: "minutes", label: "Minutes", kind: .number(NumberRule())),
        ])
        let fields = [
            F.field("title", .text, in: card), F.field("summary", .text, in: card), F.field("amount", .number, in: card),
            F.field("latitude", .number, in: card), F.field("longitude", .number, in: card), F.field("stops", .list(stops), in: card),
        ]
        catalogue.itemTypes[card] = ItemTypeInfo(
            id: card, label: "Card", plural: "Cards", fields: fields, titleField: "title", bodyField: nil, parent: nil)
        catalogue.itemTypes[memo] = ItemTypeInfo(
            id: memo, label: "Memo", plural: "Memos", fields: fields, titleField: "title", bodyField: "summary", parent: nil)
        return catalogue
    }

    private struct Scene {
        let library: MarfaLibrary
        let source: FakeItemSource
        let undo: UndoManager

        var notices: Notices { library.notices }

        /// Edits the item, as an undo step of its own unless `undoable` is false, and gives the edit's write.
        @discardableResult
        func edit(_ id: ItemID, _ changes: [String: PropertyValue?], undoable: Bool = true) throws -> WriteID {
            let before = source.submitted.count
            if undoable { undo.beginUndoGrouping() }
            defer { if undoable { undo.endUndoGrouping() } }
            try #require(library.setItemProperties(id, changes: changes, actionName: "Edit", undoManager: undoable ? undo : nil))
            try #require(source.submitted.count == before + 1, "the edit was written")
            return try #require(source.submitted.last?.id)
        }

        /// Names en1 `name`.
        @discardableResult
        func set(_ name: String, undoable: Bool = true) throws -> WriteID {
            try edit(F.en1, ["name": .string(name)], undoable: undoable)
        }

        /// The copy shows the item holding `values` at `version`, a nil value as no property, as the engine publishes a
        /// row it read.
        func show(_ id: ItemID, _ values: [String: PropertyValue?] = [:], version: Int64) async throws {
            var item = try #require(library.item(id))
            for (key, value) in values {
                item.properties.removeAll { $0.key == key }
                if let value { item.properties.append(Property(key: key, value: value)) }
            }
            item.version = ItemVersion(version)
            source.send(.upserted([item]))
            try #require(await eventually { library.item(id)?.version == ItemVersion(version) })
        }

        func show(_ name: String, version: Int64) async throws {
            try await show(F.en1, ["name": .string(name)], version: version)
        }

        /// The copy takes the write: the engine publishes the row, then says it took it.
        func take(_ write: WriteID, _ id: ItemID, _ values: [String: PropertyValue?], version: Int64) async throws {
            try await show(id, values, version: version)
            source.send(.taken(write))
        }

        func take(_ write: WriteID, showing name: String, version: Int64) async throws {
            try await take(write, F.en1, ["name": .string(name)], version: version)
        }

        /// The server answers the write, its answer saying the item holds `holding`, or what the write set where that
        /// is nil; an `unread` answer says nothing of what it holds.
        func answer(_ write: WriteID, _ outcome: WriteOutcome, holding: [String: PropertyValue]? = nil, unread: Bool = false) {
            source.send(.answered(write, outcome, holding: unread ? nil : holding ?? sent(by: write)))
        }

        /// The server answers the write, and the engine reads the item again.
        func answer(_ write: WriteID, _ outcome: WriteOutcome, showing name: String, version: Int64) async throws {
            answer(write, outcome)
            try await show(name, version: version)
        }

        /// What the write set of each key, a key it cleared being absent.
        func sent(by write: WriteID) -> [String: PropertyValue]? {
            guard case .editProperties(_, let changes, _)? = source.submitted.first(where: { $0.id == write })?.write else { return nil }
            return changes.compactMapValues { $0 }
        }

        /// Another item's change follows everything sent before on the one stream, so once it shows, all of that has
        /// been taken.
        func settle() async throws {
            let mark = UUID().uuidString
            var other = try #require(library.item(F.p2))
            other.properties = [Property(key: "mark", value: .string(mark))]
            source.send(.upserted([other]))
            try #require(await eventually { library.item(F.p2)?.value(of: "mark") == .string(mark) })
        }

        /// The write each step made last, as the item edit it is.
        var lastWrite: ItemWrite? { source.writes.last }
        var lastID: WriteID? { source.submitted.last?.id }
        var lastMessage: String? { notices.waiting.last?.message }
    }

    private func loaded() async throws -> Scene {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let card = F.item(Self.c1, Self.card, "Card", age: 10, properties: [Property(key: "summary", value: .string("Old"))])
        source.send(.loaded(SourceSnapshot(items: F.items + [card], catalogue: Self.catalogue)))
        try #require(await eventually { library.isLoaded })
        let undo = UndoManager()
        undo.groupsByEvent = false
        return Scene(library: library, source: source, undo: undo)
    }

    private func name(_ name: String, base: Int64) -> ItemWrite {
        .editProperties(F.en1, ["name": .string(name)], base: ItemVersion(base))
    }

    private func card(_ key: String, _ value: PropertyValue?, base: Int64) -> ItemWrite {
        var changes: [String: PropertyValue?] = [:]
        changes.updateValue(value, forKey: key)
        return .editProperties(Self.c1, changes, base: ItemVersion(base))
    }

    /// Long enough for a step put back to have been registered again.
    private func waitForAPutBack() async throws {
        try await Task.sleep(for: .milliseconds(100))
    }

    /// #386: the copy had not yet shown the earlier edit when the later one was made.
    @Test func anUndoPutsBackAnEarlierEditTheCopyHadNotShownYet() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L")
        let later = try scene.set("Ada K")
        try await scene.take(earlier, showing: "Ada L", version: 2)
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .accepted, showing: "Ada K", version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 3)
        #expect(scene.lastWrite == name("Ada L", base: 4))
    }

    // MARK: What the copy stored

    /// What the person sent, and what the copy and the server's answer hold of it: a trimmed address, a 20-digit number
    /// as the nearest double, and a clear the copy holds as a null.
    nonisolated static var storedForms: [(String, PropertyValue?, PropertyValue)] {
        let long = PropertyValue.number(Decimal(string: "12345678901234567891")!)
        return [
            ("summary", .string("https://example.com/a "), .string("https://example.com/a")),
            ("amount", long, MarfaMapping.value(MarfaMapping.json(long))),
            ("summary", nil, .null),
        ]
    }

    @Test(arguments: storedForms) func aStepIsJudgedOnWhatTheCopyStoredNotWhatWasSent(
        key: String, sent: PropertyValue?, stored: PropertyValue
    ) async throws {
        #expect(sent != stored, "what the copy stores differs from what was sent")
        let scene = try await loaded()
        let before = scene.library.item(Self.c1)?.value(of: key)
        let edit = try scene.edit(Self.c1, [key: sent])
        try await scene.take(edit, Self.c1, [key: stored], version: 2)
        scene.answer(edit, .accepted, holding: [key: stored])
        try await scene.show(Self.c1, version: 3)

        scene.undo.undo()
        #expect(scene.source.writes.count == 2, "the Undo is made")
        #expect(scene.lastWrite == card(key, before, base: 3))

        let undone = try #require(scene.lastID)
        try await scene.take(undone, Self.c1, [key: before], version: 4)
        scene.answer(undone, .accepted)
        try await scene.show(Self.c1, version: 5)
        scene.undo.redo()
        #expect(scene.source.writes.count == 3, "the Redo is made")
        #expect(scene.lastWrite == card(key, sent, base: 5))
    }

    /// Swift's `==` takes the composed and the decomposed accent for one, but the server stores them as different text.
    @Test func anUndoAfterAnotherDeviceChangedOnlyTheSpellingIsNotMade() async throws {
        let composed = "Caf\u{E9}", decomposed = "Cafe\u{301}"
        #expect(composed == decomposed, "the two spellings are one string to Swift")
        let scene = try await loaded()
        let edit = try scene.set(composed)
        try await scene.take(edit, showing: composed, version: 2)
        try await scene.answer(edit, .accepted, showing: composed, version: 3)
        try await scene.show(decomposed, version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 1, "the other device's spelling is not written over")
        #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
    }

    // MARK: What the server's answer says

    /// The server moved the clear onto a newer version and dropped it, as the core does for a property its edit read
    /// no value for, so the answer holds another device's value; before the item is read again, the answer alone says so.
    @Test(arguments: [true, false]) func anUndoOfAClearTheServerDroppedIsNotMade(dropped: Bool) async throws {
        let scene = try await loaded()
        let edit = try scene.edit(Self.c1, ["summary": nil])
        try await scene.take(edit, Self.c1, ["summary": nil], version: 2)
        scene.answer(edit, .accepted, holding: dropped ? ["summary": .string("Since")] : [:])
        try await scene.settle()
        #expect(scene.library.item(Self.c1)?.value(of: "summary") == nil, "the copy still shows the clear")

        scene.undo.undo()
        if dropped {
            #expect(scene.source.writes.count == 1, "the other device's value is not written over")
            #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
        } else {
            #expect(scene.lastWrite == card("summary", .string("Old"), base: 2))
        }
    }

    @Test func anUndoOfAnEditWhoseAnswerCantBeReadIsNotMade() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        scene.answer(edit, .accepted, unread: true)
        try await scene.show("Ada L", version: 3)

        scene.undo.undo()
        #expect(scene.source.writes.count == 1)
        #expect(scene.lastMessage == MarfaLibrary.answerUnread(undoing: true))
        try await waitForAPutBack()
        #expect(!scene.undo.canUndo, "a step that can't be made is not put back")
    }

    @Test func anUndoBuiltOnAnEarlierEditWhoseAnswerCantBeReadIsNotMade() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        scene.answer(earlier, .accepted, unread: true)
        try await scene.answer(later, .accepted, showing: "Ada K", version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 2)
        #expect(scene.lastMessage == MarfaLibrary.earlierUnknown)
        try await waitForAPutBack()
        #expect(!scene.undo.canUndo)
    }

    /// One key wins the conflict and the other loses it, as the server's answer says through the app's own mapping.
    @Test(arguments: [true, false], [true, false]) func anUndoOfAnEditThatLostAKeyOfAConflictIsNotMade(lost: Bool, readAgain: Bool) async throws {
        let scene = try await loaded()
        let edit = try scene.edit(Self.c1, ["summary": .string("Mine"), "title": .string("Also mine")])
        try await scene.take(edit, Self.c1, ["summary": .string("Mine"), "title": .string("Also mine")], version: 2)
        let summary: JSONValue = lost ? "Theirs" : "Mine"
        let answer: JSONValue = ["item": ["id": "c1", "properties": ["summary": summary, "title": "Also mine"]]]
        let outcome = MarfaMapping.outcome(.conflicted(siblingId: "copy", fields: ["summary"]))
        scene.source.send(.answered(edit, outcome, holding: MarfaMapping.holding(answeredBy: answer)))
        if readAgain {
            try await scene.show(Self.c1, ["summary": MarfaMapping.value(summary)], version: 3)
        } else {
            try await scene.settle()
            #expect(scene.library.item(Self.c1)?.value(of: "summary") == .string("Mine"), "the copy still shows the edit")
        }

        scene.undo.undo()
        if lost {
            #expect(scene.source.writes.count == 1, "the server's value is not written over")
            #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
        } else {
            #expect(scene.source.writes.count == 2, "an edit the server kept whole is undone")
        }
    }

    // MARK: Earlier edits

    @Test func anUndoBuiltOnAnEarlierEditThatWasRefusedIsNotMade() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .refused(SyncProblem(code: "validation_error", message: "Not allowed.")), showing: "Ada K", version: 4)
        try await scene.answer(later, .accepted, showing: "Ada K", version: 5)
        let told = scene.notices.told

        scene.undo.undo()
        #expect(scene.source.writes.count == 2, "nothing is written")
        #expect(scene.notices.told == told + 1)
        #expect(scene.lastMessage == MarfaLibrary.earlierNotMade)
        try await waitForAPutBack()
        #expect(!scene.undo.canUndo, "a step that can't be made is not put back")
    }

    /// Every earlier edit is judged before any is acted on, whichever key comes first.
    @Test(arguments: ["summary", "title"]) func aStepBuiltOnOneRefusedAndOneUnansweredEditIsNotMade(refusedKey: String) async throws {
        let scene = try await loaded()
        let first = try scene.edit(Self.c1, ["summary": .string("S1")], undoable: false)
        try await scene.take(first, Self.c1, ["summary": .string("S1")], version: 2)
        let second = try scene.edit(Self.c1, ["title": .string("T1")], undoable: false)
        try await scene.take(second, Self.c1, ["title": .string("T1")], version: 3)
        let step = try scene.edit(Self.c1, ["summary": .string("S2"), "title": .string("T2")])
        try await scene.take(step, Self.c1, ["summary": .string("S2"), "title": .string("T2")], version: 4)
        scene.answer(refusedKey == "summary" ? first : second, .refused(SyncProblem(code: "validation_error", message: "Not allowed.")))
        try await scene.show(Self.c1, version: 5)

        scene.undo.undo()
        #expect(scene.source.writes.count == 3, "nothing is written")
        #expect(scene.lastMessage == MarfaLibrary.earlierNotMade)
        try await waitForAPutBack()
        #expect(!scene.undo.canUndo, "a step one earlier edit rules out is not put back for the other")
    }

    @Test func anUndoBuiltOnAnEarlierEditWithNoAnswerIsPutBackUntilItIsAnswered() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)

        scene.undo.undo()
        #expect(scene.notices.told == 1)
        #expect(scene.source.writes.count == 2, "nothing is written")
        #expect(scene.lastMessage?.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        try #require(await eventually { scene.undo.canUndo })

        try await scene.answer(earlier, .accepted, showing: "Ada K", version: 4)
        scene.undo.undo()
        #expect(scene.lastWrite == name("Ada L", base: 4))
    }

    /// A step put back goes on the undo stack after its run, so no other step of its group is made again (a board
    /// drag puts each item's edit in one group).
    @Test func aStepPutBackInAGroupMakesNothingElseAgain() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        scene.undo.beginUndoGrouping()
        try scene.set("Ada K")
        let other = try scene.edit(Self.c1, ["summary": .string("New")])
        scene.undo.endUndoGrouping()
        try await scene.take(other, Self.c1, ["summary": .string("New")], version: 2)
        scene.answer(other, .accepted)
        try await scene.show(Self.c1, version: 3)
        let before = scene.source.writes.count

        scene.undo.undo()
        try await waitForAPutBack()
        #expect(scene.lastMessage?.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        #expect(scene.source.writes.count == before + 1, "only the other item's Undo is written")
        #expect(scene.lastWrite == card("summary", .string("Old"), base: 3))
        #expect(scene.undo.canUndo, "the Undo is put back")
    }

    @Test func anUndoAfterARedoPutsBackWhatTheItemHeldWhenTheRedoRan() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        scene.undo.undo()
        let undone = try #require(scene.lastID)
        // Redo runs before the server answers the Undo, so the Redo's own Undo is built on the Undo's write.
        try await scene.take(undone, showing: "Ada", version: 4)
        scene.undo.redo()
        #expect(scene.lastWrite == name("Ada L", base: 4))
        let redone = try #require(scene.lastID)
        try await scene.take(redone, showing: "Ada L", version: 5)

        scene.undo.undo()
        #expect(scene.notices.told == 1)
        #expect(scene.source.writes.count == 3, "nothing is written while the Undo's write has no answer")
        #expect(scene.lastMessage?.hasPrefix(MarfaLibrary.earlierNotAnswered) == true)
        try #require(await eventually { scene.undo.canUndo })

        try await scene.answer(undone, .accepted, showing: "Ada L", version: 6)
        scene.undo.undo()
        #expect(scene.source.writes.count == 4)
        #expect(scene.lastWrite == name("Ada", base: 6))
    }

    /// The person withdrew the earlier edit from the queue, so the server will never answer it. The source answers it
    /// as this sends (`MarfaEngineCoalescingTests.aWriteWithdrawnThroughTheSourceIsAnsweredAsWithdrawn`).
    @Test func anUndoBuiltOnAWithdrawnEditIsNotMade() async throws {
        let scene = try await loaded()
        let earlier = try scene.set("Ada L", undoable: false)
        try await scene.take(earlier, showing: "Ada L", version: 2)
        let later = try scene.set("Ada K")
        try await scene.take(later, showing: "Ada K", version: 3)
        try await scene.answer(earlier, .blocked(.failingAlone, nil), showing: "Ada K", version: 4)
        try await scene.answer(earlier, .refused(SyncProblem(code: MarfaEngine.withdrawnCode)), showing: "Ada K", version: 5)
        #expect(scene.notices.told == 0, "the person withdrew it, so nothing is told")

        scene.undo.undo()
        #expect(scene.source.writes.count == 2)
        #expect(scene.lastMessage == MarfaLibrary.earlierNotMade)
        try await waitForAPutBack()
        #expect(!scene.undo.canUndo)
    }

    // MARK: Changes elsewhere

    @Test func anUndoAfterAnotherDeviceChangedTheKeyIsNotMade() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        try await scene.show("Ada E", version: 4)

        scene.undo.undo()
        #expect(scene.source.writes.count == 1)
        #expect(scene.lastMessage == MarfaLibrary.changedSince(undoing: true))
    }

    @Test func aRedoAfterAnotherDeviceChangedTheKeyIsNotMade() async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        scene.undo.undo()
        #expect(scene.lastWrite == name("Ada", base: 3))
        let undone = try #require(scene.lastID)
        try await scene.take(undone, showing: "Ada", version: 4)
        try await scene.answer(undone, .accepted, showing: "Ada", version: 5)
        try await scene.show("Ada E", version: 6)

        scene.undo.redo()
        #expect(scene.source.writes.count == 2)
        let notice = try #require(scene.notices.waiting.last)
        #expect(notice.text == "Ada L", "what the person typed is given back")
        #expect(notice.message.contains(MarfaLibrary.changedSince(undoing: false)))
    }

    /// The Redo's values are the only copy of what the person set, numbers and a list's entries as well as text.
    @Test func aRedoThatCantBeMadeGivesBackEveryValue() async throws {
        let scene = try await loaded()
        let values: [String: PropertyValue?] = [
            "latitude": .number(Decimal(string: "51.5")!), "longitude": .number(Decimal(string: "-0.12")!),
            "stops": .array([.object(["name": .string("Home"), "minutes": .number(12)])]),
        ]
        let edit = try scene.edit(Self.c1, values)
        try await scene.take(edit, Self.c1, values, version: 2)
        scene.answer(edit, .accepted)
        try await scene.show(Self.c1, version: 3)
        scene.undo.undo()
        let undone = try #require(scene.lastID)
        try await scene.take(undone, Self.c1, values.mapValues { _ in nil }, version: 4)
        scene.answer(undone, .accepted)
        try await scene.show(Self.c1, ["latitude": .number(48)], version: 5)

        scene.undo.redo()
        #expect(scene.source.writes.count == 2)
        let notice = try #require(scene.notices.waiting.last)
        #expect(notice.text == "51.5\n\n-0.12\n\nminutes: 12, name: Home")
        #expect(notice.message.contains(MarfaLibrary.changedSince(undoing: false)))
    }

    /// An item that can't be changed is refused for its own reason, not as one that changed.
    @Test(arguments: [true, false]) func anUndoOfAnItemThatCantBeChangedSaysWhy(damaged: Bool) async throws {
        let scene = try await loaded()
        let edit = try scene.set("Ada L")
        try await scene.take(edit, showing: "Ada L", version: 2)
        try await scene.answer(edit, .accepted, showing: "Ada L", version: 3)
        var item = try #require(scene.library.item(F.en1))
        if damaged { item.problem = ItemProblem(message: "Part of this item couldn’t be read.") } else { item.readOnly = true }
        item.version = ItemVersion(4)
        scene.source.send(.upserted([item]))
        try #require(await eventually { scene.library.item(F.en1)?.version == ItemVersion(4) })

        scene.undo.undo()
        #expect(scene.source.writes.count == 1)
        #expect(scene.lastMessage == (damaged ? "Part of this item couldn’t be read." : BatchSkips.sentence(.readOnly, count: 1)))
    }

    @Test func anUndoOfAKeyThatIsNowTheItemsTextIsNotMade() async throws {
        let scene = try await loaded()
        scene.undo.beginUndoGrouping()
        try #require(scene.library.setItemProperties(
            Self.c1, changes: ["summary": .string("New")], actionName: "Edit", undoManager: scene.undo))
        scene.undo.endUndoGrouping()
        // Elsewhere, the item becomes a type that keeps its text in that key.
        var moved = try #require(scene.library.item(Self.c1))
        moved.type = Self.memo
        moved.properties = [Property(key: "summary", value: .string("New"))]
        moved.version = ItemVersion(2)
        scene.source.send(.upserted([moved]))
        try #require(await eventually { scene.library.item(Self.c1)?.type == Self.memo })

        scene.undo.undo()
        #expect(scene.notices.told == 1)
        #expect(scene.source.writes.count == 1, "the text is never written as a property")
    }
}
