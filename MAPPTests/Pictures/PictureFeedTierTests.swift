import Foundation
import Marfa
import enum MarfaCore.ItemState
import enum MarfaCore.Tier
import struct MarfaCore.Item
import Testing
@testable import MAPP

/// Which items Always loads pictures for without asking. Marfa stamps every item with the source of the key that wrote
/// it, so a note written in MAPP has a source too: the tier is what tells the feed from the library. The items are
/// mapped from rows as the library maps them, and the answers come from the editor's own wiring.
@MainActor struct PictureFeedTierTests {
    private let folder: TemporaryFolder
    private let defaults: UserDefaults

    init() throws {
        folder = try TemporaryFolder()
        defaults = try #require(UserDefaults(suiteName: "PictureFeedTierTests-\(UUID().uuidString)"))
        defaults.set(RemotePictureSetting.always.rawValue, forKey: RemotePictureSetting.key)
    }

    private func item(_ id: String, tier: Marfa.Tier, source: String) -> MAPP.Item {
        let row = Marfa.Item(
            id: id, type: "core.note", properties: ["title": "Title", "body": "Body"], state: .active, tier: tier, version: 1,
            schemaVersion: 1, source: source, sourceId: nil, occurredAt: "2026-10-06T00:52:22.021Z",
            createdAt: "2026-10-06T00:52:22.021Z", updatedAt: "2026-10-06T01:00:00Z", tags: [])
        return MarfaMapping.item(row, edges: [], catalogue: FakeItemLibrary.testCatalogue, isHeld: { _ in false })
    }

    private func editor(_ library: FakeItemLibrary) -> EditorController {
        EditorController(
            library: library,
            pictures: WebPictures(
                cache: PictureCache(folder: folder.url.appending(path: "Cache")),
                fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
                defaults: defaults))
    }

    private func request(_ item: ItemID, _ address: String, ask: String) throws -> PictureRequest {
        try #require(PictureRequest(body: ["type": "load", "item": item.rawValue, "address": address, "ask": ask]))
    }

    @Test func alwaysLoadsInTheFeedAndAsksInTheLibraryEvenWhereTheLibraryItemHasASource() async throws {
        let written = item("written-in-mapp", tier: .library, source: "mapp")
        let captured = item("captured", tier: .feed, source: "mapp")
        let connector = item("from-a-connector", tier: .feed, source: "rss")
        #expect(written.source == "mapp" && written.tier == .library, "the library item has a source, as every item does")
        let library = FakeItemLibrary(items: [written, captured, connector])
        let editor = editor(library)
        // The stub counts requests by host, so each picture is on a host of its own.
        let addresses = (0..<3).map { _ in "https://\(PictureStub.newHost())/a.png" }
        for address in addresses { PictureStub.answer(address, with: .body([SamplePicture.png()])) }

        let own = await editor.pictureRequests.reply(to: try request(written.id, addresses[0], ask: "drawing"))
        let feed = await editor.pictureRequests.reply(to: try request(captured.id, addresses[1], ask: "drawing"))
        let other = await editor.pictureRequests.reply(to: try request(connector.id, addresses[2], ask: "drawing"))

        #expect(own == ["state": "waiting"])
        #expect(feed?["state"] == "loaded")
        #expect(other?["state"] == "loaded")
        #expect(PictureStub.requests(to: addresses[0]).isEmpty, "nothing was asked of the website a note names")
        #expect(PictureStub.requests(to: addresses[1]).count == 1)
        #expect(PictureStub.requests(to: addresses[2]).count == 1)
    }

    @Test func choosingStillLoadsAPictureInALibraryNoteAndItThenShowsWithoutAsking() async throws {
        let written = item("written-in-mapp", tier: .library, source: "mapp")
        let library = FakeItemLibrary(items: [written])
        let editor = editor(library)
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))

        let chosen = await editor.pictureRequests.reply(to: try request(written.id, address, ask: "chosen"))
        let again = await editor.pictureRequests.reply(to: try request(written.id, address, ask: "drawing"))

        #expect(chosen?["state"] == "loaded")
        #expect(again == chosen)
        #expect(PictureStub.requests(to: address).count == 1)
    }

    @Test func aPictureLoadedInTheFeedKeepsShowingOnceTheItemMovesToTheLibrary() async throws {
        let captured = item("captured", tier: .feed, source: "mapp")
        let library = FakeItemLibrary(items: [captured])
        let editor = editor(library)
        let address = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        _ = await editor.pictureRequests.reply(to: try request(captured.id, address, ask: "drawing"))

        library.items = [item("captured", tier: .library, source: "mapp")]
        let later = await editor.pictureRequests.reply(to: try request(captured.id, address, ask: "drawing"))

        #expect(later?["state"] == "loaded")
        #expect(PictureStub.requests(to: address).count == 1)
    }
}
