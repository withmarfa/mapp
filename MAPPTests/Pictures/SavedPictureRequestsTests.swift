import Foundation
import Testing
import WebKit
@testable import MAPP

/// A picture saved as a file on an item replaces its web address on the item's page: the answer comes from the file
/// whatever the Remote Pictures setting and whatever the ask, and the website is never asked. The answers come from
/// the editor's own wiring, with a stand-in internet that counts every request made to it.
@MainActor struct SavedPictureRequestsTests {
    private let folder: TemporaryFolder
    private let defaults: UserDefaults
    private let library: FakeItemLibrary
    private let site = PictureStub.newHost()
    private var address: String { "https://\(site)/a.png" }
    /// The editor holds its library weakly, so the test keeps both.
    private let editor: EditorController

    init() throws {
        let folder = try TemporaryFolder()
        let defaults = try #require(UserDefaults(suiteName: "SavedPictureRequestsTests-\(UUID().uuidString)"))
        let library = FakeItemLibrary()
        self.folder = folder
        self.defaults = defaults
        self.library = library
        editor = EditorController(
            library: library,
            pictures: WebPictures(
                cache: PictureCache(folder: folder.url.appending(path: "Cache")),
                fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
                defaults: defaults))
    }

    private func setting(_ setting: RemotePictureSetting) {
        defaults.set(setting.rawValue, forKey: RemotePictureSetting.key)
    }

    private func note(tier: Tier = .library) -> ItemID {
        let id = library.add("A note\n").id
        library.items[library.items.count - 1].tier = tier
        return id
    }

    /// An image file as a connector's download leaves it, in a folder of its own.
    private func file(_ data: Data = SamplePicture.png(), named name: String = "pic.png") throws -> URL {
        let directory = folder.url.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try data.write(to: url)
        return url
    }

    private func request(_ item: ItemID, _ address: String, ask: String, export: Bool? = nil) throws -> PictureRequest {
        var body: [String: Any] = ["type": "load", "item": item.rawValue, "address": address, "ask": ask]
        if let export { body["export"] = export }
        return try #require(PictureRequest(body: body))
    }

    private func savedURL(_ item: ItemID, _ address: String, file: URL) -> String {
        EmbeddedFiles.pictureURL(
            for: URL(string: address)!, version: 0, savedIn: item, stamp: file.deletingLastPathComponent().lastPathComponent
        ).absoluteString
    }

    private func trash(_ id: ItemID) throws {
        library.items[try #require(library.items.firstIndex { $0.id == id })].state = .trashed
    }

    // MARK: Showing it

    @Test(arguments: [RemotePictureSetting.ask, .always, .never], ["drawing", "chosen", "cached"])
    func aSavedPictureIsLoadedWhateverTheSettingAndTheAskWithNoRequestToTheWebsite(
        setting: RemotePictureSetting, ask: String
    ) async throws {
        self.setting(setting)
        let note = note()
        let saved = try file()
        library.attachPicture(saved, to: note, from: address)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: ask))

