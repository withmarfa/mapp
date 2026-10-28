import Foundation
import Testing
@testable import MAPP

@Suite(.hangLimit)
@MainActor struct PictureRequestsTests {
    private let folder: TemporaryFolder
    private let defaults: UserDefaults

    init() throws {
        folder = try TemporaryFolder()
        defaults = try #require(UserDefaults(suiteName: "PictureRequestsTests-\(UUID().uuidString)"))
    }

    private func requests() -> PictureRequests {
        PictureRequests(
            pictures: WebPictures(
                cache: PictureCache(folder: folder.url.appending(path: "Cache")),
                fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
                defaults: defaults))
    }

    private func body(_ address: String, ask: String, export: Bool? = nil) -> [String: Any] {
        var body: [String: Any] = ["type": "load", "item": "note", "address": address, "ask": ask]
        if let export { body["export"] = export }
        return body
    }

    @Test func aRequestIsReadFromWhatThePageSends() throws {
        let request = try #require(PictureRequest(body: body("https://example.com/a.png", ask: "chosen")))

        #expect(request == PictureRequest(body: body("https://example.com/a.png", ask: "chosen")))
        #expect(request.ask == .chosen)
        #expect(request.address == URL(string: "https://example.com/a.png"))
        #expect(!request.exporting)
    }

    @Test(arguments: [
        #""nonsense""#, #"{"type":"load"}"#,
        #"{"type":"other","item":"n","address":"https://a.com/x","ask":"drawing"}"#,
        #"{"type":"load","item":"n","address":"file:///etc/passwd","ask":"drawing"}"#,
        #"{"type":"load","item":"n","address":"https://a.com/x","ask":"everything"}"#,
        #"{"type":"load","item":"","address":"https://a.com/x","ask":"drawing"}"#,
    ])
    func aRequestThatIsNotOneIsNotRead(json: String) throws {
        let body = try JSONSerialization.jsonObject(with: Data(json.utf8), options: .fragmentsAllowed)

        #expect(PictureRequest(body: body) == nil)
    }

    @Test func aWaitingPictureIsAnsweredWaitingAndALoadedOneWithAnAddressOnTheScheme() async throws {
        let text = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(text, with: .body([SamplePicture.png()]))
        let requests = requests()
        requests.version = { 3 }

        let drawing = try #require(PictureRequest(body: body(text, ask: "drawing")))
        let chosen = try #require(PictureRequest(body: body(text, ask: "chosen")))
        let waiting = await requests.reply(to: drawing)
        let loaded = await requests.reply(to: chosen)

        #expect(waiting == ["state": "waiting"])
        #expect(loaded == ["state": "loaded", "url": EmbeddedFiles.pictureURL(for: URL(string: text)!, version: 3).absoluteString])
    }

    @Test func aSettingOfNeverIsAnsweredOff() async throws {
        defaults.set(RemotePictureSetting.never.rawValue, forKey: RemotePictureSetting.key)

        let request = try #require(PictureRequest(body: body("https://example.com/a.png", ask: "chosen")))
        let reply = await requests().reply(to: request)

        #expect(reply == ["state": "off"])
    }

    @Test func aRefusalGivesTheReasonAndSaysWhetherTryingAgainMayHelp() async throws {
        let site = PictureStub.newHost()
        let missing = "https://\(site)/missing.png"
        PictureStub.answer(missing, with: .body([SamplePicture.png()], status: 503))
        let svg = "https://\(site)/a.svg"
        PictureStub.answer(svg, with: .body([SamplePicture.svg], type: "image/svg+xml"))
        let requests = requests()

        let busyRequest = try #require(PictureRequest(body: body(missing, ask: "chosen")))
        let wrongRequest = try #require(PictureRequest(body: body(svg, ask: "chosen")))
        let busy = try #require(await requests.reply(to: busyRequest))
        let wrong = try #require(await requests.reply(to: wrongRequest))

        #expect(busy["state"] == "refused")
        #expect(busy["reason"] == PictureFailure.badStatus(503).message)
        #expect(busy["retry"] == "true")
        #expect(wrong["state"] == "refused")
        #expect(wrong["reason"] == PictureFailure.notAPicture.message)
        #expect(wrong["retry"] == nil)
    }

    @Test func aReplyAfterTheNoteChangedIsDropped() async throws {
        let text = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(text, with: .body([SamplePicture.png()]))
        let requests = requests()
        // The reply asks for the version before the fetch and again after it: the note changes in between.
        var asked = 0
        requests.version = {
            asked += 1
            return asked
        }
        let request = try #require(PictureRequest(body: body(text, ask: "chosen")))

        #expect(await requests.reply(to: request) == nil)
    }

    @Test func anExportTakesTheBytesOfAKeptPictureOnlyAndFetchesNothing() async throws {
        let kept = "https://\(PictureStub.newHost())/a.png"
        let other = "https://\(PictureStub.newHost())/b.png"
        PictureStub.answer(kept, with: .body([SamplePicture.png()]))
        PictureStub.answer(other, with: .body([SamplePicture.png()]))
        let requests = requests()
        let choice = try #require(PictureRequest(body: body(kept, ask: "chosen")))
        let keptExport = try #require(PictureRequest(body: body(kept, ask: "cached", export: true)))
        let otherExport = try #require(PictureRequest(body: body(other, ask: "chosen", export: true)))
        _ = await requests.reply(to: choice)

        let reply = try #require(await requests.reply(to: keptExport))
        let missing = await requests.reply(to: otherExport)

        #expect(reply["state"] == "loaded")
        #expect(reply["mimeType"] == "image/png")
        #expect(Data(base64Encoded: try #require(reply["data"])) == SamplePicture.png())
        #expect(missing == ["state": "waiting"])
        #expect(PictureStub.requests(to: other).isEmpty)
    }

    @Test func aPictureUrlOnTheSchemeNamesItsAddressAndNothingElse() throws {
        let address = URL(string: "https://example.com/a b.png?x=1&y=2#frag")!
        let url = EmbeddedFiles.pictureURL(for: address, version: 4)

        #expect(url.scheme == EmbeddedFiles.scheme)
        #expect(url.host == "picture")
        #expect(EmbeddedFiles.pictureAddress(in: url) == address)
        #expect(EmbeddedFiles.pictureAddress(in: EmbeddedFiles.pictureURL(for: URL(string: "http://example.com/a.png")!, version: 1)) == nil)
        #expect(EmbeddedFiles.pictureAddress(in: URL(string: "https://example.com/a.png")!) == nil)
    }
}
