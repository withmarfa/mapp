import Foundation
import Observation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// A small Marfa library: types with subtypes, a project with a child and a grandchild, favorites, an item in the
/// feed, one in the bin, an entity titled by its name and an image.
nonisolated enum LibraryFixture {
    static let note = TypeID("core.note")
    static let ticket = TypeID("aic.ticket")
    static let task = TypeID("aic.ticket.task")
    static let bug = TypeID("aic.ticket.bug")
    static let project = MarfaMapping.projectType
    static let entity = TypeID("core.entity")
    static let image = TypeID("core.image")
    static let album = TypeID("core.album")

    static let p1 = ItemID("p1"), p2 = ItemID("p2"), e1 = ItemID("e1"), t1 = ItemID("t1")
    static let n1 = ItemID("n1"), n2 = ItemID("n2"), n3 = ItemID("n3"), en1 = ItemID("en1"), f1 = ItemID("f1")

    static func field(_ key: String, _ kind: ItemTypeInfo.Field.Kind, in type: TypeID = note) -> ItemTypeInfo.Field {
        ItemTypeInfo.Field(key: key, label: MarfaMapping.label(forField: key), kind: kind, declaredBy: type)
    }

    static let ticketFields = [
        field("title", .text), field("body", .text), field("status", .choice(["open", "done"]), in: ticket),
        field("due", .date, in: ticket),
    ]

    static let catalogue = Catalogue(
        itemTypes: [
            ItemTypeInfo(
                id: note, label: "Note", fields: [field("title", .text), field("body", .text)], titleField: "title",
                bodyField: "body", parent: nil),
            ItemTypeInfo(id: ticket, label: "Ticket", fields: ticketFields, titleField: "title", bodyField: "body", parent: note),
            ItemTypeInfo(id: task, label: "Task", fields: ticketFields, titleField: "title", bodyField: "body", parent: ticket),
            ItemTypeInfo(id: bug, label: "Bug", fields: ticketFields, titleField: "title", bodyField: "body", parent: ticket),
            ItemTypeInfo(
                id: project, label: "Project", fields: [field("title", .text), field("body", .text)],
                titleField: "title", bodyField: "body", parent: note),
            ItemTypeInfo(
                id: entity, label: "Entity", fields: [field("name", .text, in: entity)], titleField: "name",
                bodyField: nil, parent: nil),
            ItemTypeInfo(id: MarfaMapping.fileType, label: "File", fields: [], titleField: nil, bodyField: nil, parent: nil),
            ItemTypeInfo(id: image, label: "Image", fields: [], titleField: nil, bodyField: nil, parent: MarfaMapping.fileType),
            ItemTypeInfo(
                id: album, label: "Album", fields: [field("title", .text, in: album)], titleField: "title", bodyField: nil,
                parent: nil, roles: ["container"]),
        ],
        edgeTypes: [
            EdgeTypeInfo(
                id: "parent-of", label: "Parent of", reverseName: "child-of", cardinality: .one, writtenAt: .target,
                sourceTypes: [], targetTypes: []),
            EdgeTypeInfo(
                id: "about", label: "About", reverseName: nil, cardinality: .many, writtenAt: .source,
                sourceTypes: [], targetTypes: []),
            EdgeTypeInfo(
                id: "supersedes", label: "Supersedes", reverseName: nil, cardinality: .one, writtenAt: .source,
                sourceTypes: [ticket], targetTypes: [ticket], reverseCardinality: .one),
            EdgeTypeInfo(
                id: "in-collection", label: "In collection", reverseName: nil, cardinality: .many, writtenAt: .source,
                sourceTypes: [], targetTypes: [], targetRoles: ["container"]),
            EdgeTypeInfo(
                id: "references", label: "References", reverseName: nil, cardinality: .many, writtenAt: .source,
                sourceTypes: [], targetTypes: []),
            EdgeTypeInfo(
                id: "in-folder", label: "In folder", reverseName: nil, cardinality: .many, writtenAt: .source,
                sourceTypes: [], targetTypes: [TypeID("system.folder")]),
        ])

    static func child(_ edge: String, _ child: ItemID, of parent: ItemID) -> Edge {
        Edge(id: EdgeID(edge), type: "child-of", source: child, target: .item(parent), origin: .property("child-of"))
    }

    static func item(
        _ id: ItemID, _ type: TypeID, _ title: String, age: Int, state: ItemState = .active, tier: Tier = .library,
        tags: Set<String> = [], edges: [Edge] = [], titleRule: Item.TitleRule = .property("title"),
        properties: [Property] = [], content: Item.Content = .markdown
    ) -> Item {
        let date = Date(timeIntervalSince1970: 1_000_000 - Double(age))
        return Item(
            id: id, type: type, title: title, titleRule: titleRule, properties: properties, content: content,
            state: state, tier: tier, tags: tags, version: ItemVersion(1), created: date, modified: date,
            trashed: state == .trashed ? date : nil, edgesOut: edges)
    }

    static var items: [Item] {
        [
            item(p1, project, "Alpha", age: 1),
            item(e1, task, "Epic task", age: 2, edges: [child("c1", e1, of: p1)]),
            item(t1, bug, "Bug one", age: 3, tags: [ItemTag.favorite], edges: [child("c2", t1, of: e1)]),
            item(n1, note, "Plain note", age: 4, tags: [ItemTag.favorite], edges: [
                Edge(id: EdgeID("a1"), type: "about", source: n1, target: .item(p1), origin: .property("about")),
                Edge(id: EdgeID("r1"), type: "references", source: n1, target: .item(t1), origin: .body),
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
        SourceSnapshot(items: items, catalogue: catalogue, places: [])
    }
}

@MainActor
private func loaded(_ items: [Item] = LibraryFixture.items) async throws -> (MarfaLibrary, FakeItemSource) {
    let source = FakeItemSource()
    for (id, text) in LibraryFixture.texts { source.setBody(text, of: id) }
    let library = MarfaLibrary(source: source)
    source.send(.loaded(SourceSnapshot(items: items, catalogue: LibraryFixture.catalogue, places: [])))
    try #require(await eventually { library.isLoaded })
    return (library, source)
}

private func ids(_ items: [MAPP.Item]) -> Set<ItemID> { Set(items.map(\.id)) }

/// Whether reading `read` is told of the next change, which the test then makes.
@MainActor
private func observes(_ read: () -> Void) -> LiveMarfa.Flag {
    let flag = LiveMarfa.Flag()
    withObservationTracking(read) { flag.set() }
    return flag
}

@MainActor
@Suite struct MarfaLibraryReadingTests {
    typealias F = LibraryFixture

    @Test func isLoadedOnlyOnceTheCopyAndItsTextAreRead() async throws {
        let source = FakeItemSource()
        source.setBody("Alpha body", of: F.p1)
        let library = MarfaLibrary(source: source)
        #expect(!library.isLoaded)
        #expect(!library.isGone(F.p1))
        source.send(.loaded(F.snapshot))
        #expect(await eventually { library.isLoaded })
        #expect(library.body(of: F.p1)?.text == "Alpha body")
        #expect(library.body(of: F.en1) == nil)
        #expect(library.catalogue == F.catalogue)
    }

    @Test func eachPlaceHoldsWhatItsNameSays() async throws {
        let (library, _) = try await loaded()
        #expect(ids(library.items(in: .inbox)) == [F.n2])
        #expect(ids(library.items(in: .allNotes)) == [F.p1, F.e1, F.t1, F.n1, F.n2, F.en1, F.f1, F.p2])
        #expect(ids(library.items(in: .favorites)) == [F.t1, F.n1])
        #expect(ids(library.items(in: .favoriteItem(F.n1))) == [F.n1])
        #expect(library.items(in: .favoriteItem(F.n2)).isEmpty)
        #expect(ids(library.items(in: .itemType("aic.ticket"))) == [F.e1, F.t1])
        #expect(ids(library.items(in: .itemType("aic.ticket.bug"))) == [F.t1])
        #expect(ids(library.items(in: .project(F.p1))) == [F.p1, F.e1, F.t1])
        #expect(ids(library.items(in: .project(F.p2))) == [F.p2])
        #expect(ids(library.items(in: .files)) == [F.f1])
        #expect(ids(library.items(in: .recentlyDeleted)) == [F.n3])
        #expect(library.items(in: .folder(F.p1)).isEmpty)
        #expect(library.items(in: .marfaTypes).isEmpty)
        #expect(library.folders.isEmpty)
        for place in [SidebarItem.inbox, .allNotes, .favorites, .itemType("aic.ticket"), .project(F.p1), .files, .recentlyDeleted] {
            #expect(library.count(in: place) == library.items(in: place).count, "\(place)")
        }
        // Newest first, as the source paints them.
        #expect(library.items(in: .allNotes).first?.id == F.p1)
    }

    @Test func placesAreNamedForThePerson() async throws {
        let (library, _) = try await loaded()
        #expect(library.name(of: .inbox) == String(localized: "Inbox"))
        #expect(library.name(of: .allNotes) == String(localized: "All Items"))
        #expect(library.name(of: .itemType("aic.project")) == String(localized: "Projects"))
        #expect(library.name(of: .itemType("aic.ticket.bug")) == "Bug")
        #expect(library.name(of: .project(F.p1)) == "Alpha")
        #expect(library.name(of: .favoriteItem(F.n1)) == "Plain note")
    }

    @Test func changesFromTheSourceReplaceWhatWasHeld() async throws {
        let (library, source) = try await loaded()
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Renamed"
        renamed.tier = .library
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.n2)?.title == "Renamed" })
        #expect(library.items(in: .inbox).isEmpty)

        let added = F.item(ItemID("new"), F.task, "New task", age: 0, edges: [F.child("c9", ItemID("new"), of: F.p2)])
        source.setBody("Fresh", of: added.id)
        source.send(.upserted([added]))
        #expect(await eventually { library.item(added.id) != nil })
        #expect(library.body(of: added.id)?.text == "Fresh")
        #expect(ids(library.items(in: .project(F.p2))) == [F.p2, added.id])
        #expect(library.count(in: .itemType("aic.ticket")) == 3)

        source.send(.removed([F.n1]))
        #expect(await eventually { library.isGone(F.n1) })
        #expect(library.item(F.n1) == nil)
        #expect(!ids(library.items(in: .favorites)).contains(F.n1))
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
        source.send(.bodyChanged(F.p1, ItemVersion(2)))
        #expect(await eventually { library.body(of: F.p1)?.text == "Changed in place" })
    }

    @Test func searchAsksTheCopyAndLeavesOutTheBin() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1, F.n3, F.p1] }
        #expect(library.items(matching: "  ").isEmpty)
        #expect(await eventually { library.items(matching: "body").map(\.id) == [F.n1, F.p1] })
        let searches = source.searches.withLock { $0 }
        _ = library.items(matching: "body")
        #expect(source.searches.withLock { $0 } == searches)

        // A change to the items asks again, and the last results stand meanwhile.
        source.hits.withLock { $0["body"] = [F.p1] }
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Other"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.items(matching: "body").map(\.id) == [F.p1] })
    }

    @Test func aSearchThatFailsKeepsWhatWasFoundAndSaysWhy() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["body"] = [F.n1] }
        #expect(await eventually { library.items(matching: "body").map(\.id) == [F.n1] })
        source.searchFails.withLock { $0 = true }
        var renamed = try #require(library.item(F.n2))
        renamed.title = "Other"
        source.send(.upserted([renamed]))
        // The list reads the search again as it redraws for the change.
        #expect(await eventually {
            _ = library.items(matching: "body")
            return library.failure != nil
        })
        #expect(library.failure?.title == String(localized: "Can’t Search"))
        #expect(library.items(matching: "body").map(\.id) == [F.n1])
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
        #expect(project.first { $0.field == "inverse:about" }?.label == "Items About This")
        #expect(project.first { $0.field == "child-of" }?.targets.isEmpty == true)

        let note = library.relationships(for: F.n1)
        #expect(note.first { $0.field == "about" }?.allowsMultiple == true)
        #expect(!note.contains { $0.field == "supersedes" })
        #expect(library.bodyMentions(for: F.n1).map(\.itemID) == [F.t1])
        #expect(library.relationships(for: F.f1).allSatisfy { !$0.isEditable })
    }

    @Test func candidatesFollowTheCatalogueAndNeverCloseACycle() async throws {
        let (library, _) = try await loaded()
        // Not itself, and not the task below it, which would make it its own ancestor.
        #expect(ids(library.relationshipCandidates(for: F.e1, field: "child-of")) == [F.p1, F.n1, F.n2, F.en1, F.f1, F.p2])
        // Not the project above it, nor anything in the bin.
        #expect(ids(library.relationshipCandidates(for: F.t1, field: "inverse:parent-of")) == [F.n1, F.n2, F.en1, F.f1, F.p2])
        #expect(ids(library.relationshipCandidates(for: F.e1, field: "supersedes")) == [F.t1])
        #expect(library.relationshipCandidates(for: F.n1, field: "supersedes").isEmpty)
        #expect(library.creationParentCandidates(typeID: "aic.ticket.task").count == 8)
        #expect(library.relationshipCandidates(for: F.e1, field: "child-of").map(\.title) ==
            ["Ada", "Alpha", "Beta", "Feed note", "Photo", "Plain note"])
    }

    @Test func aRoleAllowsTheTypesThatPlayIt() async throws {
        let album = F.item(ItemID("al1"), F.album, "Holiday", age: 0)
        let (library, _) = try await loaded(F.items + [album])
        #expect(ids(library.relationshipCandidates(for: F.n1, field: "in-collection")) == [album.id])
        #expect(library.relationships(for: F.n1).contains { $0.field == "in-collection" })
        #expect(library.setItemRelationship(F.n1, field: "in-collection", targetIDs: [album.id], undoManager: nil))
        #expect(!library.setItemRelationship(F.n1, field: "in-collection", targetIDs: [F.p1], undoManager: nil))
        #expect(library.failure?.message == String(localized: "This kind of item can’t be linked here."))
    }

    @Test func whatOnlyFilesHaveAnswersNothing() async throws {
        let (library, source) = try await loaded()
        #expect(library.folderURL == nil)
        #expect(library.fileURL(for: F.f1) == nil)
        #expect(try await library.fileURL(of: F.f1) == URL(filePath: "/dev/null"))
        #expect(try await library.fileURL(of: F.n1) == nil)
        #expect(library.path(of: F.n1) == nil)
        #expect(library.fileName(of: F.n1) == nil)
        #expect(library.imageBase(of: F.n1) == nil)
        #expect(library.folder(F.n1) == nil)
        #expect(library.trashDays == nil)
        #expect(!library.isItemTitleTaken("Alpha"))
        #expect(library.idsForWindows([F.n1, ItemID("missing")]) == [F.n1])
        library.leave(F.n1)
        #expect(source.ended.withLock { $0 } == [F.n1])
    }
}

