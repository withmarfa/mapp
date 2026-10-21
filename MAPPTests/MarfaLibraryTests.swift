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

    @Test func anItemTheServersBinHoldsIsListedAndRecoveredLikeAnyOther() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        library.delete([F.n1], undoManager: undo)
        // The server took the delete and the copy let the row go; the source still lists it, as the bin holds it.
        var binned = try #require(library.item(F.n1))
        binned.state = .trashed
        source.send(.upserted([binned]))
        #expect(await eventually { library.items(in: .recentlyDeleted).contains { $0.id == F.n1 } })
        #expect(library.count(in: .recentlyDeleted) == 2)
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.transition(F.n1, .active)])
        #expect(library.failure == nil)

        // A restore the server refuses is told in the server's own words.
        library.recover([F.n3], undoManager: nil)
        let restore = try #require(source.submitted.last?.id)
        source.send(.answered(restore, .refused(SyncProblem(code: "item_not_found", message: "The server doesn’t hold this item."))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.title == String(localized: "Can’t Recover"))
        #expect(library.failure?.message == "The server doesn’t hold this item.")
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
        source.offered.withLock { $0 = [.archive, .purge] }
        source.state.set(.online)
        #expect(await eventually { library.capabilities.contains(.purge) })
        var binned = try #require(library.item(F.n3))
        binned.version = ItemVersion(9)
        source.send(.upserted([binned]))
        #expect(await eventually { library.item(F.n3)?.version == ItemVersion(9) })
        library.notesToPurge = [F.n3, F.n1]
        library.deletePermanentlyOnConfirm([F.n3, F.n1])
        // An item not in the bin is only moved there, never destroyed.
        #expect(source.writes == [.purge(F.n3, version: ItemVersion(9))])
        #expect(library.notesToPurge.isEmpty)

        let purge = try #require(source.submitted.last?.id)
        source.send(.answered(purge, .refused(SyncProblem(code: "version_conflict", message: "The item changed after you saw it."))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.title == String(localized: "Can’t Delete Immediately"))
        #expect(library.failure?.message == "The item changed after you saw it.")
    }

    @Test func deletingForGoodWaitsForTheServer() async throws {
        let (library, source) = try await loaded()
        source.offered.withLock { $0 = [.archive, .purge] }
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        #expect(!library.capabilities.contains(.purge))
        library.deletePermanentlyOnConfirm([F.n3])
        #expect(source.writes.isEmpty)
        #expect(library.failure?.title == String(localized: "Can’t Delete Immediately"))
        library.failure = nil
        library.deletePermanently([F.n3])
        #expect(source.writes.isEmpty)
        #expect(library.failure?.title == String(localized: "Can’t Delete Immediately"))
    }

    @Test func aLinkIsAddedRemovedAndReplacedByAMove() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        // A new parent replaces the one link a child holds: one move of the edge's source, which keeps its id.
        undo.beginUndoGrouping()
        #expect(library.setItemRelationship(F.t1, field: "child-of", targetIDs: [F.p1], undoManager: undo))
        undo.endUndoGrouping()
        #expect(source.writes == [.moveEdge(EdgeID("c2"), end: .source, to: F.p1)])
        #expect(library.failure == nil)
        // The undo moves it back, to the parent it had.
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.moveEdge(EdgeID("c2"), end: .source, to: F.e1)])
        undo.redo()
        #expect(source.writes.last == .moveEdge(EdgeID("c2"), end: .source, to: F.p1))

        // A child chosen under a project from the project's side is taken from the parent it has, in one move.
        source.clearWrites()
        undo.beginUndoGrouping()
        #expect(library.setItemRelationship(F.p2, field: "inverse:parent-of", targetIDs: [F.e1], undoManager: undo))
        undo.endUndoGrouping()
        #expect(source.writes == [.moveEdge(EdgeID("c1"), end: .source, to: F.p2)])
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [.moveEdge(EdgeID("c1"), end: .source, to: F.p1)])
        #expect(library.failure == nil)
        source.clearWrites()

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
        #expect(!library.setItemRelationship(F.t1, field: "inverse:supersedes", targetIDs: [F.e1, bug2.id], undoManager: nil))
        #expect(library.failure?.message == String(localized: "Only one item can be chosen here."))
        #expect(source.writes.isEmpty)

        // The first bug is already superseded by the second. That link is the second bug's own, so the task does
        // not take it: the person is told which item holds it, and nothing is sent.
        library.failure = nil
        #expect(!library.setItemRelationship(F.e1, field: "supersedes", targetIDs: [F.t1], undoManager: nil))
        #expect(library.failure?.message
            == String(localized: "“\("Bug two")” already holds this link to “\("Bug one")”. Remove it there first."))
        #expect(source.writes.isEmpty)
        #expect(library.relationships(for: F.t1).first { $0.field == "inverse:supersedes" }?.targets.map(\.itemID) == [bug2.id])
        // Chosen from the other end, the second bug's own link changes from the first bug to the task: the edge's
        // target moves.
        library.failure = nil
        #expect(library.setItemRelationship(F.e1, field: "inverse:supersedes", targetIDs: [bug2.id], undoManager: nil))
        #expect(source.writes == [.moveEdge(EdgeID("s1"), end: .target, to: F.e1)])
        #expect(library.failure == nil)
    }

    /// Both ends hold one link of their type, so the one move cannot also free the end it takes from.
    @Test func aMoveThatNeedsTwoEdgesToChangeIsToldAndNotSent() async throws {
        func bug(_ id: String, supersedes target: ItemID? = nil, edge: String = "") -> MAPP.Item {
            F.item(ItemID(id), F.bug, "Bug \(id)", age: 0, edges: target.map {
                [Edge(id: EdgeID(edge), type: "supersedes", source: ItemID(id), target: .item($0), origin: .property("supersedes"))]
            } ?? [])
        }
        let (library, source) = try await loaded(F.items + [bug("a"), bug("b"), bug("c", supersedes: ItemID("a"), edge: "s1"),
            bug("d", supersedes: ItemID("b"), edge: "s2")])
        // `a`, superseded by `c`, would be superseded by `d` instead, which supersedes `b`: two edges would change.
        #expect(!library.setItemRelationship(ItemID("a"), field: "inverse:supersedes", targetIDs: [ItemID("d")], undoManager: nil))
        #expect(library.failure?.message
            == String(localized: "Both items already hold a link of this kind, so one can’t take the other’s."))
        #expect(source.writes.isEmpty)
        // From `c`'s own side, `b` is held by `d` as its own link, which is never taken from it.
        library.failure = nil
        #expect(!library.setItemRelationship(ItemID("c"), field: "supersedes", targetIDs: [ItemID("b")], undoManager: nil))
        #expect(library.failure?.message
            == String(localized: "“\("Bug d")” already holds this link to “\("Bug b")”. Remove it there first."))
        #expect(source.writes.isEmpty)
        // Replacing its own link for an item that holds none is one move of the end that goes.
        library.failure = nil
        #expect(library.setItemRelationship(ItemID("c"), field: "supersedes", targetIDs: [F.t1], undoManager: nil))
        #expect(source.writes == [.moveEdge(EdgeID("s1"), end: .target, to: F.t1)])
    }

    /// A refusal that turns on rows the copy may not hold, such as a longer cycle, is the server's: it is told in the
    /// server's words, and the link stays where it was.
    @Test func aMoveTheServerRefusesIsToldAndLeavesTheOldLink() async throws {
        let (library, source) = try await loaded()
        library.setItemRelationship(F.t1, field: "child-of", targetIDs: [F.p1], undoManager: nil)
        let move = try #require(source.submitted.last?.id)
        source.send(.answered(move, .refused(SyncProblem(code: "edge_cycle", message: "That would close a cycle."))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.title == String(localized: "Can’t Change This Relationship"))
        #expect(library.failure?.message == "That would close a cycle.")
        #expect(library.relationships(for: F.t1).first { $0.field == "child-of" }?.targets.map(\.itemID) == [F.e1])
        #expect(source.writes.count == 1)
    }

    /// The contract's cycle rule is kept before anything is sent, and a move that would close one leaves the old link.
    @Test func aMoveThatWouldCloseACycleIsToldAndLeavesTheOldLink() async throws {
        let (library, source) = try await loaded()
        let cycle = String(localized: "This would link the item back to itself through the items between them.")
        // The task's child is below it, so it cannot become the task's parent.
        #expect(!library.setItemRelationship(F.e1, field: "child-of", targetIDs: [F.t1], undoManager: nil))
        #expect(library.failure?.message == cycle)
        // Nor can the project take its own grandchild as its parent from the other end.
        library.failure = nil
        #expect(!library.setItemRelationship(F.t1, field: "inverse:parent-of", targetIDs: [F.p1], undoManager: nil))
        #expect(library.failure?.message == cycle)
        #expect(source.writes.isEmpty)
        #expect(library.relationships(for: F.e1).first { $0.field == "child-of" }?.targets.map(\.itemID) == [F.p1])
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

    @Test func whatOnlyFilesDoIsSaidPlainly() async throws {
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
            #expect(library.failure?.message == MarfaEngine.filesOnly, "\(name)")
        }
        #expect(!library.capabilities.contains(.importFiles))
        #expect(!library.capabilities.contains(.move))
        #expect(source.writes.isEmpty)
        #expect(library.folders.isEmpty)
    }

    @Test func attachedFilesGoToTheSourceAndTheTextItGivesIsWhatThePageWrites() async throws {
        let (library, source) = try await loaded()
        let embeds = try await library.attach(
            [(name: "a.png", data: Data([1])), (name: "b.png", data: Data([2]))], to: F.n1)
        #expect(embeds.map(\.name) == ["a.png", "b.png"])
        #expect(embeds.map(\.link) == ["a.png", "b.png"])
        #expect(source.attaching.attached.withLock { $0.map(\.item) } == [F.n1, F.n1])
        #expect(source.writes.isEmpty)

        source.attaching.failure.withLock { $0 = SourceFailure(kind: .failed, message: "The file can’t be written into the text.") }
        await #expect(throws: SourceFailure.self) {
            try await library.attach([(name: "c.png", data: Data([3]))], to: F.n1)
        }
    }

    @Test func aRefusalTheSourceAnswersReachesThePerson() async throws {
        let (library, source) = try await loaded()
        library.setFavorite([F.n2], true, undoManager: nil)
        let write = try #require(source.submitted.first?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "unsupported", message: MarfaEngine.filesOnly))))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.title == String(localized: "Can’t Add to Favorites"))
        #expect(library.failure?.message == MarfaEngine.filesOnly)

        // A conflict is the item's own state to show, not an alert; an answer told twice is told once.
        library.failure = nil
        source.send(.answered(write, .refused(SyncProblem(code: "again"))))
        library.setFavorite([F.n2], false, undoManager: nil)
        source.send(.answered(try #require(source.submitted.last?.id), .conflicted(sibling: F.n1, fields: ["tags"])))
        source.send(.unavailable(SourceFailure(kind: .failed, message: "The copy can’t be read.")))
        #expect(await eventually { library.failure != nil })
        #expect(library.failure?.message == "The copy can’t be read.")
    }

    /// Finishing waits until the source has queued every write, and not for the server, so quitting offline is
    /// not held up and quitting at once loses nothing.
    @Test func finishingWaitsUntilTheSourceHasQueuedEveryWriteButNotForTheServer() async throws {
        let (library, source) = try await loaded()
        source.queuing.withLock { $0 = true }
        let finished = Task { await library.finish() }
        try await Task.sleep(for: .milliseconds(100))
        #expect(source.queues.withLock { $0 } == 0, "finishing returned before the source had queued its writes")
        source.queuing.withLock { $0 = false }
        await finished.value
        #expect(source.queues.withLock { $0 } == 1)
    }
}

@MainActor
@Suite struct MarfaLibrarySyncTests {
    typealias F = LibraryFixture

    @Test func capabilitiesFollowTheSourceAndTheConnection() async throws {
        let (library, source) = try await loaded()
        #expect(library.capabilities == [.archive])
        #expect(library.connection == .connecting)
        source.offered.withLock { $0 = [.archive, .purge, .move, .folders, .retype, .retier, .importFiles] }
        #expect(library.capabilities == [.archive, .retype, .retier])
        let watched = observes { _ = library.capabilities }
        source.state.set(.online)
        #expect(await eventually { library.connection == .online })
        #expect(watched.isSet)
        #expect(library.capabilities == [.archive, .retype, .retier, .purge])
        source.state.set(.offline(reason: "network"))
        #expect(await eventually { library.connection == .offline(reason: "network") })
        #expect(library.capabilities == [.archive, .retype, .retier])
        source.state.set(.signedOut)
        #expect(await eventually { library.connection == .signedOut })
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

/// What an item's text links and embeds: the package writes each as an edge when the text is saved, so the items
/// at both ends show it.
@MainActor
@Suite struct MarfaLibraryTextEdgeTests {
    typealias F = LibraryFixture

    private static var catalogue: Catalogue {
        var catalogue = F.catalogue
        catalogue.edgeTypes["attached-to"] = EdgeTypeInfo(
            id: "attached-to", label: "Attached to", reverseName: nil, cardinality: .many, writtenAt: .source,
            sourceTypes: [MarfaMapping.fileType], targetTypes: [])
        return catalogue
    }

    private static func loaded() async throws -> MarfaLibrary {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source)
        var items = F.items
        func replace(_ id: ItemID, _ change: (inout MAPP.Item) -> Void) {
            if let position = items.firstIndex(where: { $0.id == id }) { change(&items[position]) }
        }
        replace(F.n1) { note in
            note.edgesOut += [
                Edge(id: EdgeID("n1#references#1"), type: "references", source: F.n1, target: .pending(spelling: "Later"), origin: .body),
                Edge(id: EdgeID("n1#references#2"), type: "references", source: F.n1, target: .unresolved(spelling: "Nowhere", ambiguous: false), origin: .body),
                Edge(id: EdgeID("n1#references#3"), type: "references", source: F.n1, target: .unresolved(spelling: "Twin", ambiguous: true), origin: .body),
                Edge(id: EdgeID("n1#references#4"), type: "references", source: F.n1, target: .refused(spelling: "Banned", reason: "forbidden"), origin: .body),
            ]
        }
        replace(F.f1) { file in
            file.edgesOut = [Edge(id: EdgeID("at1"), type: "attached-to", source: F.f1, target: .item(F.n1), origin: .property("attached-to"))]
        }
        source.send(.loaded(SourceSnapshot(items: items, catalogue: catalogue, places: [])))
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
        #expect(linked.label == "Linked From")
        #expect(linked.targets.map(\.itemID) == [F.n1])
        #expect(!linked.isEditable)
        #expect(!library.setItemRelationship(F.t1, field: "inverse:references", targetIDs: [], undoManager: nil))
    }

    @Test func anEmbeddedFileShowsAtBothEndsOfItsAttachment() async throws {
        let library = try await Self.loaded()
        let attachments = try #require(library.relationships(for: F.n1).first { $0.field == "inverse:attached-to" })
        #expect(attachments.label == "Attachments")
        #expect(attachments.targets.map(\.itemID) == [F.f1])
        let attachedTo = try #require(library.relationships(for: F.f1).first { $0.field == "attached-to" })
        #expect(attachedTo.targets.map(\.itemID) == [F.n1])
    }
}

/// The connect review's findings for the Marfa library, each failing on the code before its fix.
@MainActor
@Suite struct MarfaLibraryConnectReviewTests {
    /// A create refused before it was queued, as one made while the copy is brought up to date, has no problem in
    /// the queue to show; the library says so, and the window's draft is given back to edit and send again.
    @Test func aCreateRefusedBeforeItIsQueuedGivesTheDraftBackAndSaysWhy() async throws {
        let (library, source) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        browser.startItemDraft()
        browser.itemDraft?.title = "Trip"
        browser.itemDraft?.body = "Book the hotel"
        let id = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(browser.isAwaitingCreation)

        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "hydration_incomplete", message: MarfaEngine.notCurrent))))
        #expect(await eventually { library.wasRefused(creating: id) })
        #expect(browser.isCreationSettled(in: library))
        browser.finishCreation(in: library)

        #expect(!browser.isAwaitingCreation, "the draft can be edited and sent again")
        #expect(browser.isCreatingItem)
        #expect(browser.itemDraft?.title == "Trip")
        #expect(browser.itemDraft?.body == "Book the hotel")
        #expect(library.failure?.title == "Can’t Create Item")
        #expect(library.failure?.message == MarfaEngine.notCurrent)

        let again = try #require(browser.createDraft(in: library, undoManager: nil))
        #expect(again != id, "a second Return sends the draft again rather than naming the refused item")
    }

    /// A refused create whose draft was carried to another library is kept there, since no queue holds its text.
    @Test func aRefusedCreateIsCarriedToTheNextLibrary() async throws {
        let (library, source) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        browser.startItemDraft()
        browser.itemDraft?.title = "Trip"
        _ = try #require(browser.createDraft(in: library, undoManager: nil))
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "invalid", message: "No."))))
        #expect(await eventually { library.failure != nil })

        browser.adopt(FakeItemLibrary())
        #expect(browser.itemDraft?.title == "Trip")
        #expect(browser.isCreatingItem)
    }

    /// A write made after the source closed is kept nowhere, so the person is told rather than left to find it gone.
    @Test func aWriteMadeAfterTheSourceClosedSaysItWasNotKept() async throws {
        let (library, source) = try await loaded()
        await source.close()
        library.setFavorite([LibraryFixture.n1], false, undoManager: nil)
        #expect(library.failure?.message == MarfaEngine.notKept)
        #expect(source.submitted.isEmpty)
    }

    /// A page that hands over its text after the source closed, as one leaving while the copy opens again does,
    /// gives the text to the app to tell, since the windows read another library by then.
    @Test func textAClosedSourceWillNotTakeGoesToTheAppWithTheText() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        await source.close()
        library.updateBody(of: LibraryFixture.n1, to: "Typed while signing in again")
        #expect(told.map(\.text) == ["Typed while signing in again"])
        #expect(library.failure == nil, "this library is shown nowhere, so it is not told here")
    }

    /// Text submitted just before the source closed is refused by it as it closes, and goes to the app too.
    @Test func textRefusedAsTheSourceClosesGoesToTheAppWithTheText() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        library.updateBody(of: LibraryFixture.n1, to: "Typed as it closed")
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: MarfaEngine.closedCode, message: MarfaEngine.notKept))))
        #expect(await eventually { !told.isEmpty })
        #expect(told.map(\.text) == ["Typed as it closed"])
    }

    /// A save that arrives after the row can no longer be written reaches nothing, so the person is told and the text
    /// goes where they can get it back.
    @Test func textTypedOverAnItemThatCannotBeWrittenIsGivenBack() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        var damaged = try #require(library.item(LibraryFixture.n1))
        damaged.problem = ItemProblem(message: "Damaged", withholdsText: true)
        source.send(.upserted([damaged]))
        try #require(await eventually { library.item(LibraryFixture.n1)?.problem != nil })

        library.updateBody(of: LibraryFixture.n1, to: "Typed as the row turned unreadable")
        #expect(told.map(\.text) == ["Typed as the row turned unreadable"])
        #expect(told.first?.reason == MarfaLibrary.cantChange)
        #expect(source.writes.isEmpty)
    }

    @Test func textThatChangesNothingIsNotTold() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        var damaged = try #require(library.item(LibraryFixture.n1))
        damaged.problem = ItemProblem(message: "Damaged", withholdsText: true)
        source.send(.upserted([damaged]))
        try #require(await eventually { library.item(LibraryFixture.n1)?.problem != nil })
        let held = try #require(library.body(of: LibraryFixture.n1)?.text)

        library.updateBody(of: LibraryFixture.n1, to: held)
        library.updateBody(of: ItemID("nowhere"), to: "Nobody's")
        #expect(told.isEmpty)
    }

    /// A text save the package refused before queueing it is in no queue, so the typed text is given back with the
    /// reason, in place of an alert the page then replaces with the server's text.
    @Test func textRefusedBeforeItWasQueuedIsGivenBackWithTheReason() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        library.updateBody(of: LibraryFixture.n1, to: "Typed while the copy was brought up to date")
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "copy_expired", message: "Try again in a moment.", notQueued: true))))
        #expect(await eventually { !told.isEmpty })
        #expect(told.map(\.text) == ["Typed while the copy was brought up to date"])
        #expect(told.first?.reason == "Try again in a moment.")
        #expect(library.failure == nil, "the person is told once")
    }

    /// A text save the server refused is in the queue, listed with its text, so it is told as it was.
    @Test func textTheServerRefusedStaysInTheQueueAndIsToldAsAFailure() async throws {
        let (library, source) = try await loaded()
        var told: [MarfaLibrary.NotKept] = []
        library.onNotKept = { told.append($0) }
        library.updateBody(of: LibraryFixture.n1, to: "Refused later")
        let write = try #require(source.submitted.last?.id)
        source.send(.answered(write, .refused(SyncProblem(code: "validation_error", message: "Too long."))))
        #expect(await eventually { library.failure != nil })
        #expect(told.isEmpty)
    }
}
