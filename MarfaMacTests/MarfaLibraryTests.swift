import Foundation
import Observation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MarfaMac

/// A small Marfa library: types with subtypes, a project with a child and a grandchild, favorites, an item in the
/// feed, one in the bin, an entity titled by its name and an image.
nonisolated enum LibraryFixture {
    static let note = TypeID("core.note")
    static let ticket = TypeID("aic.ticket")
    static let task = TypeID("aic.ticket.task")
    static let bug = TypeID("aic.ticket.bug")
    static let project = TypeID("aic.project")
    static let entity = TypeID("core.entity")
    static let image = TypeID("core.image")
    static let album = TypeID("core.album")

    static let p1 = ItemID("p1"), p2 = ItemID("p2"), e1 = ItemID("e1"), t1 = ItemID("t1")
    static let n1 = ItemID("n1"), n2 = ItemID("n2"), n3 = ItemID("n3"), en1 = ItemID("en1"), f1 = ItemID("f1")

    static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind, in type: TypeID = note) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: key, kind: kind, declaredBy: type)
    }

    static let ticketFields = [
        field("title", .text), field("body", .text), field("status", .choice(["open", "done"]), in: ticket),
        field("due", .date(includesTime: false), in: ticket),
    ]

    static let catalogue = Catalogue(
        itemTypes: [
            ItemTypeInfo(
                id: note, label: "Note", plural: "Notes", fields: [field("title", .text), field("body", .text)], titleField: "title",
                bodyField: "body", parent: nil, icon: "lucide:file-text"),
            ItemTypeInfo(id: ticket, label: "Ticket", plural: "Tickets", fields: ticketFields, titleField: "title", bodyField: "body", parent: note, icon: "lucide:ticket"),
            ItemTypeInfo(id: task, label: "Task", plural: "Tasks", fields: ticketFields, titleField: "title", bodyField: "body", parent: ticket, icon: "lucide:list-checks"),
            ItemTypeInfo(id: bug, label: "Bug", plural: "Bugs", fields: ticketFields, titleField: "title", bodyField: "body", parent: ticket, icon: "lucide:bug"),
            ItemTypeInfo(
                id: project, label: "Project", plural: "Projects", fields: [field("title", .text), field("body", .text)],
                titleField: "title", bodyField: "body", parent: note, icon: "lucide:folder"),
            ItemTypeInfo(
                id: entity, label: "Entity", plural: "Entities", fields: [field("name", .text, in: entity)], titleField: "name",
                bodyField: nil, parent: nil),
            ItemTypeInfo(id: MarfaMapping.fileType, label: "File", plural: "Files", fields: [], titleField: nil, bodyField: nil, parent: nil, icon: "lucide:file"),
            ItemTypeInfo(id: image, label: "Image", plural: "Images", fields: [], titleField: nil, bodyField: nil, parent: MarfaMapping.fileType, icon: "lucide:image"),
            ItemTypeInfo(
                id: album, label: "Album", plural: "Albums", fields: [field("title", .text, in: album)], titleField: "title", bodyField: nil,
                parent: nil, roles: ["container"]),
        ],
        edgeTypes: [
            EdgeTypeInfo(
                id: "parent-of", label: "Children", reverseLabel: "Parent", reverseName: "child-of", cardinality: .one, writtenFrom: .to,
                fromTypes: [], toTypes: []),
            EdgeTypeInfo(
                id: "about", label: "About", reverseLabel: "Subject of", reverseName: nil, cardinality: .many, writtenFrom: .from,
                fromTypes: [], toTypes: []),
            EdgeTypeInfo(
                id: "supersedes", label: "Supersedes", reverseLabel: "Superseded by", reverseName: nil, cardinality: .one, writtenFrom: .from,
                fromTypes: [ticket], toTypes: [ticket], reverseCardinality: .one),
            EdgeTypeInfo(
                id: "in-collection", label: "In collection", reverseLabel: "Contents", reverseName: nil, cardinality: .many, writtenFrom: .from,
                fromTypes: [], toTypes: [], toRoles: ["container"], flat: true),
            EdgeTypeInfo(
                id: "references", label: "References", reverseLabel: "Referenced by", reverseName: nil, cardinality: .many, writtenFrom: .from,
                fromTypes: [], toTypes: []),
            EdgeTypeInfo(
                id: "in-folder", label: "In folder", reverseLabel: "Folder of", reverseName: nil, cardinality: .many, writtenFrom: .from,
                fromTypes: [], toTypes: [TypeID("system.folder")]),
        ])

    static func child(_ edge: String, _ child: ItemID, of parent: ItemID) -> Edge {
        Edge(id: EdgeID(edge), type: "child-of", from: child, to: .item(parent), origin: .property("child-of"))
    }

    static func item(
        _ id: ItemID, _ type: TypeID, _ title: String, age: Int, state: ItemState = .active, tier: Tier = .library,
        tags: Set<String> = [], edges: [Edge] = [], titleRule: Item.TitleRule = .property("title"),
        properties: [Property] = [], content: Item.Content = .markdown
    ) -> Item {
        let date = Date(timeIntervalSince1970: 1_000_000 - Double(age))
        return Item(
            id: id, type: type, title: title, name: title.isEmpty ? nil : title, titleRule: titleRule, properties: properties, content: content,
            state: state, tier: tier, tags: tags, version: ItemVersion(1), created: date, modified: date,
            trashed: state == .trashed ? date : nil, edgesOut: edges)
    }

    static var items: [Item] {
        [
            item(p1, project, "Alpha", age: 1),
            item(e1, task, "Epic task", age: 2, edges: [child("c1", e1, of: p1)]),
            item(t1, bug, "Bug one", age: 3, tags: [ItemTag.favorite], edges: [child("c2", t1, of: e1)]),
            item(n1, note, "Plain note", age: 4, tags: [ItemTag.favorite], edges: [
                Edge(id: EdgeID("a1"), type: "about", from: n1, to: .item(p1), origin: .property("about")),
                Edge(id: EdgeID("r1"), type: "references", from: n1, to: .item(t1), origin: .body),
            ]),
            item(n2, note, "Feed note", age: 5, tier: .feed),
            item(n3, note, "Old note", age: 6, state: .trashed, tags: [ItemTag.favorite]),
            item(en1, entity, "Ada", age: 7, titleRule: .property("name"), properties: [Property(key: "name", value: .string("Ada"))]),
            item(f1, image, "Photo", age: 8, titleRule: .firstLine, content: .file(.png, byteCount: 0)),
            item(p2, project, "Beta", age: 9),
        ]
    }

    static let texts: [ItemID: String] = [
        p1: "Alpha body", e1: "Task body", t1: "Bug body", n1: "Note body", n2: "Feed body", n3: "Old body", p2: "",
    ]

    static var snapshot: SourceSnapshot {
        SourceSnapshot(items: items, catalogue: catalogue)
    }
}

@MainActor
private func loaded(
    _ items: [Item] = LibraryFixture.items, catalogue: Catalogue = LibraryFixture.catalogue
) async throws -> (MarfaLibrary, FakeItemSource) {
    let source = FakeItemSource()
    for (id, text) in LibraryFixture.texts { source.setBody(text, of: id) }
    let library = MarfaLibrary(source: source, notices: Notices())
    source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
    try #require(await eventually { library.isLoaded })
    return (library, source)
}

private func ids(_ items: [MarfaMac.Item]) -> Set<ItemID> { Set(items.map(\.id)) }

/// Whether reading `read` is told of the next change, which the test then makes.
@MainActor
private func observes(_ read: () -> Void) -> LiveMarfa.Flag {
    let flag = LiveMarfa.Flag()
    withObservationTracking(read) { flag.set() }
    return flag
}

@MainActor
@Suite(.hangLimit) struct MarfaLibraryReadingTests {
    typealias F = LibraryFixture

    @Test func isLoadedOnlyOnceTheCopyAndItsTextAreRead() async throws {
        let source = FakeItemSource()
        source.setBody("Alpha body", of: F.p1)
        let library = MarfaLibrary(source: source, notices: Notices())
        #expect(!library.isLoaded)
        #expect(!library.isGone(F.p1))
        source.send(.loaded(F.snapshot))
        #expect(await eventually { library.isLoaded })
        #expect(library.body(of: F.p1)?.text == "Alpha body")
        #expect(library.body(of: F.en1) == nil)
        #expect(library.catalogue == F.catalogue)
    }