@MainActor
@Suite struct MarfaLibraryWritingTests {
    typealias F = LibraryFixture

    @Test func creatingMintsTheIdAndPutsTheItemUnderItsParent() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        let id = try #require(library.createItem(
            typeID: "aic.ticket.task", title: "  New task ", body: "Text", parentID: F.p1, in: .allNotes, undoManager: undo))
        #expect(id.rawValue == id.rawValue.lowercased())
        #expect(id.rawValue.dropFirst(14).first == "7")
        #expect(source.writes == [.create(id: id, ItemDraft(type: F.task, title: "New task", body: "Text", parent: F.p1))])

        // The Inbox is the feed tier, and a blank body is no text.
        let inbox = try #require(library.createItem(
            typeID: "core.note", title: "Captured", body: "\n", parentID: nil, in: .inbox, undoManager: nil))
        #expect(source.writes.last == .create(id: inbox, ItemDraft(type: F.note, title: "Captured", tier: .feed)))

        // Undoing a create puts the item in the bin; redoing it brings it back.
        source.send(.upserted([F.item(id, F.task, "New task", age: 0, edges: [F.child("c8", id, of: F.p1)])]))
        #expect(await eventually { library.item(id) != nil })
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.transition(id, .trashed)])
        undo.redo()
        #expect(source.writes == [.transition(id, .trashed), .transition(id, .active)])
    }

    @Test func aCreateTheCatalogueRefusesIsToldAndNotSent() async throws {
        let (library, source) = try await loaded()
        #expect(library.createItem(typeID: "no.such", title: "X", body: "", parentID: nil, in: .allNotes, undoManager: nil) == nil)
        #expect(library.failure?.title == String(localized: "Can’t Create Item"))
        library.failure = nil
        #expect(library.createItem(typeID: "core.note", title: " ", body: "", parentID: nil, in: .allNotes, undoManager: nil) == nil)
        #expect(library.failure != nil)
        #expect(source.writes.isEmpty)
    }

    @Test func textIsEditedFromTheVersionReadAndHeldUntilAnswered() async throws {
        let (library, source) = try await loaded()
        library.updateBody(of: F.n1, to: "Note body")
        #expect(source.writes.isEmpty)
        library.updateBody(of: F.n1, to: "Typed")
        #expect(source.writes == [.editBody(F.n1, "Typed", base: ItemVersion(1), merge: .asRead)])
        #expect(library.body(of: F.n1)?.text == "Typed")

        // A read that raced the write gives older text, which the library does not take.
        source.setBody("Note bod", of: F.n1)
        source.send(.bodyChanged(F.n1, ItemVersion(1)))
        source.send(.upserted([F.item(F.n1, F.note, "Plain note", age: 4, tags: [ItemTag.favorite])]))
        #expect(await eventually { library.item(F.n1)?.edgesOut.isEmpty == true })
        #expect(library.body(of: F.n1)?.text == "Typed")

        // Once answered, what the copy holds stands, merged or not.
        source.setBody("Typed, merged", of: F.n1, version: 2)
        source.send(.answered(try #require(source.submitted.first?.id), .accepted))
        #expect(await eventually { library.body(of: F.n1)?.text == "Typed, merged" })
        #expect(library.failure == nil)

        // The next edit goes from the version of the text now held.
        library.updateBody(of: F.n1, to: "Again")
        #expect(source.writes.last == .editBody(F.n1, "Again", base: ItemVersion(2), merge: .asRead))

        // An item in the bin, or a file, takes no text.
        library.updateBody(of: F.n3, to: "No")
        library.updateBody(of: F.f1, to: "No")
        #expect(source.writes.count == 2)
    }

    @Test func aTitleIsTheTypesTitleFieldAndUndoesAtTheCurrentVersion() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(library.setItemProperty(F.en1, key: "title", value: .string(" Ada L. "), undoManager: undo))
        #expect(source.writes == [.editProperties(F.en1, ["name": .string("Ada L.")], base: ItemVersion(1), undoing: nil)])

        var moved = try #require(library.item(F.en1))
        moved.version = ItemVersion(7)
        source.send(.upserted([moved]))
        #expect(await eventually { library.item(F.en1)?.version == ItemVersion(7) })
        undo.undo()
        #expect(source.writes.last == .editProperties(F.en1, ["name": .string("Ada")], base: ItemVersion(7), undoing: nil))

        // A title that is the first line of the text is edited in the text.
        #expect(!library.setItemProperty(F.f1, key: "title", value: .string("X"), undoManager: nil))
        #expect(!library.setItemProperty(F.en1, key: "title", value: .string(" "), undoManager: nil))
    }

    @Test func aPropertyIsCheckedAgainstItsFieldAndUndone() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        #expect(!library.setItemProperty(F.t1, key: "status", value: .string("maybe"), undoManager: undo))
        #expect(library.failure?.title == String(localized: "Invalid Property"))
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
        #expect(source.writes.last == .editProperties(F.t1, ["due": nil], base: ItemVersion(1), undoing: nil))
        undo.undo()
        #expect(source.writes.last == .editProperties(F.t1, ["status": nil], base: ItemVersion(1), undoing: nil))
        undo.redo()
        #expect(source.writes.last == .editProperties(F.t1, ["status": .string("done")], base: ItemVersion(1), undoing: nil))
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
        #expect(source.writes == [.transition(F.n1, .trashed)])
        #expect(undo.undoActionName == String(localized: "Delete Note"))
        undo.undo()
        #expect(source.writes.last == .transition(F.n1, .active))
        source.clearWrites()
        library.recover([F.n3, F.n1], undoManager: undo)
        #expect(source.writes == [.transition(F.n3, .active)])
        undo.undo()
        #expect(source.writes.last == .transition(F.n3, .trashed))
    }

    @Test func anItemTheServersBinHoldsIsNotRecoveredAndThePersonIsTold() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        // The server took the delete, so the copy no longer holds the item.
        source.send(.removed([F.n1]))
        #expect(await eventually { library.item(F.n1) == nil })
        source.clearWrites()
        undo.undo()
        #expect(source.writes.isEmpty)
        #expect(library.failure?.title == String(localized: "Can’t Recover"))
        let inTheBin = try #require(library.failure?.message)

        // One the copy held when asked, but not by the time the source made it, is told the same way.
        library.failure = nil
        library.recover([F.n3], undoManager: nil)
        let restore = try #require(source.submitted.last?.id)
        source.send(.answered(restore, .refused(SyncProblem(code: MarfaLibrary.notHeldCode, message: "not found"))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.message == inTheBin)
    }

    @Test func aLinkIsAddedAndRemovedButNotReplacedYet() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        let notYet = String(localized: "Changing this link isn’t available yet in a Marfa library.")
        // A new parent, or a child taken from the parent it has, would replace the one link that end holds.
        #expect(!library.setItemRelationship(F.t1, field: "child-of", targetIDs: [F.p1], undoManager: undo))
        #expect(library.failure?.message == notYet)
        library.failure = nil
        #expect(!library.setItemRelationship(F.p2, field: "inverse:parent-of", targetIDs: [F.e1], undoManager: undo))
        #expect(library.failure?.message == notYet)
        #expect(source.writes.isEmpty)
        #expect(!undo.canUndo)

        // Removing the parent, then choosing one for an end that holds none, are each one write.
        undo.beginUndoGrouping()
        #expect(library.setItemRelationship(F.t1, field: "child-of", targetIDs: [], undoManager: undo))
        undo.endUndoGrouping()
        #expect(source.writes == [.unlink(EdgeID("c2"))])
        source.send(.upserted([F.item(F.t1, F.bug, "Bug one", age: 3, tags: [ItemTag.favorite])]))
        #expect(await eventually { library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.isEmpty == true })
        source.clearWrites()
        undo.beginUndoGrouping()
        #expect(library.setItemRelationship(F.t1, field: "child-of", targetIDs: [F.p1], undoManager: undo))
        undo.endUndoGrouping()
        let toProject = EdgeDraft(type: "parent-of", source: F.p1, target: F.t1)
        #expect(source.writes == [.link(toProject, undoing: nil)])

        // The source says what it made; the undo takes that edge away, and the next puts the old parent back.
        source.send(.upserted([F.item(F.t1, F.bug, "Bug one", age: 3, tags: [ItemTag.favorite], edges: [F.child("c7", F.t1, of: F.p1)])]))
        #expect(await eventually { library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.first?.itemID == F.p1 })
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.unlink(EdgeID("c7"))])
        undo.undo()
        #expect(source.writes.last == .link(EdgeDraft(type: "parent-of", source: F.e1, target: F.t1), undoing: nil))

        // A field that holds many adds and removes in one change.
        source.clearWrites()
        #expect(library.setItemRelationship(F.n1, field: "about", targetIDs: [F.p2], undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "about", source: F.n1, target: F.p2), undoing: nil)])
        // The old link goes once the source has taken the new one.
        source.send(.answered(try #require(source.submitted.last?.id), .accepted))
        #expect(await eventually { source.writes.last == .unlink(EdgeID("a1")) })
    }

    @Test func anItemPointedAtOnlyOnceKeepsItsOne() async throws {
        let bug2 = F.item(ItemID("t2"), F.bug, "Bug two", age: 0, edges: [
            Edge(id: EdgeID("s1"), type: "supersedes", source: ItemID("t2"), target: .item(F.t1), origin: .property("supersedes")),
        ])
        let (library, source) = try await loaded(F.items + [bug2])
        #expect(library.relationships(for: F.t1).first { $0.field == "inverse:supersedes" }?.allowsMultiple == false)
        // The first bug is already superseded by the second, and can be only once.
        #expect(!library.setItemRelationship(F.e1, field: "supersedes", targetIDs: [F.t1], undoManager: nil))
        #expect(library.failure?.title == String(localized: "Can’t Change This Relationship"))
        #expect(!library.setItemRelationship(F.t1, field: "inverse:supersedes", targetIDs: [F.e1, bug2.id], undoManager: nil))
        // Chosen from the other end, the second bug would give up what it superseded: a replacement, not made yet.
        library.failure = nil
        #expect(!library.setItemRelationship(F.e1, field: "inverse:supersedes", targetIDs: [bug2.id], undoManager: nil))
        #expect(library.failure?.message == String(localized: "Changing this link isn’t available yet in a Marfa library."))
        #expect(source.writes.isEmpty)
    }

    @Test func aRelationshipTheContractRefusesIsToldAndNotSent() async throws {
        let (library, source) = try await loaded()
        let refusals: [(ItemID, String, [ItemID])] = [
            (F.e1, "child-of", [F.t1]),
            (F.e1, "child-of", [F.e1]),
            (F.t1, "child-of", [F.p1, F.p2]),
            (F.e1, "supersedes", [F.n1]),
            (F.e1, "child-of", [F.n3]),
            (F.p1, "inverse:parent-of", [F.p1]),
        ]
        for (id, field, targets) in refusals {
            library.failure = nil
            #expect(!library.setItemRelationship(id, field: field, targetIDs: targets, undoManager: nil), "\(field) \(targets)")
            #expect(library.failure?.title == String(localized: "Can’t Change This Relationship"), "\(field) \(targets)")
        }
        #expect(!library.setItemRelationship(F.f1, field: "about", targetIDs: [F.p1], undoManager: nil))
        #expect(!library.setItemRelationship(F.n1, field: "nothing", targetIDs: [F.p1], undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func whatTheLibraryCannotDoYetIsSaidPlainly() async throws {
        let (library, source) = try await loaded()
        let cases: [(String, () -> Void)] = [
            ("move", { library.move([F.n1], to: nil, undoManager: nil) }),
            ("rename", { library.renameNote(F.n1, to: "X", undoManager: nil) }),
            ("import", { library.importFiles([URL(filePath: "/dev/null")], folderID: nil, requestID: UUID()) }),
            ("new folder", { _ = library.newFolder(undoManager: nil) }),
            ("rename folder", { library.rename(F.n1, to: "X", undoManager: nil) }),
            ("delete folder", { library.deleteFolder(F.n1, undoManager: nil) }),
            ("order folders", { library.moveFolders([F.n1], before: nil, undoManager: nil) }),
        ]
        for (name, act) in cases {
            library.failure = nil
            act()
            #expect(library.failure?.message == MarfaEngine.notYet, "\(name)")
        }
        library.notesToPurge = [F.n3]
        library.failure = nil
        library.deletePermanently([F.n3])
        #expect(library.failure?.title == String(localized: "Can’t Delete Immediately"))
        #expect(library.notesToPurge.isEmpty)
        library.failure = nil
        library.deletePermanentlyOnConfirm([F.n3])
        #expect(library.failure?.title == String(localized: "Can’t Delete Immediately"))
        await #expect(throws: SourceFailure.self) {
            try await library.attach([(name: "a.png", data: Data([1]))], to: F.n1)
        }
        #expect(source.writes.isEmpty)
        #expect(library.folders.isEmpty)
    }

    @Test func aRefusalTheSourceAnswersReachesThePerson() async throws {
        let (library, source) = try await loaded()
        library.setFavorite([F.n2], true, undoManager: nil)
        let write = try #require(source.submitted.first?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "unsupported", message: MarfaEngine.notYet))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.title == String(localized: "Can’t Add to Favorites"))
        #expect(library.failure?.message == MarfaEngine.notYet)

        // A conflict is the item's own state to show, not an alert; an answer told twice is told once.
        library.failure = nil
        source.send(.answered(write, .refused(SyncProblem(code: "again"))))
        library.setFavorite([F.n2], false, undoManager: nil)
        source.send(.answered(try #require(source.submitted.last?.id), .conflicted(sibling: F.n1, fields: ["tags"])))
        source.send(.unavailable(SourceFailure(kind: .failed, message: "The copy can’t be read.")))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.message == "The copy can’t be read.")
    }

    @Test func finishingFlushesTheSource() async throws {
        let (library, source) = try await loaded()
        library.finish()
        #expect(await eventually { source.flushes.withLock { $0 } == 1 })
    }
}

