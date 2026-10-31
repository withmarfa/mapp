import Foundation
import Synchronization
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// A file attached to another item shows under that item, not as a row of its own in the lists.
@MainActor
@Suite(.hangLimit) struct AttachedFilesListingTests {
    typealias F = LibraryFixture

    /// A feed note and a library note with a picture each, a picture nothing holds, a picture held by a note in the
    /// bin, and a picture attached to a picture.
    private static let onFeedNote = ItemID("pic-feed"), onLibraryNote = ItemID("pic-library"), alone = ItemID("pic-alone")
    private static let onBinned = ItemID("pic-binned"), onPicture = ItemID("pic-on-pic"), manifest = ItemID("manifest")

    private static func attachment(_ id: ItemID, to parent: ItemID, tier: Tier, type: TypeID = F.image) -> Item {
        F.item(
            id, type, id.rawValue, age: 20, tier: tier,
            edges: [Edge(id: EdgeID("\(id.rawValue)#at"), type: "attached-to", source: id, target: .item(parent), origin: .property("attached-to"))],
            titleRule: .firstLine, content: .file(.png, byteCount: 0))
    }

    private static var items: [Item] {
        F.items + [
            attachment(onFeedNote, to: F.n2, tier: .feed),
            attachment(onLibraryNote, to: F.n1, tier: .library),
            F.item(alone, F.image, "pic-alone", age: 21, tier: .feed, titleRule: .firstLine, content: .file(.png, byteCount: 0)),
            attachment(onBinned, to: F.n3, tier: .feed),
            attachment(onPicture, to: onFeedNote, tier: .feed),
            attachment(manifest, to: F.n2, tier: .feed, type: MarfaMapping.fileType),
        ]
    }

    private static let attached: Set<ItemID> = [onFeedNote, onLibraryNote, onBinned, onPicture, manifest]

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        source.send(.loaded(SourceSnapshot(items: Self.items, catalogue: F.catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func ids(_ place: SidebarItem, in library: MarfaLibrary) -> Set<ItemID> { Set(library.items(in: place).map(\.id)) }

    @Test func theInboxAllItemsAndATypesPlaceLeaveOutAttachedFiles() async throws {
        let (library, _) = try await loaded()
        #expect(ids(.inbox, in: library) == [F.n2, Self.alone])
        #expect(ids(.allNotes, in: library) == [F.p1, F.e1, F.t1, F.n1, F.n2, F.en1, F.f1, F.p2, Self.alone])
        #expect(ids(.itemType("core.image"), in: library) == [F.f1, Self.alone])
        #expect(ids(.itemType("core.file"), in: library).isEmpty)
    }

    @Test func aFileWithNoParentStillShows() async throws {
        let (library, _) = try await loaded()
        #expect(ids(.inbox, in: library).contains(Self.alone))
        #expect(ids(.allNotes, in: library).contains(F.f1))
    }

    @Test func aFileWhoseParentIsInTheBinStaysOutWithIt() async throws {
        let (library, _) = try await loaded()
        #expect(ids(.recentlyDeleted, in: library) == [F.n3])
        #expect(!ids(.inbox, in: library).contains(Self.onBinned))
        #expect(!ids(.allNotes, in: library).contains(Self.onBinned))
    }

    @Test func theFilesPlaceAndTheParentsAttachmentsStillHoldEveryFile() async throws {
        let (library, _) = try await loaded()
        #expect(ids(.files, in: library) == Self.attached.union([F.f1, Self.alone]))
        #expect(Set(library.attachments(of: F.n2)) == [Self.onFeedNote, Self.manifest])
    }

    @Test func countsMatchTheLists() async throws {
        let (library, _) = try await loaded()
        for place in [SidebarItem.inbox, .allNotes, .itemType("core.image"), .itemType("core.file"), .files] {
            #expect(library.count(in: place) == library.items(in: place).count, "\(place)")
        }
    }

    @Test func detachingAFileBringsItBack() async throws {
        let (library, source) = try await loaded()
        #expect(library.count(in: .inbox) == 2)
        var freed = try #require(library.item(Self.onFeedNote))
        freed.edgesOut = []
        source.send(.upserted([freed]))
        #expect(await eventually { ids(.inbox, in: library) == [F.n2, Self.alone, Self.onFeedNote] })
        #expect(library.count(in: .inbox) == 3)

        var attached = try #require(library.item(Self.alone))
        attached.edgesOut = [Edge(id: EdgeID("late"), type: "attached-to", source: Self.alone, target: .item(F.n1), origin: .property("attached-to"))]
        source.send(.upserted([attached]))
        #expect(await eventually { !ids(.inbox, in: library).contains(Self.alone) })
        #expect(library.count(in: .inbox) == 2)
    }

    @Test func searchStillFindsAnAttachedFile() async throws {
        let (library, source) = try await loaded()
        source.hits.withLock { $0["pic"] = [Self.onFeedNote, F.f1] }
        #expect(await eventually { Set(library.search("pic", in: .everywhere).items.map(\.id)) == [Self.onFeedNote, F.f1] })
        #expect(await eventually { Set(library.search("pic", in: .place(.inbox)).items.map(\.id)) == [Self.onFeedNote, F.f1] })
        // The copy is asked about the Inbox by its tier alone, so it does not hide the files.
        let asked = source.targets.withLock { $0 }
        #expect(asked.allSatisfy { target in
            if case .items(_, let filter) = target { filter == nil } else { true }
        })
    }
}