    @Test func changesFromTheSourceReplaceWhatWasHeld() async throws {
        let (library, source) = try await loaded()
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Renamed"
        renamed.tier = .library
        renamed.modified = Date(timeIntervalSince1970: 2_000_000)
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.n2)?.title == "Renamed" })
        #expect(library.items(in: .feed).isEmpty)

        let added = F.item(ItemID("new"), F.task, "New task", age: 0, edges: [F.child("c9", ItemID("new"), of: F.p2)])
        source.setBody("Fresh", of: added.id)
        source.send(.upserted([added]))
        #expect(await eventually { library.item(added.id) != nil })
        #expect(library.body(of: added.id)?.text == "Fresh")
        #expect(library.count(in: .type(TypeID("aic.ticket.task"))) == 2)

        source.send(.removed([F.n1]))
        #expect(await eventually { library.isGone(F.n1) })
        #expect(library.item(F.n1) == nil)
        #expect(!ids(library.favoriteItems(in: .all, archived: .hidden)).contains(F.n1))
        #expect(library.isGone(nil))
    }

    @Test func aMovedVersionShowsItsNewTextWithIt() async throws {
        let (library, source) = try await loaded()
        var edited = try #require(library.item(F.p1))
        edited.version = ItemVersion(2)
        source.setBody("Edited elsewhere", of: F.p1, version: 2)
        source.send(.upserted([edited]))
        #expect(await eventually { library.item(F.p1)?.version == ItemVersion(2) })
        #expect(library.body(of: F.p1) == ItemBody(id: F.p1, text: "Edited elsewhere", version: ItemVersion(2)))

        source.setBody("Changed in place", of: F.p1, version: 2)
        source.sendBody(of: F.p1)
        #expect(await eventually { library.body(of: F.p1)?.text == "Changed in place" })
    }

    /// Every edge field the type may hold is listed, the filled ones first, and only a link the text holds, a folder
    /// and what the item allows refuse a change; an inverse end is written like any other.
    @Test func relationFieldsListEveryFieldAndSayWhichTakeAChange() async throws {
        let (library, _) = try await loaded()
        let bug = library.relationFields(of: F.t1)
        #expect(bug.prefix(2).map(\.field) == ["child-of", "inverse:references"])
        #expect(bug.dropFirst(2).allSatisfy(\.targets.isEmpty))
        let field = Dictionary(uniqueKeysWithValues: bug.map { ($0.field, $0) })
        #expect(field["child-of"]?.label == "Parent")
        #expect(field["child-of"]?.cardinality == .one)
        #expect(field["child-of"]?.editability == .editable)
        #expect(field["inverse:parent-of"]?.editability == .editable)
        #expect(field["inverse:supersedes"]?.allowedTypes.contains(F.bug) == true)
        #expect(field["inverse:references"]?.targets.map(\.itemID) == [F.n1])
        #expect(field["inverse:references"]?.editability == .readOnly(String(localized: "A link is changed in the text that holds it.")))
        #expect(field["in-folder"]?.editability == .readOnly(String(localized: "Marfa keeps this link itself.")))
        // An item in the bin takes no change of links.
        let binned = library.relationFields(of: F.n3)
        #expect(!binned.isEmpty)
        #expect(binned.allSatisfy { $0.editability != .editable })
    }

    @Test func relationshipsReadBothWaysUnderTheirNames() async throws {
        let (library, _) = try await loaded()
        let task = library.relationships(for: F.e1)
        let parent = try #require(task.first { $0.field == "child-of" })
        #expect(parent.label == "Parent")
        #expect(parent.targets.map(\.itemID) == [F.p1])
        #expect(parent.targets.first?.title == "Alpha")
        #expect(!parent.allowsMultiple)
        #expect(parent.isEditable)
        #expect(task.first { $0.field == "inverse:parent-of" }?.targets.map(\.itemID) == [F.t1])
        #expect(task.first { $0.field == "inverse:parent-of" }?.label == "Children")
        // A ticket can supersede; a field the item's type cannot hold, or one only the server's folders end, is not offered.
        #expect(task.contains { $0.field == "supersedes" })
        #expect(!task.contains { $0.field == "in-folder" || $0.field == "references" })

        let project = library.relationships(for: F.p1)
        #expect(project.first { $0.field == "inverse:about" }?.targets.map(\.itemID) == [F.n1])
        #expect(project.first { $0.field == "inverse:about" }?.label == "Subject of")
        #expect(project.first { $0.field == "child-of" }?.targets.isEmpty == true)

        let note = library.relationships(for: F.n1)
        #expect(note.first { $0.field == "about" }?.label == "About")
        #expect(note.first { $0.field == "about" }?.allowsMultiple == true)
        #expect(!note.contains { $0.field == "supersedes" })
        #expect(library.bodyMentions(for: F.n1).map(\.itemID) == [F.t1])
    }

    @Test func candidatesFollowTheCatalogueAndLeaveCyclesToTheCoresCheck() async throws {
        let (library, _) = try await loaded()
        // Not itself or anything in the bin. The task below it is offered: whether a link closes a cycle is the core's
        // to say (`relationshipVerdict`), not this list's.
        #expect(Set(ids(library.relationshipCandidates(for: F.e1, field: "child-of"))) == [F.p1, F.n1, F.n2, F.en1, F.f1, F.p2, F.t1])
        #expect(Set(ids(library.relationshipCandidates(for: F.t1, field: "inverse:parent-of"))) == [F.n1, F.n2, F.en1, F.f1, F.p2, F.p1, F.e1])
        #expect(ids(library.relationshipCandidates(for: F.e1, field: "supersedes")) == [F.t1])
        #expect(library.relationshipCandidates(for: F.n1, field: "supersedes").isEmpty)
        #expect(library.creationParentCandidates(typeID: "aic.ticket.task").count == 8)
        #expect(library.relationshipCandidates(for: F.e1, field: "child-of").map(\.title) ==
            ["Ada", "Alpha", "Beta", "Bug one", "Feed note", "Photo", "Plain note"])
    }

    @Test func aRoleAllowsTheTypesThatPlayIt() async throws {
        let album = F.item(ItemID("al1"), F.album, "Holiday", age: 0)
        let (library, _) = try await loaded(F.items + [album])
        #expect(ids(library.relationshipCandidates(for: F.n1, field: "in-collection")) == [album.id])
        #expect(library.relationships(for: F.n1).contains { $0.field == "in-collection" })
        #expect(await library.changeLinks(F.n1, field: "in-collection", adding: [album.id], removing: [], undoManager: nil) == .taken)
    }
}

@MainActor
@Suite(.hangLimit) struct MarfaLibraryWritingTests {
    typealias F = LibraryFixture

