import Foundation
import Testing
import WebKit
@testable import MAPP

/// The pictures of a document shown in the sealed web page come from the app alone: a saved picture first, under every
/// setting, then the Remote Pictures setting. Nothing here reaches a network: the fetcher is given `PictureStub`.
@Suite(.hangLimit)
@MainActor struct SealedPicturesTests {
    private let folder: TemporaryFolder
    private let defaults: UserDefaults
    private let library = FakeItemLibrary()
    private let note: ItemID

    init() throws {
        folder = try TemporaryFolder()
        defaults = try #require(UserDefaults(suiteName: "SealedPicturesTests-\(UUID().uuidString)"))
        note = library.add("An article\n").id
    }

    private func set(_ setting: RemotePictureSetting) {
        defaults.set(setting.rawValue, forKey: RemotePictureSetting.key)
    }

    private func pictures(for item: ItemID? = nil) -> SealedPictures {
        let item = item ?? note
        let web = WebPictures(
            cache: PictureCache(folder: folder.url.appending(path: "Cache"), limit: PictureCache.standardLimit),
            fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
            defaults: defaults, queue: PictureQueue())
        return SealedPictures(item: item, pictures: web, inFeed: { false }) { [library] in
            await library.openSavedPicture(of: item, at: $0)
        }
    }

    /// An address a website serves a picture at, and the number of requests made to it.
    private func served(width: Int = 8) -> (address: URL, requests: () -> Int) {
        let text = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(text, with: .body([SamplePicture.png(width: width)]))
        return (URL(string: text)!, { PictureStub.requests(to: text).count })
    }

    @discardableResult
    private func saved(from address: URL, width: Int = 8) throws -> ItemID {
        let file = folder.url.appending(path: "\(UUID().uuidString).png")
        try SamplePicture.png(width: width).write(to: file)
        return library.attachPicture(file, to: note, from: address.absoluteString)
    }

    private func reply(_ pictures: SealedPictures, _ address: URL, item: ItemID? = nil) async -> String {
        switch await pictures.answer(SealedPictures.url(for: address, in: item ?? pictures.item, version: pictures.version)) {
        case .file: "file"
        case .placeholder: "placeholder"
        case .refused: "refused"
        }
    }

    private func refused(_ pictures: SealedPictures, _ url: URL?) async -> Bool {
        if case .refused = await pictures.answer(url) { return true }
        return false
    }

    // MARK: Answering

    @Test func aSavedPictureIsServedUnderNeverWithNoRequest() async throws {
        set(.never)
        let (address, requests) = served()
        try saved(from: address)
        let pictures = pictures()
        pictures.show([address], version: pictures.version)

        #expect(await reply(pictures, address) == "file")
        #expect(requests() == 0)
        #expect(pictures.waitingCount == 0)
    }

    @Test func underAskAPictureWaitsUntilThePersonChoosesToLoadIt() async {
        let (address, requests) = served()
        let pictures = pictures()
        pictures.show([address], version: pictures.version)

        #expect(await reply(pictures, address) == "placeholder")
        #expect(pictures.waitingCount == 1)
        #expect(requests() == 0)

        pictures.loadWaiting()
        #expect(await reply(pictures, address) == "file")
        #expect(requests() == 1)
        #expect(pictures.waitingCount == 0)
    }

    @Test func underNeverNothingWaitsAndNothingIsFetched() async {
        set(.never)
        let (address, requests) = served()
        let pictures = pictures()
        pictures.show([address], version: pictures.version)

        #expect(await reply(pictures, address) == "placeholder")
        #expect(pictures.waitingCount == 0)
        #expect(requests() == 0)
    }

    @Test func onlyThisItemsPicturesAreAnswered() async throws {
        set(.always)
        let (address, _) = served()
        let (notShown, requests) = served()
        let pictures = pictures()
        pictures.show([address], version: pictures.version)

        #expect(await reply(pictures, address, item: ItemID("another-item")) == "refused")
        #expect(await reply(pictures, notShown) == "refused", "an address the document did not name")
        #expect(await refused(pictures, address), "a web address itself")
        #expect(await refused(pictures, URL(string: "\(SealedPictures.scheme)://picture/?item=\(note.rawValue)&address=file:///etc/hosts&v=0")))
        #expect(await refused(pictures, nil))
        #expect(requests() == 0)
    }

    // MARK: In the sealed page

    private func images(on page: SealedWebPage) async throws -> [Int] {
        let widths = try await page.page.callJavaScript(
            "return Array.from(document.images).map(i => i.complete ? i.naturalWidth : -1)") as? [Any]
        return (widths ?? []).compactMap { ($0 as? NSNumber)?.intValue }
    }

    @Test func aReaderPageDrawsItsSavedPicturesAndLoadsTheRestWhenChosen() async throws {
        let (kept, keptRequests) = served()
        try saved(from: kept, width: 5)
        let (waiting, waitingRequests) = served(width: 7)
        let pictures = pictures()
        let page = try await SealedWebPage.make(pictures: pictures, runsScripts: false)
        let document = SealedPictureRewrite.rewrite(
            Data(#"<html><body><img src="\#(kept.absoluteString)"><img data-src="\#(waiting.absoluteString)"></body></html>"#.utf8),
            item: note, version: pictures.version)
        pictures.show(document.addresses, version: 0)
        try await page.show(document.html)

        #expect(try await eventuallyAsking { try await images(on: page).first == 5 })
        #expect(await eventually { pictures.waitingCount == 1 })

        pictures.loadWaiting()
        await page.redrawPictures(version: pictures.version)
        #expect(try await eventuallyAsking { try await images(on: page) == [5, 7] }, "the redraw works with the page's scripts off")
        #expect(keptRequests() == 0)
        #expect(waitingRequests() == 1)
    }

    @Test func picturesWaitingAreCountedWhenTheSettingChangedWhileThePageLoaded() async throws {
        let (address, requests) = served()
        let pictures = pictures()
        let page = try await SealedWebPage.make(pictures: pictures, runsScripts: false)
        let document = SealedPictureRewrite.rewrite(
            Data(#"<html><body><img src="\#(address.absoluteString)"></body></html>"#.utf8), item: note, version: pictures.version)
        pictures.show(document.addresses, version: 0)
        // As when the Remote Pictures setting or a saved picture changes after the rewrite and before the page draws.
        pictures.redraw()
        try await page.show(document.html)

        #expect(await eventually { pictures.waitingCount == 1 })
        #expect(requests() == 0)
    }

    @Test func aPageWithPicturesStillReachesNoServer() async throws {
        let probe = try await Probe()
        let pictures = pictures()
        let page = try await SealedWebPage.make(pictures: pictures, runsScripts: true)
        try await page.show(Data("""
            <html><body><script>
            window.results = {};
            const tries = ['https', 'http'].map(scheme => fetch(scheme + '://127.0.0.1:\(probe.port)/fetch', { mode: 'no-cors' })
              .then(() => 'loaded', () => 'blocked'));
            tries.push(new Promise(res => { const i = new Image(); i.onload = () => res('loaded'); i.onerror = () => res('blocked');
              i.src = 'https://127.0.0.1:\(probe.port)/img.png'; }));
            Promise.all(tries).then(r => { results.r = r.join(); window.done = true; });
            </script></body></html>
            """.utf8))

        #expect(try await eventuallyAsking { (try await page.page.callJavaScript("return window.done === true") as? Bool) == true })
        #expect(try await page.page.callJavaScript("return window.results.r") as? String == "blocked,blocked,blocked")
        #expect(probe.count == 0, "nothing reached the server, but \(probe.seen) did")
    }
}