@MainActor
@Suite struct MarfaLibrarySyncTests {
    typealias F = LibraryFixture

    @Test func capabilitiesFollowTheSourceAndTheConnection() async throws {
        let (library, source) = try await loaded()
        #expect(library.capabilities == [.archive])
        #expect(library.connection == .connecting)
        source.offered.withLock { $0 = [.archive, .purge, .move, .folders, .retype] }
        #expect(library.capabilities == [.archive, .retype])
        let watched = observes { _ = library.capabilities }
        source.state.set(.online)
        #expect(await eventually { library.connection == .online })
        #expect(watched.isSet)
        #expect(library.capabilities == [.archive, .retype, .purge])
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        #expect(library.capabilities == [.archive, .retype])
        source.state.set(.keyRefused)
        #expect(await eventually { library.connection == .keyRefused })
        source.state.set(.stopped(code: "x", message: "Stopped."))
        #expect(await eventually { library.connection == .unavailable(message: "Stopped.") })
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

    @Test func eachReadIsToldOfTheChangesThatAlterIt() async throws {
        let (library, source) = try await loaded()
        let list = observes { _ = library.items(in: .favorites) }
        let count = observes { _ = library.count(in: .favorites) }
        let one = observes { _ = library.item(F.n1) }
        let other = observes { _ = library.item(F.p2) }
        let text = observes { _ = library.body(of: F.n1) }
        let relations = observes { _ = library.relationships(for: F.p1) }
        var renamed = try #require(library.item(F.n1))
        renamed.title = "Retitled"
        source.send(.upserted([renamed]))
        #expect(await eventually { list.isSet })
        #expect(one.isSet)
        #expect(relations.isSet)
        // A title is not a place, another item is not this one, and the text did not change.
        #expect(!count.isSet)
        #expect(!other.isSet)
        #expect(!text.isSet)

        let count2 = observes { _ = library.count(in: .favorites) }
        let text2 = observes { _ = library.body(of: F.n1) }
        let gone = observes { _ = library.item(F.p2) }
        let missing = observes { _ = library.item(ItemID("later")) }
        renamed.tags = []
        source.setBody("New text", of: F.n1, version: 2)
        renamed.version = ItemVersion(2)
        source.send(.upserted([renamed]))
        #expect(await eventually { count2.isSet })
        #expect(text2.isSet)
        source.send(.removed([F.p2]))
        #expect(await eventually { gone.isSet })
        source.send(.upserted([F.item(ItemID("later"), F.note, "Later", age: 0)]))
        #expect(await eventually { missing.isSet })

        let search = observes { _ = library.items(matching: "x") }
        source.hits.withLock { $0["x"] = [F.n1] }
        #expect(await eventually { search.isSet })
    }
}

@MainActor
@Suite struct MarfaLibraryPerformanceTests {
    typealias F = LibraryFixture