    @Test func creatingMintsTheIdAndPutsTheItemUnderItsParent() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        let id = try #require(library.createItem(
            typeID: "aic.ticket.task", title: "  New task ", body: "Text", parentID: F.p1, in: .library, undoManager: undo))
        #expect(id.rawValue == id.rawValue.lowercased())
        #expect(id.rawValue.dropFirst(14).first == "7")
        #expect(source.writes == [.create(id: id, ItemDraft(type: F.task, title: "New task", body: "Text", parent: F.p1))])

        // The Inbox is the feed tier, and a blank body is no text.
        let inbox = try #require(library.createItem(
            typeID: "core.note", title: "Captured", body: "\n", parentID: nil, in: .feed, undoManager: nil))
        #expect(source.writes.last == .create(id: inbox, ItemDraft(type: F.note, title: "Captured", tier: .feed)))

        // Undoing a create puts the item in the bin; redoing it brings it back.
        source.send(.upserted([F.item(id, F.task, "New task", age: 0, edges: [F.child("c8", id, of: F.p1)])]))
        #expect(await eventually { library.item(id) != nil })
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.transition(id, .trashed, from: .active)])
        // The engine queues the move, which its Undo or Redo waits for.
        source.send(.taken(try #require(source.submitted.last?.id)))
        try #require(await eventually { library.stateJudging.isEmpty })
        undo.redo()
        #expect(source.writes == [.transition(id, .trashed, from: .active), .restore(id)])
    }

    @Test func aCreateTheCatalogueRefusesIsToldAndNotSent() async throws {
        let (library, source) = try await loaded()
        #expect(library.createItem(typeID: "no.such", title: "X", body: "", parentID: nil, in: .library, undoManager: nil) == nil)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Create Item"))
        library.notices.answerAll()
        #expect(library.createItem(typeID: "core.note", title: " ", body: "", parentID: nil, in: .library, undoManager: nil) == nil)
        #expect(library.notices.waiting.last != nil)
        #expect(source.writes.isEmpty)
    }

    @Test func textIsEditedFromTheVersionReadAndHeldUntilAnswered() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Note body")
        #expect(source.writes.isEmpty)
        library.updateBody(of: F.n1, to: "Typed")
        library.sendWaitingText()
        #expect(source.writes == [.editBody(F.n1, "Typed", base: ItemVersion(1), merge: .asRead)])
        #expect(library.body(of: F.n1)?.text == "Typed")
        #expect(library.hasUnreadSave(F.n1))
        source.send(.taken(try #require(source.submitted.first?.id)))
        #expect(await eventually { !library.hasUnreadSave(F.n1) }, "the copy has read the save back")

        // A read that raced the write gives older text, which the library does not take.
        source.setBody("Note bod", of: F.n1)
        source.sendBody(of: F.n1)
        source.send(.upserted([F.item(F.n1, F.note, "Plain note", age: 4, tags: [ItemTag.favorite])]))
        #expect(await eventually { library.item(F.n1)?.edgesOut.isEmpty == true })
        #expect(library.body(of: F.n1)?.text == "Typed")

        // Once answered, what the copy holds stands, merged or not, told in the change after the answer.
        source.setBody("Typed, merged", of: F.n1, version: 2)
        source.send(.answered(try #require(source.submitted.first?.id), .accepted))
        source.sendBody(of: F.n1)
        #expect(await eventually { library.body(of: F.n1)?.text == "Typed, merged" })
        #expect(library.notices.waiting.last == nil)

        // The next edit goes from the version of the text now held.
        library.updateBody(of: F.n1, to: "Again")
        library.sendWaitingText()
        #expect(source.writes.last == .editBody(F.n1, "Again", base: ItemVersion(2), merge: .asRead))

        // An item in the bin, or a file, takes no text.
        library.updateBody(of: F.n3, to: "No")
        library.updateBody(of: F.f1, to: "No")
        library.sendWaitingText()
        #expect(source.writes.count == 2)
    }

    /// The copy took the person's text, so text told before it was taken is older than what it holds: where the read
    /// after the write fails, the answer leaves the person's text on the page until a read tells the copy's.
    @Test func aSaveWhoseReadBackFailedKeepsThePersonsTextOnceAnswered() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Typed")
        library.sendWaitingText()
        let write = try #require(source.submitted.first?.id)
        source.send(.unavailable(SourceFailure(kind: .failed, message: "The copy could not be read.")))
        source.send(.taken(write))
        source.send(.answered(write, .accepted))
        source.send(.upserted([F.item(F.n2, F.note, "Answered", age: 5, tier: .feed)]))
        #expect(await eventually { library.item(F.n2)?.title == "Answered" })
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Typed", version: ItemVersion(1)))

        // The next save is typed on the person's own text, so it follows the write the copy took.
        library.updateBody(of: F.n1, to: "Typed again")
        library.sendWaitingText()
        #expect(source.writes.last == .editBody(F.n1, "Typed again", base: ItemVersion(1), merge: .following))

        // A read that lands tells the copy's text, which stands once the save is answered.
        source.setBody("Typed again", of: F.n1, version: 3)
        source.send(.taken(try #require(source.submitted.last?.id)))
        source.sendBody(of: F.n1)
        source.send(.answered(try #require(source.submitted.last?.id), .accepted))
        #expect(await eventually { library.body(of: F.n1)?.version == ItemVersion(3) })
        library.updateBody(of: F.n1, to: "Third")
        library.sendWaitingText()
        #expect(source.writes.last == .editBody(F.n1, "Third", base: ItemVersion(3), merge: .asRead))
    }

    /// The engine tells what it read back of a save before it tells the copy took it, and the copy keeps the version
    /// it held until the answer, so the page keeps the person's text on that version.
    @Test func aSavesReadBackToldBeforeItIsTakenKeepsThePersonsText() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Typed")
        library.sendWaitingText()
        let write = try #require(source.submitted.first?.id)
        // A read that raced the write, then the read of the write itself.
        source.sendBody(of: F.n1)
        source.setBody("Typed", of: F.n1, version: 1)
        source.sendBody(of: F.n1)
        source.send(.taken(write))
        #expect(await eventually { !library.hasUnreadSave(F.n1) }, "the copy has read the save back")
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Typed", version: ItemVersion(1)))
        source.send(.answered(write, .accepted))
        source.send(.upserted([F.item(F.n2, F.note, "Answered", age: 5, tier: .feed)]))
        #expect(await eventually { library.item(F.n2)?.title == "Answered" })
        #expect(library.body(of: F.n1) == ItemBody(id: F.n1, text: "Typed", version: ItemVersion(1)))

        // The next save is typed on the person's own text, so it follows the write the copy took.
        library.updateBody(of: F.n1, to: "Typed again")
        library.sendWaitingText()
        #expect(source.writes.last == .editBody(F.n1, "Typed again", base: ItemVersion(1), merge: .following))
    }

    /// A save refused before it was queued left the copy as it was, so the page goes back to the copy's text.
    @Test func aSaveRefusedBeforeItWasQueuedShowsTheCopysText() async throws {
        let (library, source) = try await loaded()
        let before = try #require(library.body(of: F.n1))
        library.updateBody(of: F.n1, to: "Typed while the copy was brought up to date")
        library.sendWaitingText()
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "copy_expired", message: "Try again in a moment.", notQueued: true))))
        #expect(await eventually { library.body(of: F.n1) == before })
    }

    @Test func aTitleIsTheTypesTitleFieldAndUndoesAtTheCurrentVersion() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.setItemProperty(F.en1, key: "title", value: .string(" Ada L. "), undoManager: undo))
        #expect(source.writes == [.editProperties(F.en1, ["name": .string("Ada L.")], base: ItemVersion(1))])

        var moved = try #require(library.item(F.en1))
        moved.version = ItemVersion(7)
        source.send(.upserted([moved]))
        #expect(await eventually { library.item(F.en1)?.version == ItemVersion(7) })
        undo.undo()
        #expect(source.writes.last == .editProperties(F.en1, ["name": .string("Ada")], base: ItemVersion(7)))

        // A title that is the first line of the text is edited in the text.
        #expect(!library.setItemProperty(F.f1, key: "title", value: .string("X"), undoManager: nil))
        #expect(!library.setItemProperty(F.en1, key: "title", value: .string(" "), undoManager: nil))
    }

    @Test func aPropertyIsCheckedAgainstItsFieldAndUndone() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(!library.setItemProperty(F.t1, key: "status", value: .string("maybe"), undoManager: undo))
        #expect(library.notices.waiting.last?.title == String(localized: "Invalid Property"))
        #expect(!library.setItemProperty(F.t1, key: "nope", value: .string("x"), undoManager: undo))
        #expect(!library.setItemProperty(F.t1, key: "body", value: .string("x"), undoManager: undo))
        #expect(!library.setItemProperty(F.n3, key: "title", value: .string("x"), undoManager: undo))
        #expect(source.writes.isEmpty)

        // Two steps, each undone on its own.
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.setItemProperty(F.t1, key: "status", value: .string("done"), undoManager: undo))
        undo.endUndoGrouping()
        undo.beginUndoGrouping()
        #expect(library.setItemProperty(F.t1, key: "due", value: .string("2026-10-06"), undoManager: undo))
        undo.endUndoGrouping()
        undo.undo()
        #expect(source.writes.last == .editProperties(F.t1, ["due": nil], base: ItemVersion(1)))
        undo.undo()
        #expect(source.writes.last == .editProperties(F.t1, ["status": nil], base: ItemVersion(1)))
        undo.redo()
        #expect(source.writes.last == .editProperties(F.t1, ["status": .string("done")], base: ItemVersion(1)))
    }

    @Test func favoritesAreTheFavoriteTagAndUndo() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.setFavorite([F.n1, F.n2, F.n3], true, undoManager: undo)
        #expect(source.writes == [.tag(F.n2, ItemTag.favorite, on: true)])
        undo.undo()
        #expect(source.writes.last == .tag(F.n2, ItemTag.favorite, on: false))
        undo.redo()
        #expect(source.writes.last == .tag(F.n2, ItemTag.favorite, on: true))
        source.clearWrites()
        library.setFavorite([F.n2], false, undoManager: nil)
        #expect(source.writes.isEmpty)
    }

    @Test func deletingMovesToTheBinAndUndoes() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1, F.n3], undoManager: undo)
        #expect(source.writes == [.transition(F.n1, .trashed, from: .active)])
        #expect(undo.undoActionName == String(localized: "Delete Item"))
        // The engine queues the move, which its Undo or Redo waits for.
        source.send(.taken(try #require(source.submitted.last?.id)))
        try #require(await eventually { library.stateJudging.isEmpty })
        undo.undo()
        #expect(source.writes.last == .restore(F.n1))
        source.send(.taken(try #require(source.submitted.last?.id)))
        source.clearWrites()
        library.recover([F.n3, F.n1], undoManager: undo)
        #expect(source.writes == [.restore(F.n3)])
        // The engine queues the move, which its Undo or Redo waits for.
        source.send(.taken(try #require(source.submitted.last?.id)))
        try #require(await eventually { library.stateJudging.isEmpty })
        undo.undo()
        #expect(source.writes.last == .transition(F.n3, .trashed, from: .active))
    }

    @Test func anItemTheServersBinHoldsIsListedAndRecoveredLikeAnyOther() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        // The engine queues the move, which its Undo or Redo waits for.
        source.send(.taken(try #require(source.submitted.last?.id)))
        try #require(await eventually { library.stateJudging.isEmpty })
        // The server took the delete and the copy let the row go; the source still lists it, as the bin holds it.
        var binned = try #require(library.item(F.n1))
        binned.state = .trashed
        source.send(.upserted([binned]))
        #expect(await eventually { library.deletedItems.contains { $0.id == F.n1 } })
        #expect(library.deletedCount == 2)
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.restore(F.n1)])
        #expect(library.notices.waiting.last == nil)

        // A restore the server refuses is told in the server's own words.
        library.recover([F.n3], undoManager: nil)
        let restore = try #require(source.submitted.last?.id)
        source.send(.answered(restore, .refused(SyncProblem(code: "item_not_found", message: "The server doesn’t hold this item."))))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Recover"))
        #expect(library.notices.waiting.last?.message == "The server doesn’t hold this item.")
    }

    @Test func anItemTheCopyNoLongerHoldsIsNotRecovered() async throws {
        let (library, source) = try await loaded()
        source.send(.removed([F.n3]))
        #expect(await eventually { library.item(F.n3) == nil })
        source.clearWrites()
        library.recover([F.n3], undoManager: nil)
        #expect(source.writes.isEmpty)
    }

    @Test func deletingForGoodSendsEachItemInTheBinAtTheVersionShown() async throws {
        let (library, source) = try await loaded()
        source.state.set(.online)
        #expect(await eventually { library.reachesServer })
        var binned = try #require(library.item(F.n3))
        binned.version = ItemVersion(9)
        source.send(.upserted([binned]))
        #expect(await eventually { library.item(F.n3)?.version == ItemVersion(9) })
        library.itemsToPurge = [F.n3, F.n1]
        library.deletePermanentlyOnConfirm([F.n3, F.n1])
        // An item not in the bin is only moved there, never destroyed.
        #expect(source.writes == [.purge(F.n3, version: ItemVersion(9))])
        #expect(library.itemsToPurge.isEmpty)

        let purge = try #require(source.submitted.last?.id)
        source.send(.answered(purge, .refused(SyncProblem(code: "version_conflict", message: "The item changed after you saw it."))))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Delete Immediately"))
        #expect(library.notices.waiting.last?.message == "The item changed after you saw it.")
    }

    @Test func deletingForGoodWaitsForTheServer() async throws {
        let (library, source) = try await loaded()
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        #expect(!library.reachesServer)
        library.deletePermanentlyOnConfirm([F.n3])
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Delete Immediately"))
        library.notices.answerAll()
        library.deletePermanently([F.n3])
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Delete Immediately"))
    }

    @Test func aLinkIsAddedRemovedAndReplacedByAMove() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        /// The copy takes the last write, as the engine does once it has judged and queued it.
        func take() async throws {
            source.send(.taken(try #require(source.submitted.last?.id)))
            try #require(await eventually { library.linkSteps.values.allSatisfy(\.judging.isEmpty) })
        }
        // A new parent replaces the one link a child holds: one move of the edge's source, which keeps its id.
        undo.beginUndoGrouping()
        #expect(await library.changeLinks(F.t1, field: "child-of", adding: [F.p1], removing: [F.e1], undoManager: undo) == .taken)
        // The core is asked first, so the write follows; it joins the open group.
        #expect(await eventually { source.writes == [.moveEdge(EdgeID("c2"), end: .from, to: F.p1, from: F.e1)] }, "sent \(source.writes)")
        try await take()
        undo.endUndoGrouping()
        #expect(library.notices.waiting.last == nil)
        // The undo moves it back, to the parent it had.
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.moveEdge(EdgeID("c2"), end: .from, to: F.e1, from: F.p1)])
        try await take()
        undo.redo()
        #expect(source.writes.last == .moveEdge(EdgeID("c2"), end: .from, to: F.p1, from: F.e1))
        try await take()

        // A child chosen under a project from the project's side is taken from the parent it has, in one move.
        source.clearWrites()
        undo.beginUndoGrouping()
        #expect(await library.changeLinks(F.p2, field: "inverse:parent-of", adding: [F.e1], removing: [], undoManager: undo) == .taken)
        #expect(await eventually { source.writes == [.moveEdge(EdgeID("c1"), end: .from, to: F.p2, from: F.p1)] }, "sent \(source.writes)")
        try await take()
        undo.endUndoGrouping()
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.moveEdge(EdgeID("c1"), end: .from, to: F.p1, from: F.p2)])
        try await take()
        #expect(library.notices.waiting.last == nil)
        source.clearWrites()

        // Removing the parent, then choosing one for an end that holds none, are each one write.
        undo.beginUndoGrouping()
        #expect(await library.changeLinks(F.t1, field: "child-of", adding: [], removing: [F.e1], undoManager: undo) == .taken)
        undo.endUndoGrouping()
        #expect(source.writes == [.unlink(EdgeID("c2"))])
        try await take()
        source.send(.upserted([F.item(F.t1, F.bug, "Bug one", age: 3, tags: [ItemTag.favorite])]))
        #expect(await eventually { library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.isEmpty == true })
        source.clearWrites()
        undo.beginUndoGrouping()
        #expect(await library.changeLinks(F.t1, field: "child-of", adding: [F.p1], removing: [], undoManager: undo) == .taken)
        let toProject = EdgeDraft(type: "parent-of", from: F.p1, to: F.t1)
        #expect(await eventually { source.writes == [.link(toProject)] }, "sent \(source.writes)")
        let minted = try #require(source.lastMintedEdge)
        try await take()
        undo.endUndoGrouping()

        // The undo takes away the edge this Mac made, by the id it gave it, and the next puts the old parent back.
        source.send(.upserted([F.item(F.t1, F.bug, "Bug one", age: 3, tags: [ItemTag.favorite], edges: [F.child(minted.rawValue, F.t1, of: F.p1)])]))
        #expect(await eventually { library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.first?.itemID == F.p1 })
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.unlink(minted)])
        try await take()
        undo.undo()
        #expect(source.writes.last == .link(EdgeDraft(type: "parent-of", from: F.e1, to: F.t1)))

        // A field that holds many adds and removes in one change.
        source.clearWrites()
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [F.p1], undoManager: nil) == .taken)
        #expect(await eventually { source.writes == [.link(EdgeDraft(type: "about", from: F.n1, to: F.p2))] })
        // The old link goes once the source has taken the new one.
        source.send(.answered(try #require(source.submitted.last?.id), .accepted))
        #expect(await eventually { source.writes.last == .unlink(EdgeID("a1")) })
    }

    /// The undo of a change reverses only what that change wrote: it removes the two links it added, by the ids it gave
    /// them, puts back the one it removed, and leaves a link someone else added since.
    @Test func undoReversesOnlyWhatTheChangeWrote() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.p2, F.e1], removing: [F.p1], undoManager: undo) == .taken)
        try #require(await eventually { source.submitted.count == 2 })
        let added = source.submitted.compactMap { sent -> EdgeID? in
            if case .link(let draft) = sent.write { return draft.id }
            return nil
        }
        #expect(added.count == 2)
        for write in source.submitted {
            source.send(.taken(write.id))
            source.send(.answered(write.id, .accepted))
        }
        // The old link goes once the new ones are answered.
        try #require(await eventually { source.writes.last == .unlink(EdgeID("a1")) }, "sent \(source.writes)")
        let removal = try #require(source.submitted.last?.id)
        source.send(.taken(removal))
        source.send(.answered(removal, .accepted))
        try #require(await eventually { library.linkSteps.isEmpty })
        undo.endUndoGrouping()
        // Someone else links the note to the second bug meanwhile.
        source.send(.upserted([F.item(F.n1, F.note, "Plain note", age: 4, tags: [ItemTag.favorite], edges: [
            Edge(id: added[0], type: "about", from: F.n1, to: .item(F.p2), origin: .property("about")),
            Edge(id: added[1], type: "about", from: F.n1, to: .item(F.e1), origin: .property("about")),
            Edge(id: EdgeID("theirs"), type: "about", from: F.n1, to: .item(F.t1), origin: .property("about")),
            Edge(id: EdgeID("r1"), type: "references", from: F.n1, to: .item(F.t1), origin: .body),
        ])]))
        try #require(await eventually { library.relationships(for: F.n1).first { $0.field == "about" }?.targets.count == 3 })
        source.clearWrites()
        undo.undo()
        // The link removed comes back first, and the two added go once it is answered, as in any swap.
        #expect(source.writes == [.link(EdgeDraft(type: "about", from: F.n1, to: F.p1))], "sent \(source.writes)")
        let back = try #require(source.submitted.last?.id)
        source.send(.taken(back))
        source.send(.answered(back, .accepted))
        try #require(await eventually { source.writes.count == 3 }, "sent \(source.writes)")
        #expect(Set(source.writes.dropFirst()) == [.unlink(added[0]), .unlink(added[1])])
    }

    @Test func aLinkAThirdItemHoldsIsNeverTakenFromIt() async throws {
        let bug2 = F.item(ItemID("t2"), F.bug, "Bug two", age: 0, edges: [
            Edge(id: EdgeID("s1"), type: "supersedes", from: ItemID("t2"), to: .item(F.t1), origin: .property("supersedes")),
        ])
        let (library, source) = try await loaded(F.items + [bug2])
        #expect(library.relationships(for: F.t1).first { $0.field == "inverse:supersedes" }?.allowsMultiple == false)
        // The first bug is already superseded by the second. That link is the second bug's own, so the task does
        // not take it: the person is told which item holds it, and nothing is sent.
        library.notices.answerAll()
        #expect(await library.changeLinks(F.e1, field: "supersedes", adding: [F.t1], removing: [], undoManager: nil) != .taken)
        #expect(library.notices.waiting.last?.message
            == String(localized: "“\("Bug two")” already holds this link to “\("Bug one")”. Remove it there first."))
        #expect(source.writes.isEmpty)
        #expect(library.relationships(for: F.t1).first { $0.field == "inverse:supersedes" }?.targets.map(\.itemID) == [bug2.id])
        // Chosen from the other end, the second bug's own link changes from the first bug to the task: the edge's
        // target moves.
        library.notices.answerAll()
        #expect(await library.changeLinks(F.e1, field: "inverse:supersedes", adding: [bug2.id], removing: [], undoManager: nil) == .taken)
        #expect(await eventually { source.writes == [.moveEdge(EdgeID("s1"), end: .to, to: F.e1, from: F.t1)] }, "sent \(source.writes)")
        #expect(library.notices.waiting.last == nil)
    }

    /// A replacement of the one link an end holds is one move, asked of the core as a move, since a new link would be refused
    /// for the end that is full; the third item's own link is still not taken.
    @Test func aReplacementOfAnItemsOwnLinkIsAskedAsAMove() async throws {
        func bug(_ id: String, supersedes target: ItemID? = nil, edge: String = "") -> MarfaMac.Item {
            F.item(ItemID(id), F.bug, "Bug \(id)", age: 0, edges: target.map {
                [Edge(id: EdgeID(edge), type: "supersedes", from: ItemID(id), to: .item($0), origin: .property("supersedes"))]
            } ?? [])
        }
        let (library, source) = try await loaded(F.items + [bug("a"), bug("b"), bug("c", supersedes: ItemID("a"), edge: "s1"),
            bug("d", supersedes: ItemID("b"), edge: "s2")])
        // From `c`'s own side, `b` is held by `d` as its own link, which is never taken from it.
        #expect(await library.changeLinks(ItemID("c"), field: "supersedes", adding: [ItemID("b")], removing: [ItemID("a")], undoManager: nil) != .taken)
        #expect(library.notices.waiting.last?.message
            == String(localized: "“\("Bug d")” already holds this link to “\("Bug b")”. Remove it there first."))
        #expect(source.writes.isEmpty)
        // Replacing its own link for an item that holds none is one move of the end that goes.
        library.notices.answerAll()
        #expect(await library.changeLinks(ItemID("c"), field: "supersedes", adding: [F.t1], removing: [ItemID("a")], undoManager: nil) == .taken)
        #expect(await eventually { source.writes == [.moveEdge(EdgeID("s1"), end: .to, to: F.t1, from: ItemID("a"))] }, "sent \(source.writes)")
        #expect(source.asked.withLock { $0 } == [.moved(EdgeID("s1"), .to, F.t1)])
    }

    /// The core is asked of a replacement as a move and of every other link as a new one, whichever the picker asks.
    @Test func theCoreIsAskedOfAMoveForAReplacementAndOfANewLinkForAnAdd() async throws {
        let (library, source) = try await loaded()
        #expect(await library.relationshipVerdict(for: F.t1, field: "child-of", to: F.p2) == .taken)
        #expect(await library.relationshipVerdict(for: F.n1, field: "about", to: F.p2) == .taken)
        #expect(source.asked.withLock { $0 }
            == [.moved(EdgeID("c2"), .from, F.p2), .added(EdgeDraft(type: "about", from: F.n1, to: F.p2))])
        // The core refuses the move: the row is refused with its words, and a change is told the same and sends nothing.
        source.moveRefusals.withLock { $0[EdgeID("c2")] = "That would close a cycle." }
        #expect(await library.relationshipVerdict(for: F.t1, field: "child-of", to: F.p2) == .refused("That would close a cycle."))
        #expect(await library.changeLinks(F.t1, field: "child-of", adding: [F.p2], removing: [F.e1], undoManager: nil) != .taken)
        #expect(library.notices.waiting.last?.message == "That would close a cycle.")
        #expect(source.writes.isEmpty)
    }

    /// A refusal the copy could not foresee, such as a cycle through rows outside it, is the server's: it is told in the
    /// server's words, and the link stays where it was.
    @Test func aMoveTheServerRefusesIsToldAndLeavesTheOldLink() async throws {
        let (library, source) = try await loaded()
        await library.changeLinks(F.t1, field: "child-of", adding: [F.p1], removing: [F.e1], undoManager: nil)
        try #require(await eventually { source.submitted.last != nil })
        let move = try #require(source.submitted.last?.id)
        source.send(.answered(move, .refused(SyncProblem(code: "edge_cycle", message: "That would close a cycle."))))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Change This Relationship"))
        #expect(library.notices.waiting.last?.message == "That would close a cycle.")
        #expect(library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.map(\.itemID) == [F.e1])
        #expect(source.writes.count == 1)
    }

    /// The item's `about` links as the copy shows them after the source has taken the writes so far.
    private static func note(about targets: [ItemID]) -> MarfaMac.Item {
        F.item(F.n1, F.note, "Plain note", age: 4, tags: [ItemTag.favorite], edges: targets.enumerated().map { position, target in
            Edge(id: EdgeID("a\(position + 1)"), type: "about", from: F.n1, to: .item(target), origin: .property("about"))
        })
    }

    @Test func twoChangesMadeBeforeTheFirstIsCheckedDoNotAddALinkTwice() async throws {
        let (library, source) = try await loaded()
        source.holdingChecks.withLock { $0 = true }
        // The note is about the first project. One change adds the second; the next, from a picker opened before
        // either, also picks the second and adds a task.
        let first = Task { await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) }
        let second = Task { await library.changeLinks(F.n1, field: "about", adding: [F.p2, F.e1], removing: [], undoManager: nil) }
        try #require(await eventually { library.relationshipChangesInFlight == 2 })
        #expect(source.writes.isEmpty, "nothing is written before the core has answered")
        source.holdingChecks.withLock { $0 = false }
        try #require(await eventually { source.writes == [.link(EdgeDraft(type: "about", from: F.n1, to: F.p2))] })
        // The copy shows the first change and has taken it; only then is the second worked out.
        let link = try #require(source.submitted.last?.id)
        source.send(.upserted([Self.note(about: [F.p1, F.p2])]))
        source.send(.taken(link))
        #expect(await first.value == .taken)
        #expect(await second.value == .taken)
        #expect(source.writes == [
            .link(EdgeDraft(type: "about", from: F.n1, to: F.p2)),
            .link(EdgeDraft(type: "about", from: F.n1, to: F.e1)),
        ], "sent \(source.writes)")
    }

    /// The note about the three, each link keeping the id it was made with.
    private static func note(about links: [(id: String, target: ItemID)]) -> MarfaMac.Item {
        F.item(F.n1, F.note, "Plain note", age: 4, tags: [ItemTag.favorite], edges: links.map {
            Edge(id: EdgeID($0.id), type: "about", from: F.n1, to: .item($0.target), origin: .property("about"))
        })
    }

    @Test func removingTwoLinksQuicklyDoesNotPutTheFirstBack() async throws {
        let all = [(id: "a1", target: F.p1), (id: "a2", target: F.p2), (id: "a3", target: F.e1)]
        let (library, source) = try await loaded(F.items.map { $0.id == F.n1 ? Self.note(about: all) : $0 })
        // The person removes the first project; before the screen shows it they remove the second.
        let first = Task { await library.changeLinks(F.n1, field: "about", adding: [], removing: [F.p1], undoManager: nil) }
        try #require(await eventually { source.writes == [.unlink(EdgeID("a1"))] })
        let second = Task { await library.changeLinks(F.n1, field: "about", adding: [], removing: [F.p2], undoManager: nil) }
        let removal = try #require(source.submitted.last?.id)
        // The copy shows the first removal, and has taken it, before the second is worked out from it.
        source.send(.upserted([Self.note(about: Array(all.dropFirst()))]))
        source.send(.taken(removal))
        #expect(await first.value == .taken)
        #expect(await second.value == .taken)
        #expect(source.writes == [.unlink(EdgeID("a1")), .unlink(EdgeID("a2"))], "sent \(source.writes)")
    }

    @Test func aPickerOpenedBeforeTheLastSaveKeepsThatSave() async throws {
        let (library, source) = try await loaded()
        // The picker opened while the note was about the first project only, and the person saved another change
        // meanwhile, which added the second. Picking a task adds only the task.
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) == .taken)
        let added = try #require(source.submitted.last?.id)
        source.send(.upserted([Self.note(about: [F.p1, F.p2])]))
        source.send(.taken(added))
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.e1], removing: [], undoManager: nil) == .taken)
        #expect(source.writes == [
            .link(EdgeDraft(type: "about", from: F.n1, to: F.p2)),
            .link(EdgeDraft(type: "about", from: F.n1, to: F.e1)),
        ], "sent \(source.writes)")
    }

    @Test func aChangeWaitsForTheCopyToTakeTheWritesBeforeAndEndsOnARefusalOrAClosedSource() async throws {
        let (library, source) = try await loaded()
        // Not taken yet: the next change is not worked out.
        let first = Task { await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) }
        try #require(await eventually { source.writes.count == 1 })
        let second = Task { await library.changeLinks(F.n1, field: "about", adding: [F.e1], removing: [], undoManager: nil) }
        try #require(await eventually { library.relationshipChangesInFlight == 1 })
        // Gives the second change time to be written early, which it must not be.
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.writes.count == 1, "the second change was worked out before the copy took the first")
        // A write answered before the copy took it, as a refusal is, ends the wait.
        let link = try #require(source.submitted.last?.id)
        source.send(.answered(link, .refused(SyncProblem(code: "type_not_permitted", message: "Not permitted."))))
        #expect(await first.value == .taken)
        #expect(await second.value == .taken)
        #expect(source.writes.count == 2)
        source.send(.taken(try #require(source.submitted.last?.id)))
        // A source that closes ends every wait: the stream finishes, though the write was never taken.
        let third = Task { await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) }
        try #require(await eventually { source.writes.count == 3 })
        let fourth = Task { await library.changeLinks(F.n1, field: "about", adding: [F.e1], removing: [], undoManager: nil) }
        await source.close()
        #expect(await third.value == .taken)
        _ = await fourth.value
    }

    @Test func anUnlinkHeldBackForTheNewLinksIsNotWaitedFor() async throws {
        let (library, source) = try await loaded()
        // One project is chosen in place of the other: the unlink goes only after the server answers the link.
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [F.p1], undoManager: nil) == .taken)
        let link = try #require(source.submitted.last?.id)
        source.send(.taken(link))
        // The next change goes ahead on the link being taken, with the unlink still not sent.
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.e1], removing: [], undoManager: nil) == .taken)
        #expect(source.writes.count == 2, "sent \(source.writes)")
    }

    @Test func aRefusalByTheCoreIsAnsweredToTheCallerAndNothingIsWritten() async throws {
        let (library, source) = try await loaded()
        source.refusals.withLock { $0[EdgeDraft(type: "about", from: F.n1, to: F.p2)] = "That would close a cycle." }
        #expect(await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) != .taken)
        #expect(library.notices.waiting.last?.message == "That would close a cycle.")
        #expect(source.writes.isEmpty)
    }

    @Test func undoingAParentMoveGoesBackToTheParentItLeft() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        source.holdingChecks.withLock { $0 = true }
        undo.beginUndoGrouping()
        // The bug is under the task. It is moved under the first project, and at once under the second.
        let first = Task { await library.changeLinks(F.t1, field: "child-of", adding: [F.p1], removing: [F.e1], undoManager: undo) }
        let second = Task { await library.changeLinks(F.t1, field: "child-of", adding: [F.p2], removing: [F.p1], undoManager: undo) }
        try #require(await eventually { library.relationshipChangesInFlight == 2 })
        source.holdingChecks.withLock { $0 = false }
        try #require(await eventually { source.writes == [.moveEdge(EdgeID("c2"), end: .from, to: F.p1, from: F.e1)] })
        let move = try #require(source.submitted.last?.id)
        source.send(.upserted([F.item(F.t1, F.bug, "Bug one", age: 3, tags: [ItemTag.favorite], edges: [F.child("c2", F.t1, of: F.p1)])]))
        source.send(.taken(move))
        #expect(await first.value == .taken)
        #expect(await second.value == .taken)
        undo.endUndoGrouping()
        #expect(source.writes.last == .moveEdge(EdgeID("c2"), end: .from, to: F.p2, from: F.p1), "sent \(source.writes)")
        source.send(.taken(try #require(source.submitted.last?.id)))
        try #require(await eventually { library.linkSteps.values.allSatisfy(\.judging.isEmpty) })
        source.clearWrites()
        undo.undo()
        // The second move is undone to the project the first put it under, then the first to the task it started under.
        #expect(source.writes == [
            .moveEdge(EdgeID("c2"), end: .from, to: F.p1, from: F.p2), .moveEdge(EdgeID("c2"), end: .from, to: F.e1, from: F.p1),
        ], "sent \(source.writes)")
    }

    @Test func leavingTheLibraryWaitsForAChangeStillBeingChecked() async throws {
        let (library, source) = try await loaded()
        source.holdingChecks.withLock { $0 = true }
        let change = Task { await library.changeLinks(F.n1, field: "about", adding: [F.p2], removing: [], undoManager: nil) }
        try #require(await eventually { library.relationshipChangesInFlight == 1 })
        let finished = LiveMarfa.Flag()
        let finishing = Task {
            await library.finish()
            finished.set()
        }
        // Gives the flush time to return early, which it must not.
        try await Task.sleep(for: .milliseconds(100))
        #expect(!finished.isSet, "the flush returned with the change not yet written")
        source.holdingChecks.withLock { $0 = false }
        await finishing.value
        #expect(source.writes == [.link(EdgeDraft(type: "about", from: F.n1, to: F.p2))], "sent \(source.writes)")
        #expect(await change.value)
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func aFieldOrItemThatCantChangeSendsNothing() async throws {
        let (library, source) = try await loaded()
        #expect(await library.changeLinks(F.n3, field: "about", adding: [F.p1], removing: [], undoManager: nil) != .taken)
        #expect(await library.changeLinks(F.n1, field: "nothing", adding: [F.p1], removing: [], undoManager: nil) != .taken)
        #expect(source.writes.isEmpty)
    }

    @Test func attachedFilesGoToTheSourceAndTheTextItGivesIsWhatThePageWrites() async throws {
        let (library, source) = try await loaded()
        let report = await library.attach([(name: "a.png", data: Data([1])), (name: "b.png", data: Data([2]))], to: F.n1)
        #expect(report.embeds.map(\.name) == ["a.png", "b.png"])
        #expect(report.embeds.map(\.link) == ["a.png", "b.png"])
        #expect(report.failed.isEmpty)
        #expect(source.attaching.attached.withLock { $0.map(\.item) } == [F.n1, F.n1])
        #expect(source.writes.isEmpty)
    }

    @Test func twoFilesWithOneNameEachKeepTheirBytes() async throws {
        let (library, source) = try await loaded()
        _ = await library.attach([(name: "Image.png", data: Data([1])), (name: "Image.png", data: Data([2]))], to: F.n1)
        #expect(source.attaching.attached.withLock { $0.map(\.data) } == [Data([1]), Data([2])])
    }

    @Test func aFileThatFailsLeavesTheOthersAttachedAndIsNamed() async throws {
        let (library, source) = try await loaded()
        source.attaching.failures.withLock { $0["b.png"] = SourceFailure(kind: .failed, message: "The server is out of space.") }
        let report = await library.attach(
            [(name: "a.png", data: Data([1])), (name: "b.png", data: Data([2])), (name: "c.png", data: Data([3]))], to: F.n1)
        #expect(report.embeds.map(\.name) == ["a.png", "c.png"])
        #expect(report.failed.map(\.name) == ["b.png"])
        #expect(report.failed.map(\.reason) == ["The server is out of space."])
    }

    @Test func filesGoToTheSourceFromWhereTheyAre() async throws {
        let (library, source) = try await loaded()
        let disk = TestFiles()
        let embed = try await library.attach(file: disk.url("plan.pdf", "pdf"), to: F.n1)
        #expect(embed == Embed(link: "plan.pdf", name: "plan.pdf"))
        #expect(source.attaching.attached.withLock { $0.map(\.file) } == ["plan.pdf"])

        let id = await library.addFile(
            disk.url("photo.png", "png"), title: "Holiday", parentID: F.p1, in: .feed)
        #expect(id != nil)
        let added = try #require(source.attaching.added.withLock { $0.first })
        #expect(added.file == "photo.png" && added.data == Data("png".utf8))
        #expect(added.title == "Holiday" && added.tier == .feed && added.parent == F.p1)

        source.attaching.failure.withLock { $0 = SourceFailure(kind: .failed, message: "No room.") }
        source.attaching.failures.withLock { $0["b.pdf"] = SourceFailure(kind: .failed, message: "No room.") }
        await #expect(throws: SourceFailure.self) { try await library.attach(file: disk.url("b.pdf"), to: F.n1) }
        #expect(await library.addFile(disk.url("c.png"), title: nil, parentID: nil, in: .library) == nil)
        #expect(library.notices.waiting.last?.message == "No room.")
    }

    /// The core chooses a file's type from the media type it is given, so the one given is the system's, which
    /// knows more kinds than the core's own table of extensions.
    @Test func aFileIsSentWithTheMediaTypeTheSystemGivesIt() throws {
        let disk = TestFiles()
        #expect(MarfaEngine.mimeType(of: disk.url("photo.png", "png")) == "image/png")
        #expect(MarfaEngine.mimeType(of: disk.url("scan.tiff", "tiff")) == "image/tiff")
        #expect(MarfaEngine.mimeType(of: disk.url("song.flac", "flac"))?.hasPrefix("audio/") == true)
        #expect(MarfaEngine.mimeType(of: disk.url("clip.mov", "mov")) == "video/quicktime")
        #expect(MarfaEngine.mimeType(of: disk.url("report.pdf", "pdf")) == "application/pdf")
    }

    @Test func aRefusalTheSourceAnswersReachesThePerson() async throws {
        let (library, source) = try await loaded()
        library.setFavorite([F.n2], true, undoManager: nil)
        let write = try #require(source.submitted.first?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "unsupported", message: "Favorites can’t be changed here."))))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Add to Favorites"))
        #expect(library.notices.waiting.last?.message == "Favorites can’t be changed here.")

        // A conflict is the item's own state to show, not an alert; an answer told twice is told once.
        library.notices.answerAll()
        source.send(.answered(write, .refused(SyncProblem(code: "again"))))
        library.setFavorite([F.n2], false, undoManager: nil)
        source.send(.answered(try #require(source.submitted.last?.id), .conflicted(sibling: F.n1, fields: ["tags"])))
        source.send(.unavailable(SourceFailure(kind: .failed, message: "The copy can’t be read.")))
        #expect(await eventually { library.notices.waiting.last != nil })
        #expect(library.notices.waiting.last?.message == "The copy can’t be read.")
    }

    /// Finishing waits until the source has queued every write, and not for the server, so quitting offline is
    /// not held up and quitting at once loses nothing.
    @Test func finishingWaitsUntilTheSourceHasQueuedEveryWriteButNotForTheServer() async throws {
        let (library, source) = try await loaded()
        source.queuing.withLock { $0 = true }
        let finished = Task { await library.finish() }
        // Time for finishing to return early, which it must not.
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.queues.withLock { $0 } == 0, "finishing returned before the source had queued its writes")
        source.queuing.withLock { $0 = false }
        await finished.value
        #expect(source.queues.withLock { $0 } == 1)
    }
}

@MainActor
@Suite(.hangLimit) struct MarfaLibrarySyncTests {
    typealias F = LibraryFixture

    @Test func purgeIsOfferedOnlyWhileTheServerCanBeReached() async throws {
        let (library, source) = try await loaded()
        #expect(!library.reachesServer)
        #expect(library.connection == .connecting)
        let watched = observes { _ = library.reachesServer }
        source.state.set(.online)
        #expect(await eventually { library.connection == .online })
        #expect(watched.isSet)
        #expect(library.reachesServer)
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        #expect(!library.reachesServer)
        source.state.set(.keyRefused)
        #expect(await eventually { library.connection == .keyRefused })
        source.state.set(.unavailable(message: "Stopped."))
        #expect(await eventually { library.connection == .unavailable(message: "Stopped.") })
    }

    /// A value panel writes through `setItemProperty`, which asks nothing of the connection: the copy queues the edit
    /// and the server is reached later.
    @Test func aValueChosenInAPanelWhileTheServerIsUnreachableStaysAndWaitsInTheQueue() async throws {
        let (library, source) = try await loaded()
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        let field = try #require(library.catalogue.itemTypes[F.task]?.fields.first { $0.key == "status" })
        let request = ValueEditRequest(
            kind: .choice(field), library: library, item: F.t1,
            write: { library.setItemProperty(F.t1, key: "status", value: $0, undoManager: nil) })
        let model = ValueEditModel(request)
        var closed = false
        model.close = { closed = true }
        model.activate(ValueEditOptions.optionID("done"))
        #expect(closed, "the panel does not wait for the server")
        #expect(model.notice == nil)
        #expect(source.writes == [.editProperties(F.t1, ["status": .string("done")], base: ItemVersion(1))])
        #expect(library.notices.waiting.isEmpty, "nothing is told as a fault while offline")

        // The copy applies the write at once and marks the item as waiting for the server.
        var waiting = try #require(library.item(F.t1))
        waiting.properties = waiting.properties.filter { $0.key != "status" } + [Property(key: "status", value: .string("done"))]
        waiting.sync = .waiting(writes: 1)
        source.send(.upserted([waiting]))
        #expect(await eventually { library.item(F.t1)?.value(of: "status") == .string("done") })
        #expect(library.item(F.t1)?.sync == .waiting(writes: 1))
        let reopened = ValueEditModel(request)
        #expect(reopened.rows.first { $0.isCurrent }?.id == ValueEditOptions.optionID("done"), "the next panel shows the queued value")
    }

    @Test func syncStateFollowsTheSource() async throws {
        let (library, source) = try await loaded()
        let problem = SyncProblemEntry(
            id: .write("w1"), itemID: F.n1, kind: .refused, change: .edit, reason: SyncProblem(code: "no"),
            content: SyncContent(title: "Plain note"), actions: [.discard], date: nil)
        source.report.set(SyncReport(waiting: 2, problems: [problem], queueRead: true))
        #expect(await eventually { library.syncReport.waiting == 2 })
        #expect(library.syncReport.problems == [problem])
        #expect(try await library.resolve(.write("w1"), by: .discard))
        #expect(source.resolved.withLock { $0 } == [.discard])

        var waiting = try #require(library.item(F.n1))
        waiting.sync = .waiting(writes: 1)
        source.send(.upserted([waiting]))
        #expect(await eventually { library.item(F.n1)?.sync == .waiting(writes: 1) })
        waiting.sync = .conflicted(sibling: F.n2, fields: ["body"])
        source.send(.upserted([waiting]))
        #expect(await eventually { library.item(F.n1)?.sync == .conflicted(sibling: F.n2, fields: ["body"]) })
    }
}

/// What an item's text links and embeds: the package writes each as an edge when the text is saved, so the items
/// at both ends show it.
@MainActor
@Suite(.hangLimit) struct MarfaLibraryTextEdgeTests {
    typealias F = LibraryFixture

    private static var catalogue: Catalogue {
        var catalogue = F.catalogue
        catalogue.edgeTypes["attached-to"] = EdgeTypeInfo(
            id: "attached-to", label: "Attached to", reverseLabel: "Attachments", reverseName: nil, cardinality: .many, writtenFrom: .from,
            fromTypes: [MarfaMapping.fileType], toTypes: [])
        return catalogue
    }

    private static func loaded() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        var items = F.items
        func replace(_ id: ItemID, _ change: (inout MarfaMac.Item) -> Void) {
            if let position = items.firstIndex(where: { $0.id == id }) { change(&items[position]) }
        }
        replace(F.n1) { note in
            note.edgesOut += [
                Edge(id: EdgeID("n1#references#1"), type: "references", from: F.n1, to: .pending(spelling: "Later"), origin: .body),
                Edge(id: EdgeID("n1#references#2"), type: "references", from: F.n1, to: .unresolved(spelling: "Nowhere", ambiguous: false), origin: .body),
                Edge(id: EdgeID("n1#references#3"), type: "references", from: F.n1, to: .unresolved(spelling: "Twin", ambiguous: true), origin: .body),
                Edge(id: EdgeID("n1#references#4"), type: "references", from: F.n1, to: .refused(spelling: "Banned", reason: "forbidden"), origin: .body),
            ]
        }
        replace(F.f1) { file in
            file.edgesOut = [Edge(id: EdgeID("at1"), type: "attached-to", from: F.f1, to: .item(F.n1), origin: .property("attached-to"))]
        }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return library
    }

    @Test func linksThatNameNoItemAreShownWithWhyAsTheTextsOwn() async throws {
        let library = try await Self.loaded()
        let mentions = library.bodyMentions(for: F.n1)
        #expect(mentions.map(\.title) == ["Bug one", "Later", "Nowhere", "Twin", "Banned"])
        #expect(mentions.map(\.resolution) == [.resolved(F.t1), .pending, .missing, .ambiguous([]), .refused("forbidden")])
        #expect(mentions.map(\.itemID) == [F.t1, nil, nil, nil, nil])
        // They are the text's, not relationships an item holds under a field of its own.
        #expect(!library.relationships(for: F.n1).contains { $0.field == "references" })
    }

    @Test func aLinkShowsAtItsTargetAsLinkedFromAndIsChangedInTheText() async throws {
        let library = try await Self.loaded()
        let linked = try #require(library.relationships(for: F.t1).first { $0.field == "inverse:references" })
        #expect(linked.label == "Referenced by")
        #expect(linked.targets.map(\.itemID) == [F.n1])
        #expect(!linked.isEditable)
        #expect(await library.changeLinks(F.t1, field: "inverse:references", adding: [], removing: [F.n1], undoManager: nil) != .taken)
    }

    @Test func anEmbeddedFileShowsAtBothEndsOfItsAttachment() async throws {
        let library = try await Self.loaded()
        let attachments = try #require(library.relationships(for: F.n1).first { $0.field == "inverse:attached-to" })
        #expect(attachments.label == "Attachments")
        #expect(attachments.targets.map(\.itemID) == [F.f1])
        let attachedTo = try #require(library.relationships(for: F.f1).first { $0.field == "attached-to" })
        #expect(attachedTo.targets.map(\.itemID) == [F.n1])
    }

    @Test func anAttachedFileIsLeftOutOfEveryListAndCountButSearch() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let album = ItemID("al1"), scan = ItemID("f2"), old = ItemID("old")
        func attached(_ id: ItemID) -> Edge {
            Edge(id: EdgeID("\(id.rawValue)#at"), type: "attached-to", from: id, to: .item(F.n1), origin: .property("attached-to"))
        }
        var items = F.items
        let photo = try #require(items.firstIndex { $0.id == F.f1 })
        items[photo].tags = [ItemTag.favorite]
        items[photo].edgesOut = [
            attached(F.f1), Edge(id: EdgeID("f1#in"), type: "in-collection", from: F.f1, to: .item(album), origin: .property("in-collection")),
        ]
        items += [
            F.item(album, F.album, "Trips", age: 10),
            F.item(scan, F.image, "Scan", age: 11, state: .archived, edges: [attached(scan)], titleRule: .firstLine, content: .file(.png, byteCount: 0)),
            F.item(old, F.note, "Archived note", age: 12, state: .archived),
        ]
        source.send(.loaded(SourceSnapshot(items: items, catalogue: Self.catalogue)))
        try #require(await eventually { library.isLoaded })

        #expect(!ids(library.favoriteItems(in: .all, archived: .hidden)).contains(F.f1))
        #expect(library.items(in: .collection(album)).isEmpty)
        #expect(library.count(in: .collection(album)) == 0)
        #expect(ids(library.items(in: .archive, scope: .all, archived: .only, includingKinds: true)) == [old])
        #expect(library.count(in: Place.archive) == 1)
        #expect(library.count(in: .type(F.image)) == 0)
        #expect(library.count(in: Place.library) == library.items(in: Place.library).count)
    }

    @Test func theAttachmentsOfAnItemAreTheItemsWhoseAttachedToEdgePointsAtIt() async throws {
        let library = try await Self.loaded()

        #expect(library.attachments(of: F.n1) == [F.f1])
        #expect(library.attachments(of: F.t1).isEmpty, "an edge of another type, or of another item, is no attachment")
        #expect(library.attachments(of: F.f1).isEmpty)
    }
}

