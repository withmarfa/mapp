import Foundation
import Observation
import Testing
import UniformTypeIdentifiers
@testable import MAPP

/// An item's page reads its attachments to choose its layout, so that read follows the files attached to the item and
/// nothing else: an edit elsewhere in the library does not draw every page again.
@MainActor
@Suite(.hangLimit) struct AttachmentObservationTests {
    private typealias F = LibraryFixture

    private func loaded() async throws -> (MarfaLibrary, FakeItemSource) {
        let source = FakeItemSource()
        let library = MarfaLibrary(source: source, notices: Notices())
        var catalogue = F.catalogue
        catalogue.edgeTypes[MarfaMapping.attachmentEdge] = EdgeTypeInfo(
            id: MarfaMapping.attachmentEdge, label: "Attached to", reverseLabel: "Attachments", reverseName: nil, cardinality: .many,
            writtenAt: .source, sourceTypes: [MarfaMapping.fileType], targetTypes: [])
        source.send(.loaded(SourceSnapshot(items: F.items, catalogue: catalogue)))
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
            properties: [Property(key: ItemPageLayout.resourceKindField, value: .string(ItemPageLayout.htmlResource))],
            content: .file(.html, byteCount: 10))
    }

    @Test func aPageLayoutFollowsTheItemsAttachmentsAndNothingElse() async throws {
        let (library, source) = try await loaded()
        let note = try #require(library.item(F.n1))
        #expect(library.pageLayout(of: note) == .text)

        let unrelated = observes { _ = library.pageLayout(of: note) }
        var renamed = try #require(library.item(F.p2))
        renamed.title = "Renamed"
        source.send(.upserted([renamed]))
        #expect(await eventually { library.item(F.p2)?.title == "Renamed" })
        #expect(!unrelated.isSet, "an edit to another item drew this page again")

        let attached = observes { _ = library.pageLayout(of: note) }
        let id = ItemID("doc")
        source.send(.upserted([document(id, attachedTo: F.n1)]))
        #expect(await eventually { library.item(id) != nil })
        #expect(attached.isSet, "a document attached to the item is not seen")
        #expect(library.pageLayout(of: note) == .webPage(document: id, runsScripts: false))

        let binned = observes { _ = library.pageLayout(of: note) }
        source.send(.upserted([document(id, attachedTo: F.n1, state: .trashed)]))
        #expect(await eventually { library.item(id)?.state == .trashed })
        #expect(binned.isSet, "a change to the attached file itself is not seen")
        #expect(library.pageLayout(of: note) == .text)
    }
}
