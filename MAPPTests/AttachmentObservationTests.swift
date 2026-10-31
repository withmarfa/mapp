import Foundation
import Observation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// An item's page reads its attachments to choose its layout, so that read follows the item's links and its attached
/// files: an edit to another item that changes no link does not draw every page again.
@MainActor
@Suite(.hangLimit) struct AttachmentObservationTests {
    private typealias F = LibraryFixture
    private static let media = TypeID("core.media")
    private static let article = ItemID("article")

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        var catalogue = F.catalogue
        catalogue.itemTypes[Self.media] = ItemTypeInfo(
            id: Self.media, label: "Media", fields: [], titleField: nil, bodyField: nil, parent: nil)
        catalogue.edgeTypes[MarfaMapping.attachmentEdge] = EdgeTypeInfo(
            id: MarfaMapping.attachmentEdge, label: "Attached to", reverseLabel: "Attachments", reverseName: nil, cardinality: .many,
            writtenAt: .source, sourceTypes: [MarfaMapping.fileType], targetTypes: [])
        source.send(.loaded(SourceSnapshot(items: F.items + [F.item(Self.article, Self.media, "An article", age: 0)], catalogue: catalogue)))
        try #require(await eventually { library.isLoaded })
        return (library, source)
    }

    private func observes(_ read: () -> Void) -> LiveMarfa.Flag {
        let flag = LiveMarfa.Flag()
        withObservationTracking(read) { flag.set() }
        return flag
    }

    private func document(_ id: ItemID, attachedTo host: ItemID, state: ItemState = .active) -> MAPP.Item {
        F.item(
            id, MarfaMapping.fileType, "article.html", age: 0, state: state,
            edges: [Edge(id: EdgeID("at-\(id.rawValue)"), type: MarfaMapping.attachmentEdge, source: id, target: .item(host), origin: .property(MarfaMapping.attachmentEdge))],
            titleRule: .firstLine,
            content: .file(.html, byteCount: 10))
    }

    @Test func aPageLayoutFollowsTheItemsAttachmentsAndNothingElse() async throws {
        let (library, source) = try await loaded()
        let note = try #require(library.item(Self.article))
        #expect(library.pageLayout(of: note) == .text)

        let unrelated = observes { _ = library.pageLayout(of: note) }
        var renamed = try #require(library.item(F.p2))
        renamed.title = "Renamed"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.p2)?.title == "Renamed" })
        #expect(!unrelated.isSet, "an edit to another item drew this page again")

        let attached = observes { _ = library.pageLayout(of: note) }
        let id = ItemID("doc")
        source.send(.upserted([document(id, attachedTo: Self.article)]))
        #expect(await eventually { library.item(id) != nil })
        #expect(attached.isSet, "a document attached to the item is not seen")
        #expect(library.pageLayout(of: note) == .webPage(document: id, runsScripts: false))

        let binned = observes { _ = library.pageLayout(of: note) }
        source.send(.upserted([document(id, attachedTo: Self.article, state: .trashed)]))
        #expect(await eventually { library.item(id)?.state == .trashed })
        #expect(binned.isSet, "a change to the attached file itself is not seen")
        #expect(library.pageLayout(of: note) == .text)
    }
}