/// The connect review's findings for the Marfa library, each failing on the code before its fix.
@MainActor
@Suite(.hangLimit) struct MarfaLibraryConnectReviewTests {
    /// A create refused before it was queued, as one made while the copy is brought up to date, has no problem in
    /// the queue to show; the library says so, and the window gives the new item up rather than open it.
    @Test func aCreateRefusedBeforeItIsQueuedOpensNothingAndSaysWhy() async throws {
        let (library, source) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        let id = try #require(await browser.quickAdded("Trip", in: library))
        #expect(browser.newItem?.id == id)

        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "hydration_incomplete", message: MarfaEngine.notCurrent))))
        #expect(await eventually { library.wasRefused(creating: id) })
        #expect(browser.isNewItemSettled(in: library))
        browser.finishNewItem(in: library)

        #expect(browser.newItem == nil)
        #expect(browser.selection.isEmpty)
        #expect(library.notices.waiting.last?.title == "Can’t Create Item")
        #expect(library.notices.waiting.last?.message == MarfaEngine.notCurrent)

        let again = try #require(await browser.quickAdded("Trip", in: library))
        #expect(again != id, "adding again makes another item rather than naming the refused one")
    }

    /// A create still awaited when another library opens is not followed there, since that library will never hold it.
    @Test func aCreateAwaitedWhenTheLibraryChangesIsNotCarriedToTheNextLibrary() async throws {
        let (library, _) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        _ = try #require(await browser.quickAdded("Trip", in: library))
        #expect(browser.newItem != nil)

        browser.adopt(FakeItemLibrary())
        #expect(browser.newItem == nil)
    }

    /// A write made after the source closed is kept nowhere, so the person is told rather than left to find it gone.
    @Test func aWriteMadeAfterTheSourceClosedSaysItWasNotKept() async throws {
        let (library, source) = try await loaded()
        await source.close()
        library.setFavorite([LibraryFixture.n1], false, undoManager: nil)
        #expect(library.notices.waiting.last?.message == "The app closed the library before it could keep your change. Make the change again.")
        #expect(source.submitted.isEmpty)
    }

    /// A page that hands over its text after the source closed, as one leaving while the copy opens again does,
    /// gives the text to the notices, which the app tells whichever library the windows read by then.
    @Test func textAClosedSourceWillNotTakeGoesToTheAppWithTheText() async throws {
        let (library, source) = try await loaded()
        await source.close()
        library.updateBody(of: LibraryFixture.n1, to: "Typed while the key changed")
        #expect(await eventually { library.notices.waiting.map(\.text) == ["Typed while the key changed"] })
    }

    /// The source answers nothing for a save it will not take, so no save of it is waited on to be read.
    @Test func textAClosedSourceWillNotTakeIsNotWaitedOnToBeRead() async throws {
        let (library, source) = try await loaded()
        await source.close()
        library.updateBody(of: LibraryFixture.n1, to: "Typed while the key changed")
        #expect(await eventually { !library.hasUnreadSave(LibraryFixture.n1) }, "nothing is on its way, so no embed waits for the copy to read it")
    }

    /// Text submitted just before the source closed is refused by it as it closes, and goes to the app too.
    @Test func textRefusedAsTheSourceClosesGoesToTheAppWithTheText() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: LibraryFixture.n1, to: "Typed as it closed")
        library.sendWaitingText()
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: MarfaEngine.closedCode, message: MarfaEngine.notKept))))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Typed as it closed"])
    }

    /// A create refused as the source closes gives back everything typed into it in quick add, its properties' text
    /// among it, since nothing else holds that.
    @Test func aCreateRefusedAsTheSourceClosesGivesBackItsPropertiesText() async throws {
        let (library, source) = try await loaded()
        _ = try #require(library.createItem(
            typeID: LibraryFixture.task.rawValue, title: "Kept", body: "Only copy", properties: ["status": .string("open")],
            parentID: nil, in: .library, undoManager: nil))
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: MarfaEngine.closedCode, message: MarfaEngine.notKept))))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Kept\n\nOnly copy\n\nopen"])
    }

    /// A save that arrives after the row can no longer be written reaches nothing, so the person is told and the text
    /// goes where they can get it back.
    @Test func textTypedOverAnItemThatCannotBeWrittenIsGivenBack() async throws {
        let (library, source) = try await loaded()
        var damaged = try #require(library.item(LibraryFixture.n1))
        damaged.problem = ItemProblem(message: "Damaged", withholdsText: true)
        source.send(.upserted([damaged]))
        try #require(await eventually { library.item(LibraryFixture.n1)?.problem != nil })

        library.updateBody(of: LibraryFixture.n1, to: "Typed as the row turned unreadable")
        #expect(library.notices.waiting.map(\.text) == ["Typed as the row turned unreadable"])
        #expect(library.notices.waiting.last?.message == "\(MarfaLibrary.cantChange) Your text is on the clipboard, so you can paste it back.")
        #expect(source.writes.isEmpty)
    }

    /// The page's last save can arrive for an item another device purged meanwhile, which no queue will take.
    @Test func textForAnItemThatLeftTheCopyIsGivenBack() async throws {
        let (library, source) = try await loaded()
        source.send(.removed([LibraryFixture.n1]))
        try #require(await eventually { library.item(LibraryFixture.n1) == nil })

        library.updateBody(of: LibraryFixture.n1, to: "Typed as it was purged")
        #expect(library.notices.waiting.map(\.text) == ["Typed as it was purged"])
        #expect(library.notices.waiting.last?.message == "\(MarfaLibrary.cantChange) Your text is on the clipboard, so you can paste it back.")
        #expect(source.writes.isEmpty)
    }

    /// A text save the package refused before queueing it is in no queue, so the typed text is given back with the
    /// reason, in place of an alert the page then replaces with the server's text.
    @Test func textRefusedBeforeItWasQueuedIsGivenBackWithTheReason() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: LibraryFixture.n1, to: "Typed while the copy was brought up to date")
        library.sendWaitingText()
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "copy_expired", message: "Try again in a moment.", notQueued: true))))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Typed while the copy was brought up to date"])
        #expect(library.notices.waiting.last?.message == "Try again in a moment. Your text is on the clipboard, so you can paste it back.")
        #expect(library.notices.waiting.count == 1, "the person is told once")
    }

    /// A create with a body that the package refused before queueing it, such as a reserved type, is in no queue,
    /// so its text is given back with the server's reason.
    @Test func aCreateRefusedBeforeItWasQueuedGivesItsTextBack() async throws {
        let (library, source) = try await loaded()
        _ = try #require(library.createItem(
            typeID: "core.note", title: "Kept", body: "Only copy", parentID: nil, in: .library, undoManager: nil
        ))
        let write = try #require(source.submitted.last?.id)
        let problem = SyncProblem(code: "type_not_permitted", message: "Not this type.", notQueued: true)
        source.send(.answered(write, .refused(problem)))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Kept\n\nOnly copy"])
        #expect(library.notices.waiting.last?.message == "Not this type. Your text is on the clipboard, so you can paste it back.")
        #expect(library.notices.waiting.count == 1, "the person is told once")
    }

    /// A title the package refused before queueing it, such as while the copy hydrates again, is in no queue, so
    /// what the person typed is given back with the reason.
    @Test func aTitleRefusedBeforeItWasQueuedIsGivenBack() async throws {
        let (library, source) = try await loaded()
        #expect(library.setItemProperty(LibraryFixture.n1, key: "title", value: .string("Typed title"), undoManager: nil))
        let write = try #require(source.submitted.last?.id)
        let problem = SyncProblem(code: "hydration_incomplete", message: "Try again in a moment.", notQueued: true)
        source.send(.answered(write, .refused(problem)))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Typed title"])
        #expect(library.notices.waiting.last?.message == "Try again in a moment. Your text is on the clipboard, so you can paste it back.")
        #expect(library.notices.waiting.count == 1, "the person is told once")
    }

    /// Typed text is kept when the copy already knows another device purged the item, so the package refuses the write
    /// itself: nothing is queued, and a body or a title is given back with the server's words.
    @Test(arguments: ["body", "title"])
    func textForAnItemThePackageKnowsWasPurgedIsGivenBack(_ kind: String) async throws {
        let (library, source) = try await loaded()
        if kind == "body" {
            library.updateBody(of: LibraryFixture.n1, to: "Typed as it was purged")
            library.sendWaitingText()
        } else {
            #expect(library.setItemProperty(LibraryFixture.n1, key: "title", value: .string("Typed as it was purged"), undoManager: nil))
        }
        let write = try #require(source.submitted.last?.id)
        let problem = SyncProblem(code: "item_not_found", message: "This item is gone.", notQueued: true)
        source.send(.answered(write, .refused(problem)))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Typed as it was purged"])
        #expect(library.notices.waiting.last?.message == "This item is gone. Your text is on the clipboard, so you can paste it back.")
        #expect(library.notices.waiting.count == 1, "the person is told once")
    }

    /// A list of entries refused before it was queued is in no queue either, so the text in its entries is given back.
    @Test func aListRefusedBeforeItWasQueuedGivesItsTextBack() async throws {
        let shape = ListShape(members: [.init(key: "value", label: "Value", kind: .text(nil)), .init(key: "label", label: "Label", kind: .text(nil))])
        let person = TypeID("t")
        let type = ItemTypeInfo(
            id: person, label: "T", fields: [LibraryFixture.field("title", .text, in: person), LibraryFixture.field("emails", .list(shape), in: person)],
            titleField: "title", bodyField: nil, parent: nil)
        let item = LibraryFixture.item(LibraryFixture.n1, person, "Ada", age: 1)
        let (library, source) = try await loaded([item], catalogue: Catalogue(itemTypes: [type]))
        let list: PropertyValue = .array([.object(["value": .string("a@example.com"), "label": .string("home")])])
        #expect(library.setItemProperty(LibraryFixture.n1, key: "emails", value: list, undoManager: nil))
        let write = try #require(source.submitted.last?.id)
        let problem = SyncProblem(code: "hydration_incomplete", message: "Try again in a moment.", notQueued: true)
        source.send(.answered(write, .refused(problem)))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map { $0.text } == ["home\n\na@example.com"])
    }

    /// A property edit is on its way until the copy takes or refuses it, so a list of entries can tell a write still
    /// coming from one refused.
    @Test func aPropertyEditIsOnItsWayUntilTakenOrRefused() async throws {
        let (library, source) = try await loaded()
        #expect(!library.isWritingProperties(of: LibraryFixture.en1))
        #expect(library.setItemProperty(LibraryFixture.en1, key: "name", value: .string("Ada L"), undoManager: nil))
        #expect(library.isWritingProperties(of: LibraryFixture.en1))
        #expect(!library.isWritingProperties(of: LibraryFixture.n1))
        source.send(.taken(try #require(source.submitted.last?.id)))
        #expect(await eventually { !library.isWritingProperties(of: LibraryFixture.en1) })

        #expect(library.setItemProperty(LibraryFixture.en1, key: "name", value: .string("Ada K"), undoManager: nil))
        #expect(library.isWritingProperties(of: LibraryFixture.en1))
        let problem = SyncProblem(code: "hydration_incomplete", message: "Try again in a moment.", notQueued: true)
        source.send(.answered(try #require(source.submitted.last?.id), .refused(problem)))
        #expect(await eventually { !library.isWritingProperties(of: LibraryFixture.en1) })
    }

    /// A value set back while the edit it reverses is still on its way is sent too, though it equals the stored value,
    /// so the edit in flight does not land as the value kept.
    @Test func aPropertySetBackBeforeItsEditIsTakenIsSent() async throws {
        let (library, source) = try await loaded()
        let id = LibraryFixture.en1
        let original = try #require(library.item(id)?.value(of: "name"))
        #expect(library.setItemProperty(id, key: "name", value: .string("Ada L"), undoManager: nil))
        #expect(library.setItemProperty(id, key: "name", value: original, undoManager: nil))

        let edits = source.writes.compactMap { write -> PropertyValue?? in
            guard case .editProperties(let item, let changes, _) = write, item == id else { return nil }
            return changes["name"]
        }
        #expect(edits == [.string("Ada L"), original])

        // The copy applies the two in order, so it ends holding the value set back.
        var item = try #require(library.item(id))
        for (write, value) in zip(source.submitted.suffix(2), [PropertyValue.string("Ada L"), original]) {
            item.properties = [Property(key: "name", value: value)]
            source.send(.upserted([item]))
            source.send(.taken(write.id))
        }
        #expect(await eventually { !library.isWritingProperties(of: id) })
        #expect(library.item(id)?.value(of: "name") == original)
        let count = source.writes.count
        #expect(library.setItemProperty(id, key: "name", value: original, undoManager: nil))
        #expect(source.writes.count == count, "with nothing on its way, the stored value is not sent again")
    }

    /// Each property edit carries a mark, which says once the copy took it, and never for one refused.
    @Test func aPropertyEditsMarkSaysWhetherTheCopyTookIt() async throws {
        let (library, source) = try await loaded()
        #expect(library.setItemProperty(LibraryFixture.en1, key: "name", value: .string("Ada L"), undoManager: nil))
        let taken = try #require(library.lastPropertyWrite)
        #expect(!library.tookPropertyWrite(taken))
        source.send(.taken(try #require(source.submitted.last?.id)))
        #expect(await eventually { library.tookPropertyWrite(taken) })

        #expect(library.setItemProperty(LibraryFixture.en1, key: "name", value: .string("Ada K"), undoManager: nil))
        let refused = try #require(library.lastPropertyWrite)
        #expect(refused != taken)
        let problem = SyncProblem(code: "hydration_incomplete", message: "Try again in a moment.", notQueued: true)
        source.send(.answered(try #require(source.submitted.last?.id), .refused(problem)))
        #expect(await eventually { !library.isWritingProperties(of: LibraryFixture.en1) })
        #expect(!library.tookPropertyWrite(refused))
    }

    /// A text save the server refused stays listed in Settings, but the page goes back to the server's text,
    /// so the typed text is also given back, with the reason and where the change is listed.
    @Test func textTheServerRefusedIsGivenBackAndPointsToLibrarySettings() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: LibraryFixture.n1, to: "Refused later")
        library.sendWaitingText()
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "validation_error", message: "Too long."))))
        #expect(await eventually { !library.notices.waiting.isEmpty })
        #expect(library.notices.waiting.map(\.text) == ["Refused later"])
        #expect(library.notices.waiting.last?.message == "Too long. The change is also listed in Settings. Your text is on the clipboard, so you can paste it back.")
        #expect(library.notices.waiting.count == 1, "the person is told once")
    }
}

/// A relation whose two ends share one name reads the same from either item, so its links are one list.
@MainActor
@Suite(.hangLimit) struct MarfaLibraryTwoWayTests {
    typealias F = LibraryFixture

    private static func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        var catalogue = F.catalogue
        catalogue.edgeTypes["related"] = EdgeTypeInfo(
            id: "related", label: "Related to", reverseLabel: "Related to", reverseName: nil, cardinality: .many,
            writtenFrom: .from, fromTypes: [], toTypes: [])
        var items = F.items
        func link(_ id: String, from source: ItemID, to target: ItemID) -> Edge {
            Edge(id: EdgeID(id), type: "related", from: source, to: .item(target), origin: .property("related"))
        }
        items[items.firstIndex { $0.id == F.n1 }!].edgesOut += [link("rel1", from: F.n1, to: F.p1)]
        items[items.firstIndex { $0.id == F.n2 }!].edgesOut += [link("rel2", from: F.n2, to: F.n1)]
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func aTwoWayRelationShowsItsOutgoingAndIncomingLinksAsOneList() async throws {
        let (library, _) = try await Self.loaded()
        let related = library.relationships(for: F.n1).filter { $0.field.hasSuffix("related") }
        #expect(related.count == 1)
        #expect(related.first?.label == "Related to")
        #expect(Set(related.first?.targets.compactMap(\.itemID) ?? []) == [F.p1, F.n2])
        // The item it points at reads it the same way, from the other side.
        #expect(library.relationships(for: F.p1).first { $0.field.hasSuffix("related") }?.targets.map(\.itemID) == [F.n1])
    }

    @Test func removingFromTheCombinedListRemovesTheLinkInTheDirectionItWasMade() async throws {
        let (library, source) = try await Self.loaded()
        source.clearWrites()
        #expect(await library.changeLinks(F.n1, field: "related", adding: [], removing: [F.n2], undoManager: nil) == .taken)
        #expect(source.writes == [.unlink(EdgeID("rel2"))])
    }

    /// A one-to-one relation holds one link whichever item made it, so replacing a link that points at this item
    /// moves the end that is not this item's.
    @Test func replacingALinkThatOnlyPointsHereMovesItsOtherEnd() async throws {
        var catalogue = F.catalogue
        catalogue.edgeTypes["partner"] = EdgeTypeInfo(
            id: "partner", label: "Partner", reverseLabel: "Partner", reverseName: nil, cardinality: .one,
            writtenFrom: .from, fromTypes: [], toTypes: [], reverseCardinality: .one)
        var items = F.items
        items[items.firstIndex { $0.id == F.n2 }!].edgesOut += [
            Edge(id: EdgeID("pt1"), type: "partner", from: F.n2, to: .item(F.n1), origin: .property("partner"))
        ]
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        #expect(await library.changeLinks(F.n1, field: "partner", adding: [F.p1], removing: [F.n2], undoManager: nil) == .taken)
        #expect(await eventually { source.writes == [.moveEdge(EdgeID("pt1"), end: .from, to: F.p1, from: F.n2)] }, "sent \(source.writes)")
        #expect(library.notices.waiting.last == nil)
    }
}
