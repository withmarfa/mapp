import Foundation
import Testing
@testable import MAPP

/// What is fetched, and when, by the Remote Pictures setting. Nothing here reaches a network: the fetcher is given
/// `PictureStub`, which counts the requests made to a host of the test's own.
@MainActor struct WebPicturesTests {
    private let folder: TemporaryFolder
    private let defaults: UserDefaults
    private let suite = "WebPicturesTests-\(UUID().uuidString)"

    init() throws {
        folder = try TemporaryFolder()
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    private func pictures(limit: Int = PictureCache.standardLimit) -> WebPictures {
        WebPictures(
            cache: PictureCache(folder: folder.url.appending(path: "Cache"), limit: limit),
            fetcher: PictureFetcher(resolver: PictureStub.resolver, configuration: PictureStub.configuration),
            defaults: defaults)
    }

    private func set(_ setting: RemotePictureSetting) {
        defaults.set(setting.rawValue, forKey: RemotePictureSetting.key)
    }

    /// An address that serves a picture, and the number of requests made to it.
    private func served(width: Int = 8) -> (address: URL, requests: () -> Int) {
        let text = "https://\(PictureStub.newHost())/a.png"
        PictureStub.answer(text, with: .body([SamplePicture.png(width: width)]))
        return (URL(string: text)!, { PictureStub.requests(to: text).count })
    }

    private func isLoaded(_ answer: PictureAnswer) -> Bool {
        if case .loaded = answer { return true }
        return false
    }

    @Test func withNothingSetThePersonIsAskedAndNothingIsFetched() async {
        let (address, requests) = served()
        let pictures = pictures()

        #expect(RemotePictureSetting.current(in: defaults) == .ask)
        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: false) == .waiting)
        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: true) == .waiting)
        #expect(requests() == 0)
    }

    @Test func choosingAPictureFetchesItAndTheNextDrawingNeedsNoRequestOrQuestion() async throws {
        let (address, requests) = served()
        let pictures = pictures()

        let answer = await pictures.answer(address, ask: .chosen, fromAnotherService: false)
        let again = await pictures.answer(address, ask: .drawing, fromAnotherService: false)

        guard case .loaded(let file) = answer else {
            Issue.record("not loaded: \(answer)")
            return
        }
        #expect(try Data(contentsOf: file) == SamplePicture.png())
        #expect(again == answer)
        #expect(requests() == 1)
    }

    @Test func manyAskingAtOnceFetchOnce() async {
        let (address, requests) = served()
        let pictures = pictures()

        async let first = pictures.answer(address, ask: .chosen, fromAnotherService: false)
        async let second = pictures.answer(address, ask: .chosen, fromAnotherService: false)
        async let third = pictures.answer(address, ask: .chosen, fromAnotherService: false)
        let answers = await [first, second, third]

        #expect(answers.allSatisfy(isLoaded))
        #expect(requests() == 1)
    }

    @Test func neverFetchesNothingEvenForAPictureThePersonChose() async {
        let (address, requests) = served()
        let pictures = pictures()
        set(.never)

        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: true) == .off)
        #expect(await pictures.answer(address, ask: .chosen, fromAnotherService: false) == .off)
        #expect(requests() == 0)
    }

    @Test func aPictureAlreadyKeptShowsWhateverTheSettingIsNow() async {
        let (address, requests) = served()
        let pictures = pictures()
        _ = await pictures.answer(address, ask: .chosen, fromAnotherService: false)
        set(.never)

        #expect(isLoaded(await pictures.answer(address, ask: .drawing, fromAnotherService: false)))
        #expect(requests() == 1)
    }

    @Test func alwaysLoadsForAnItemFromAnotherServiceAndNeverForANoteThePersonWrote() async {
        let (other, otherRequests) = served()
        let (own, ownRequests) = served()
        let pictures = pictures()
        set(.always)

        #expect(isLoaded(await pictures.answer(other, ask: .drawing, fromAnotherService: true)))
        #expect(await pictures.answer(own, ask: .drawing, fromAnotherService: false) == .waiting)
        #expect(otherRequests() == 1)
        #expect(ownRequests() == 0)
        #expect(isLoaded(await pictures.answer(own, ask: .chosen, fromAnotherService: false)))
    }

    @Test func theSettingIsReadAtEachQuestion() async {
        let (address, requests) = served()
        let pictures = pictures()

        set(.never)
        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: true) == .off)
        set(.ask)
        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: true) == .waiting)
        set(.always)
        #expect(isLoaded(await pictures.answer(address, ask: .drawing, fromAnotherService: true)))
        #expect(requests() == 1)
    }

    @Test func printingAsksOnlyForWhatIsKeptAndFetchesNothing() async {
        let (kept, keptRequests) = served()
        let (missing, missingRequests) = served()
        let pictures = pictures()
        set(.always)
        _ = await pictures.answer(kept, ask: .chosen, fromAnotherService: false)

        #expect(isLoaded(await pictures.answer(kept, ask: .cached, fromAnotherService: true)))
        #expect(await pictures.answer(missing, ask: .cached, fromAnotherService: true) == .waiting)
        #expect(keptRequests() == 1)
        #expect(missingRequests() == 0)
    }

    @Test func anAddressWithoutTLSIsRefusedUnderEverySetting() async {
        let address = URL(string: "http://\(PictureStub.newHost())/a.png")!
        let pictures = pictures()

        for setting in RemotePictureSetting.allCases {
            set(setting)
            #expect(await pictures.answer(address, ask: .chosen, fromAnotherService: true) == .refused(.notSecure))
        }
    }

    @Test func aRefusedPictureIsNotKeptAndCanBeChosenAgain() async {
        let text = "https://\(PictureStub.newHost())/a.png"
        let address = URL(string: text)!
        PictureStub.answer(text, with: .body([SamplePicture.page]))
        let pictures = pictures()

        #expect(await pictures.answer(address, ask: .chosen, fromAnotherService: false) == .refused(.notAPicture))
        #expect(await pictures.answer(address, ask: .drawing, fromAnotherService: false) == .waiting)
        PictureStub.answer(text, with: .body([SamplePicture.png()]))
        #expect(isLoaded(await pictures.answer(address, ask: .chosen, fromAnotherService: false)))
        #expect(PictureStub.requests(to: text).count == 2)
    }

    @Test func theCacheKeepsTheMostRecentlyUsedWithinItsLimit() async throws {
        let size = SamplePicture.png(width: 64).count
        let pictures = pictures(limit: size * 2 + size / 2)
        let (first, _) = served(width: 64)
        let (second, _) = served(width: 64)
        let (third, _) = served(width: 64)

        _ = await pictures.answer(first, ask: .chosen, fromAnotherService: false)
        try await Task.sleep(for: .milliseconds(20))  // gives the files different times of use
        _ = await pictures.answer(second, ask: .chosen, fromAnotherService: false)
        try await Task.sleep(for: .milliseconds(20))
        _ = await pictures.cache.file(for: first)  // the first is used again, so the second is the oldest
        try await Task.sleep(for: .milliseconds(20))
        _ = await pictures.answer(third, ask: .chosen, fromAnotherService: false)

        #expect(await pictures.cache.file(for: first) != nil)
        #expect(await pictures.cache.file(for: second) == nil)
        #expect(await pictures.cache.file(for: third) != nil)
    }

    @Test func removingAllLeavesNothingOfThePicturesKept() async {
        let (address, _) = served()
        let pictures = pictures()
        _ = await pictures.answer(address, ask: .chosen, fromAnotherService: false)

        await PictureCache.removeAll(in: pictures.cache.folder)

        #expect(await pictures.cache.file(for: address) == nil)
        #expect(!FileManager.default.fileExists(atPath: pictures.cache.folder.path))
    }
}
