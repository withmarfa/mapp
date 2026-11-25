import Foundation
import Synchronization
import Testing
@testable import MarfaMac

/// Collections as Marfa keeps them: items whose type plays the `container` role, holding members through
/// `in-collection` edges from each member.
@MainActor
@Suite(.hangLimit) struct MarfaCollectionsTests {
    typealias F = LibraryFixture

    static let holiday = ItemID("al1"), archive = ItemID("al2"), oldAlbum = ItemID("al3")

    /// The copy takes every write sent so far, as the engine does once it has judged and queued each.
    private func takeAll(_ library: MarfaLibrary, _ source: FakeItemSource) async throws {
        for write in source.submitted { source.send(.taken(write.id)) }
        try #require(await eventually { library.linkSteps.values.allSatisfy { $0.judging.isEmpty } })
    }

    static func member(_ edge: String, _ member: ItemID, of collection: ItemID, at position: Double? = nil) -> Edge {
        Edge(
            id: EdgeID(edge), type: "in-collection", from: member, to: .item(collection),
            origin: .property("in-collection"), position: position)
    }

    /// The fixture with three albums: Holiday holds Plain note at 2, Alpha at 1 and Bug one with no position;
    /// Archive holds Beta and Ada with none; a third album is in the bin.
    static var items: [Item] {
        F.items.map { item in
            var item = item
            switch item.id {
            case F.n1: item.edgesOut.append(member("m1", F.n1, of: holiday, at: 2))
            case F.p1: item.edgesOut.append(member("m2", F.p1, of: holiday, at: 1))
            case F.t1: item.edgesOut.append(member("m3", F.t1, of: holiday))
            case F.p2: item.edgesOut.append(member("m4", F.p2, of: archive))
            case F.en1: item.edgesOut.append(member("m5", F.en1, of: archive))
            default: break
            }
            return item
        } + [
            F.item(holiday, F.album, "Holiday", age: 0),
            F.item(archive, F.album, "Archive", age: 0),
            F.item(oldAlbum, F.album, "Old album", age: 0, state: .trashed),
        ]
    }