        #expect(reply == ["state": "loaded", "url": savedURL(note, address, file: saved)])
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test(arguments: [Tier.library, .feed])
    func theTierOfTheItemMakesNoDifference(tier: Tier) async throws {
        setting(.never)
        let note = note(tier: tier)
        let saved = try file()
        library.attachPicture(saved, to: note, from: address)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "loaded", "url": savedURL(note, address, file: saved)])
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func anAddressThatIsNotSecureIsShownFromItsFileToo() async throws {
        // A file the app already holds is read from disk, so nothing about the address is sent anywhere.
        setting(.never)
        let note = note()
        let plain = "http://\(site)/a.png"
        let saved = try file()
        library.attachPicture(saved, to: note, from: plain)

        let reply = await editor.pictureRequests.reply(to: try request(note, plain, ask: "drawing"))

        #expect(reply == ["state": "loaded", "url": savedURL(note, plain, file: saved)])
        #expect(PictureStub.requests(to: plain).isEmpty)
    }

    @Test func theAddressIsMatchedAsWrittenOnlyForTheHostAndSchemeCase() async throws {
        setting(.never)
        let note = note()
        library.attachPicture(try file(), to: note, from: "https://\(site.uppercased())/a.png")

        let same = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))
        let slash = await editor.pictureRequests.reply(to: try request(note, "https://\(site)/a.png/", ask: "drawing"))
        let longer = await editor.pictureRequests.reply(to: try request(note, "https://\(site)/a.png.bak", ask: "drawing"))

        #expect(same?["state"] == "loaded")
        #expect(slash == ["state": "off"], "a trailing slash is another address")
        #expect(longer == ["state": "off"], "a longer address is not matched by its prefix")
    }

    // MARK: Taking it away

    @Test func aFileInTheBinGivesBackToTheSettingAndRestoringItBringsThePictureBack() async throws {
        setting(.never)
        let note = note()
        let attached = library.attachPicture(try file(), to: note, from: address)
        let requests = editor.pictureRequests

        let before = await requests.reply(to: try request(note, address, ask: "drawing"))
        try trash(attached)
        let binned = await requests.reply(to: try request(note, address, ask: "drawing"))
        library.items[try #require(library.items.firstIndex { $0.id == attached })].state = .active
        let restored = await requests.reply(to: try request(note, address, ask: "drawing"))

        #expect(before?["state"] == "loaded")
        #expect(binned == ["state": "off"])
        #expect(restored == before)
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func aBinnedFileFollowsTheSettingToTheWebsiteWhereTheSettingAllowsIt() async throws {
        setting(.always)
        let note = note(tier: .feed)
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        let attached = library.attachPicture(try file(), to: note, from: address)
        try trash(attached)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "loaded", "url": EmbeddedFiles.pictureURL(for: URL(string: address)!, version: 0).absoluteString])
        #expect(PictureStub.requests(to: address).count == 1)
    }

    @Test func aFileOfAnotherItemIsNotUsedAndTheSettingAnswers() async throws {
        setting(.never)
        let note = note()
        let other = self.note()
        library.attachPicture(try file(), to: other, from: address)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "off"])
    }

    // MARK: When the file can't be had

    @Test func aFileThatCantBeFetchedIsRefusedToBeTriedAgainAndTheWebsiteIsNotAsked() async throws {
        setting(.always)
        let note = note(tier: .feed)
        PictureStub.answer(address, with: .body([SamplePicture.png()]))
        library.attachPicture(try file(), to: note, from: address)
        library.fetchFails = true

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "refused", "reason": "The server can’t be reached.", "retry": "true"])
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func aFileNotYetDownloadedIsRefusedToBeTriedAgainRatherThanLeftWaiting() async throws {
        setting(.never)
        let note = note()
        let missing = folder.url.appending(path: "not-yet/pic.png")
        library.attachPicture(missing, to: note, from: address)
        let requests = editor.pictureRequests

        let reply = await requests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "refused", "reason": "This file can’t be opened.", "retry": "true"])
        #expect(PictureStub.requests(to: address).isEmpty)

        // Once the file is there, trying again shows it.
        try FileManager.default.createDirectory(at: missing.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SamplePicture.png().write(to: missing)
        let again = await requests.reply(to: try request(note, address, ask: "chosen"))
        #expect(again?["state"] == "loaded")
    }

    @Test func aFileTheLibraryHoldsNoCopyOfFallsToTheSetting() async throws {
        setting(.never)
        let note = note()
        let attached = library.attachPicture(try file(), to: note, from: address)
        library.files[attached] = nil

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "off"])
    }

    @Test func aFileThatIsNotAnImageIsNotAPictureAndTheSettingAnswers() async throws {
        setting(.never)
        let note = note()
        library.attachPicture(try file(Data("not a picture".utf8), named: "page.txt"), to: note, from: address)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "off"])
    }

    @Test func ofTwoFilesFromOneAddressTheFirstThatCanBeHadIsShown() async throws {
        setting(.never)
        let note = note()
        let moment = Date(timeIntervalSince1970: 1_000_000)
        library.attachPicture(folder.url.appending(path: "not-yet/pic.png"), to: note, from: address, created: moment)
        let usable = try file()
        library.attachPicture(usable, to: note, from: address, created: moment + 60)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "drawing"))

        #expect(reply == ["state": "loaded", "url": savedURL(note, address, file: usable)])
    }

    @Test func aReplyAfterTheNoteChangedIsDropped() async throws {
        let note = note()
        library.attachPicture(try file(), to: note, from: address)
        let requests = editor.pictureRequests
        var asked = 0
        requests.version = {
            asked += 1
            return asked
        }

        #expect(await requests.reply(to: try request(note, address, ask: "drawing")) == nil)
    }

    // MARK: Export and print

    @Test func anExportTakesTheBytesOfTheFileWhateverTheSettingAndFetchesNothing() async throws {
        setting(.never)
        let note = note()
        let bytes = SamplePicture.png(width: 5, height: 3)
        library.attachPicture(try file(bytes), to: note, from: address)

        let reply = try #require(await editor.pictureRequests.reply(to: try request(note, address, ask: "cached", export: true)))

        #expect(reply["state"] == "loaded")
        #expect(reply["mimeType"] == "image/png")
        #expect(Data(base64Encoded: try #require(reply["data"])) == bytes)
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    @Test func aFileTooLargeForAnExportIsNotHandedOver() async throws {
        let note = note()
        let large = SamplePicture.png() + Data(count: PictureRequests.largestExport)
        library.attachPicture(try file(large), to: note, from: address)

        let reply = await editor.pictureRequests.reply(to: try request(note, address, ask: "cached", export: true))

        #expect(reply == nil, "the same limit as a picture from the web")
        #expect(PictureStub.requests(to: address).isEmpty)
    }

    // MARK: Serving it

    private func serve(_ files: EmbeddedFiles, _ url: URL) async throws -> RecordingSchemeTask {
        let task = RecordingSchemeTask(url)
        files.webView(WKWebView(), start: task)
        try #require(await eventually { task.finished || task.failure != nil })
        return task
    }

    private func schemeHandler() async throws -> EmbeddedFiles {
        let files = EmbeddedFiles()
        files.openSaved = { [library] item, address in
            guard case .file(let opened) = await library.openSavedPicture(of: item, at: address) else { return nil }
            return opened
        }
        // The web cache holds a picture for every address, to show that none is served in place of a saved one.
        let cached = try file(Data("from the cache".utf8), named: "cached.png")
        let folder = try #require(OpenFile.realPath(of: cached.deletingLastPathComponent()))
        let kept = await OpenFile.open(folder.appending(path: "cached.png"), inside: folder)
        files.openPicture = { _ in kept }
        return files
    }

    @Test func theSchemeServesTheFileAndServesNothingOnceItIsBinned() async throws {
        let note = note()
        let bytes = SamplePicture.png(width: 6, height: 2)
        let saved = try file(bytes)
        let attached = library.attachPicture(saved, to: note, from: address)
        let url = EmbeddedFiles.pictureURL(
            for: URL(string: address)!, version: 1, savedIn: note, stamp: saved.deletingLastPathComponent().lastPathComponent)
        let files = try await schemeHandler()

        let served = try await serve(files, url)
        try trash(attached)
        let binned = try await serve(files, url)

        #expect(served.response?.statusCode == 200)
        #expect(served.response?.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(served.data == bytes)
        #expect(binned.response?.statusCode == 404, "a picture URL the page still holds shows nothing once the file is binned")
    }

    @Test func theSchemeServesNothingForAnItemOrAnAddressThatHasNoSuchFile() async throws {
        let note = note()
        library.attachPicture(try file(), to: note, from: address)
        let files = try await schemeHandler()
        let other = ItemID.mint()

        let ofAnother = try await serve(files, EmbeddedFiles.pictureURL(for: URL(string: address)!, version: 1, savedIn: other))
        let ofAnotherAddress = try await serve(
            files, EmbeddedFiles.pictureURL(for: URL(string: "https://\(site)/b.png")!, version: 1, savedIn: note))

        #expect(ofAnother.response?.statusCode == 404, "a URL cannot be made to serve another item's file")
        #expect(ofAnotherAddress.response?.statusCode == 404, "and the kept web pictures are not served in its place")
    }
}