    /// Three thousand items: a hundred projects of tasks and bugs below them, notes, a tenth favorites, some in
    /// the feed and some in the bin.
    static func large() -> (items: [MAPP.Item], texts: [ItemID: String]) {
        var items: [MAPP.Item] = []
        var texts: [ItemID: String] = [:]
        for index in 0..<3_000 {
            let id = ItemID(String(format: "item-%05d", index))
            let project = ItemID(String(format: "item-%05d", (index / 30) * 30))
            let type = index % 30 == 0 ? F.project : [F.task, F.bug, F.note][index % 3]
            let edges = index % 30 == 0 ? [] : [F.child("edge-\(index)", id, of: project)]
            items.append(F.item(
                id, type, "Item \(index) \(type.rawValue)", age: index,
                state: index % 20 == 19 ? .trashed : .active, tier: index % 50 == 7 ? .feed : .library,
                tags: index % 10 == 0 ? [ItemTag.favorite] : [], edges: edges))
            texts[id] = String(repeating: "Words for item \(index). ", count: 40)
        }
        return (items, texts)
    }

    private func milliseconds(_ work: () -> Void) -> Double {
        let clock = ContinuousClock()
        let elapsed = clock.measure(work)
        return Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
    }

    /// The load waits on a main actor every other test shares, so it is recorded rather than held to a bound; the
    /// reads are timed as the main actor runs them, without a wait.
    @Test func aLargeLibraryReadsInTimeForEachKey() async throws {
        let (items, texts) = Self.large()
        let source = FakeItemSource()
        for (id, text) in texts { source.setBody(text, of: id) }
        let library = MarfaLibrary(source: source)
        let clock = ContinuousClock()
        let start = clock.now
        source.send(.loaded(SourceSnapshot(items: items, catalogue: F.catalogue, places: [])))
        try #require(await eventually(.seconds(30)) { library.isLoaded })
        let load = (clock.now - start)

        let places: [SidebarItem] = [
            .allNotes, .inbox, .favorites, .itemType("aic.ticket"), .project(ItemID("item-00030")), .recentlyDeleted,
        ]
        let cold = milliseconds { for place in places { _ = library.items(in: place) } }
        let warm = milliseconds { for place in places { _ = library.items(in: place) } }
        let counts = milliseconds { for place in places { _ = library.count(in: place) } }

        // A keystroke: one item changes, and the list and the counts are read again.
        var typed = try #require(library.item(ItemID("item-00001")))
        typed.preview = "Typed"
        source.send(.upserted([typed]))
        try #require(await eventually { library.item(ItemID("item-00001"))?.preview == "Typed" })
        let keystroke = milliseconds {
            _ = library.items(in: .allNotes)
            for place in places { _ = library.count(in: place) }
        }

        source.hits.withLock { $0["words"] = items.prefix(500).map(\.id) }
        let searchStart = clock.now
        try #require(await eventually { library.items(matching: "words").count > 400 })
        let search = clock.now - searchStart
        let searchRead = milliseconds { _ = library.items(matching: "words") }

        Attachment.record("""
            MarfaLibrary 3,000 items: load \(load), places cold \(cold) ms, warm \(warm) ms, counts \(counts) ms, \
            keystroke \(keystroke) ms, search \(search), search read \(searchRead) ms
            """, named: "MarfaLibrary performance.txt")
        #expect(library.count(in: .allNotes) == 2_850)
        // The project and its children, less the two of them in the bin.
        #expect(library.count(in: .project(ItemID("item-00030"))) == 28)
        #expect(warm < 1)
        #expect(keystroke < 50)
        #expect(searchRead < 20)
    }
}