    func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: Self.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    @Test func addingWritesOneEdgeAfterTheLastPosition() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.addToCollection([F.e1, F.n2, F.n1], Self.holiday, undoManager: undo))
        undo.endUndoGrouping()
        // Plain note is in Holiday already. The others follow position 2, by title.
        #expect(source.writes == [
            .link(EdgeDraft(type: "in-collection", from: F.e1, to: Self.holiday, position: 3)),
            .link(EdgeDraft(type: "in-collection", from: F.n2, to: Self.holiday, position: 4)),
        ])
        #expect(library.notices.waiting.isEmpty)
    }

    @Test func addingToACollectionIsOneUndoStepThatUnlinksOnlyWhatJoined() async throws {
        let (library, source) = try await loaded()
        let undo = StepCountingUndoManager()
        // Plain note is in Holiday already and Archive is a collection, so only the other two join.
        #expect(library.addToCollection([F.e1, F.n2, F.n1, Self.archive], Self.holiday, undoManager: undo))
        #expect(undo.steps == 1)
        let joined = source.writes.compactMap { write -> ItemID? in if case .link(let draft) = write { draft.from } else { nil } }
        #expect(Set(joined) == [F.e1, F.n2])
        // Each new edge carries the id the library gave it, which the source keeps and the undo then removes.
        let minted = source.submitted.compactMap { sent -> Edge? in
            guard case .link(let draft) = sent.write, let id = draft.id else { return nil }
            return Self.member(id.rawValue, draft.from, of: Self.holiday)
        }
        try await takeAll(library, source)
        for edge in minted {
            var item = try #require(library.item(edge.from))
            item.edgesOut.append(edge)
            source.send(.upserted([item]))
        }
        #expect(await eventually { Set(library.items(in: .collection(Self.holiday)).map(\.id)).isSuperset(of: [F.e1, F.n2]) })
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == Set(minted.map { .unlink(EdgeDraft(type: "in-collection", from: $0.from, to: Self.holiday, id: $0.id)) }))
        #expect(!undo.canUndo)
    }

    @Test func aDropOnACollectionAddsOnlyMissingMembershipsInOneUndoStep() async throws {
        let (library, source) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        // Plain note is in Holiday already, so only the other two join.
        #expect(browser.addDropped([F.e1, F.n2, F.n1], to: Self.holiday, in: library, undoManager: undo, toasts: toasts))
        let joined = source.writes.compactMap { write -> ItemID? in if case .link(let draft) = write { draft.from } else { nil } }
        #expect(Set(joined) == [F.e1, F.n2])
        #expect(joined.count == 2)
        #expect(toasts.current?.message == "Added 2 items to Holiday, 1 already in it")
        #expect(toasts.current?.undo != nil)
        try await takeAll(library, source)
        source.clearWrites()
        toasts.undo()
        #expect(source.writes.count == 2)
        #expect(!undo.canUndo)
    }

    /// What a source that refuses an edge write on an item in the bin would refuse among `writes`, given the items
    /// already there. The test source applies nothing, so this follows the writes in the order they were sent.
    private static func refusedForBinned(_ writes: [ItemWrite], binned: Set<ItemID> = []) -> [ItemWrite] {
        var binned = binned
        var refused: [ItemWrite] = []
        for write in writes {
            switch write {
            case .transition(let id, .trashed, _): binned.insert(id)
            case .restore(let id): binned.remove(id)
            case .link(let draft), .unlink(let draft): if binned.contains(draft.from) { refused.append(write) }
            default: break
            }
        }
        return refused
    }

    @Test func undoingAFileDropOnACollectionUnlinksBeforeItBinsAndRedoRestoresBeforeItLinks() async throws {
        let (library, source) = try await loaded()
        let dropped = ItemID("dropped")
        source.attaching.made.withLock { $0 = [dropped] }
        source.send(.upserted([F.item(dropped, F.note, "a.txt", age: 0)]))
        try #require(await eventually { library.item(dropped) != nil })
        let browser = Browser()
        browser.adopt(library)
        let undo = UndoManager()
        undo.groupsByEvent = false
        let target = browser.fileDropTarget(onCollection: Self.holiday, in: library)
        await browser.importFiles(
            [TestFiles().url("a.txt")], to: target, in: library, order: ItemOrder(), undoManager: undo)
        try #require(source.writes.count == 1)
        guard case .link = source.writes[0] else {
            Issue.record("The drop wrote no link.")
            return
        }
        let minted = try #require(source.lastMintedEdge)
        try await takeAll(library, source)
        var item = try #require(library.item(dropped))
        item.edgesOut.append(Self.member(minted.rawValue, dropped, of: Self.holiday))
        source.send(.upserted([item]))
        try #require(await eventually { library.item(dropped)?.collectionIDs.contains(Self.holiday) == true })
        source.clearWrites()

        undo.undo()
        let undone = source.writes
        guard undone.count == 2, case .unlink = undone[0], case .transition(dropped, .trashed, _) = undone[1] else {
            Issue.record("Undo wrote \(undone), not an unlink then a move to Recently Deleted.")
            return
        }
        #expect(Self.refusedForBinned(undone).isEmpty)

        try await takeAll(library, source)
        let binWrite = try #require(source.submitted.last?.id)
        var binned = try #require(library.item(dropped))
        binned.state = .trashed
        binned.edgesOut = []
        source.send(.upserted([binned]))
        try #require(await eventually { library.item(dropped)?.state == .trashed })
        source.send(.answered(binWrite, .accepted))
        try #require(await eventually { library.stateJudging[binWrite] == nil })
        source.clearWrites()

        undo.redo()
        let redone = source.writes
        guard redone.count == 2, case .restore(dropped) = redone[0], case .link = redone[1] else {
            Issue.record("Redo wrote \(redone), not a restore then a link.")
            return
        }
        #expect(Self.refusedForBinned(redone, binned: [dropped]).isEmpty)
    }

    @Test func aDropOfItemsAlreadyInTheCollectionWritesNothingAndSaysSo() async throws {
        let (library, source) = try await loaded()
        let browser = Browser()
        browser.adopt(library)
        let toasts = ToastPresenter()
        let undo = UndoManager()
        undo.groupsByEvent = false
        #expect(browser.addDropped([F.n1, F.p1], to: Self.holiday, in: library, undoManager: undo, toasts: toasts))
        #expect(source.writes.isEmpty)
        #expect(undo.canUndo == false)
        #expect(toasts.current?.message == "2 items already in Holiday")
        #expect(toasts.current?.undo == nil)
    }

    @Test func removingFromACollectionIsOneUndoStepThatPutsBackOnlyWhatLeft() async throws {
        let (library, source) = try await loaded()
        let undo = StepCountingUndoManager()
        #expect(library.removeFromCollection([F.n1, F.p1, F.e1], Self.holiday, undoManager: undo))
        #expect(undo.steps == 1)
        #expect(Set(source.writes) == [
            .unlink(EdgeDraft(type: "in-collection", from: F.n1, to: Self.holiday, id: EdgeID("m1"))),
            .unlink(EdgeDraft(type: "in-collection", from: F.p1, to: Self.holiday, id: EdgeID("m2"))),
        ], "e1 is in no collection, so nothing is sent for it")
        try await takeAll(library, source)
        source.clearWrites()
        undo.undo()
        #expect(Set(source.writes) == [
            .link(EdgeDraft(type: "in-collection", from: F.n1, to: Self.holiday, position: 2)),
            .link(EdgeDraft(type: "in-collection", from: F.p1, to: Self.holiday, position: 1)),
        ])
        #expect(!undo.canUndo)
    }

    @Test func addingToACollectionWithNoPositionsSetsNone() async throws {
        let (library, source) = try await loaded()
        #expect(library.addToCollection([F.e1], Self.archive, undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "in-collection", from: F.e1, to: Self.archive))])
    }

    @Test func removingUnlinksAndAnUndoPutsThePositionBack() async throws {
        let (library, source) = try await loaded()
        let undo = UndoManager()
        undo.groupsByEvent = false
        undo.beginUndoGrouping()
        #expect(library.removeFromCollection([F.n1, F.e1], Self.holiday, undoManager: undo))
        undo.endUndoGrouping()
        #expect(source.writes == [.unlink(EdgeDraft(type: "in-collection", from: F.n1, to: Self.holiday, id: EdgeID("m1")))])
        try await takeAll(library, source)
        source.clearWrites()
        undo.undo()
        #expect(source.writes == [
            .link(EdgeDraft(type: "in-collection", from: F.n1, to: Self.holiday, position: 2)),
        ])
        // An item in no collection has nothing to remove.
        source.clearWrites()
        #expect(!library.removeFromCollection([F.e1], Self.holiday, undoManager: nil))
        #expect(source.writes.isEmpty)
    }

    @Test func aCollectionCantBeAMember() async throws {
        let (library, source) = try await loaded()
        #expect(!library.canJoinCollection(try #require(library.item(Self.archive))))
        #expect(library.canJoinCollection(try #require(library.item(F.e1))))
        #expect(library.canJoinCollection(try #require(library.item(F.f1))))
        // A collection among the items is skipped and told; the rest are filed.
        #expect(library.addToCollection([F.e1, Self.archive], Self.holiday, undoManager: nil))
        #expect(source.writes.count == 1)
        #expect(library.notices.waiting.last?.title == String(localized: "Some Items Were Skipped"))
        #expect(library.notices.waiting.last?.message == BatchSkips.sentence(.isCollection, count: 1))
        #expect(!library.addToCollection([Self.archive], Self.holiday, undoManager: nil))
        #expect(source.writes.count == 1)
        #expect(library.notices.waiting.last?.title == String(localized: "Can’t Add to Collection"))
        // Nor is one offered as a collection for another, or written through the item's own relationship.
        #expect(library.relationshipCandidates(for: Self.archive, field: "in-collection").isEmpty)
        #expect(!library.relationships(for: Self.archive).contains { $0.field == "in-collection" && $0.isEditable })
    }

    @Test func onlyACollectionInTheLibraryTakesMembers() async throws {
        let (library, source) = try await loaded()
        #expect(!library.addToCollection([F.e1], F.p1, undoManager: nil))
        #expect(!library.addToCollection([F.e1], Self.oldAlbum, undoManager: nil))
        #expect(source.writes.isEmpty)
        #expect(library.notices.waiting.last?.message == String(localized: "This collection isn’t in the library."))
    }

    /// An archived collection takes members and is offered for one, since Marfa links an archived item as any other.
    /// One in the bin is neither.
    @Test func anArchivedCollectionTakesMembersAndIsOffered() async throws {
        let (library, source) = try await loaded()
        source.send(.upserted([F.item(Self.holiday, F.album, "Holiday", age: 0, state: .archived)]))
        try #require(await eventually { library.item(Self.holiday)?.state == .archived })
        #expect(Set(library.relationshipCandidates(for: F.e1, field: "in-collection").map(\.id)) == [Self.holiday, Self.archive])
        #expect(library.joinableCollections.map(\.id).contains(Self.holiday))
        #expect(!library.collections.map(\.id).contains(Self.holiday))
        #expect(library.addToCollection([F.e1], Self.holiday, undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "in-collection", from: F.e1, to: Self.holiday, position: 3))])
    }

    /// The collection commands take the whole selection, files too, never only its notes, and leave out what
    /// can't be a member.
    @Test func theCollectionCommandsTakeFilesAndLeaveOutCollections() async throws {
        let (library, source) = try await loaded()
        #expect(library.collectionMembers([F.f1]) == [F.f1])
        #expect(library.collectionMembers([F.n1, F.f1]) == [F.n1, F.f1])
        #expect(library.collectionMembers([F.n1, Self.holiday]) == [F.n1])
        #expect(library.collectionMembers([Self.archive, Self.oldAlbum]).isEmpty)
        #expect(library.addToCollection(library.collectionMembers([F.f1, Self.archive]), Self.holiday, undoManager: nil))
        #expect(source.writes == [.link(EdgeDraft(type: "in-collection", from: F.f1, to: Self.holiday, position: 3))])
    }

    @Test func noCatalogueContainerMeansNoCollections() async throws {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        let catalogue = Catalogue(itemTypes: Array(F.catalogue.itemTypes.values.filter { $0.id != F.album }), edgeTypes: [])
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        #expect(library.collections.isEmpty)
        #expect(!library.canJoinCollection(try #require(library.item(F.n1))))
    }
}
