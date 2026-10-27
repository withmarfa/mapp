import Foundation
import Synchronization
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

    private func pictures(
        limit: Int = PictureCache.standardLimit, resolver: @escaping PictureAddressPolicy.Resolver = PictureStub.resolver,
        queue: PictureQueue = PictureQueue()
    ) -> WebPictures {
        WebPictures(
            cache: PictureCache(folder: folder.url.appending(path: "Cache"), limit: limit),
            fetcher: PictureFetcher(resolver: resolver, configuration: PictureStub.configuration),
            defaults: defaults, queue: queue)
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
        #expect(await pictures.answer(address, ask: .drawing, inFeed: false) == .waiting)
        #expect(await pictures.answer(address, ask: .drawing, inFeed: true) == .waiting)
        #expect(requests() == 0)
    }

    @Test func choosingAPictureFetchesItAndTheNextDrawingNeedsNoRequestOrQuestion() async throws {
        let (address, requests) = served()
        let pictures = pictures()

        let answer = await pictures.answer(address, ask: .chosen, inFeed: false)
        let again = await pictures.answer(address, ask: .drawing, inFeed: false)

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

        async let first = pictures.answer(address, ask: .chosen, inFeed: false)
        async let second = pictures.answer(address, ask: .chosen, inFeed: false)
        async let third = pictures.answer(address, ask: .chosen, inFeed: false)
        let answers = await [first, second, third]

        #expect(answers.allSatisfy(isLoaded))
        #expect(requests() == 1)
    }

    @Test func neverFetchesNothingEvenForAPictureThePersonChose() async {
        let (address, requests) = served()
        let pictures = pictures()
        set(.never)

        #expect(await pictures.answer(address, ask: .drawing, inFeed: true) == .off)
        #expect(await pictures.answer(address, ask: .chosen, inFeed: false) == .off)
        #expect(requests() == 0)
    }

    @Test func aPictureAlreadyKeptShowsWhateverTheSettingIsNow() async {
        let (address, requests) = served()
        let pictures = pictures()
        _ = await pictures.answer(address, ask: .chosen, inFeed: false)
        set(.never)

        #expect(isLoaded(await pictures.answer(address, ask: .drawing, inFeed: false)))
        #expect(requests() == 1)
    }

    @Test func alwaysLoadsForAnItemInTheFeedAndAsksForOneInTheLibrary() async {
        let (feed, feedRequests) = served()
        let (library, libraryRequests) = served()
        let pictures = pictures()
        set(.always)

        #expect(isLoaded(await pictures.answer(feed, ask: .drawing, inFeed: true)))
        #expect(await pictures.answer(library, ask: .drawing, inFeed: false) == .waiting)
        #expect(feedRequests() == 1)
        #expect(libraryRequests() == 0)
        #expect(isLoaded(await pictures.answer(library, ask: .chosen, inFeed: false)))
    }

    @Test func theSettingIsReadAtEachQuestion() async {
        let (address, requests) = served()
        let pictures = pictures()

        set(.never)
        #expect(await pictures.answer(address, ask: .drawing, inFeed: true) == .off)
        set(.ask)
        #expect(await pictures.answer(address, ask: .drawing, inFeed: true) == .waiting)
        set(.always)
        #expect(isLoaded(await pictures.answer(address, ask: .drawing, inFeed: true)))
        #expect(requests() == 1)
    }

    @Test func printingAsksOnlyForWhatIsKeptAndFetchesNothing() async {
        let (kept, keptRequests) = served()
        let (missing, missingRequests) = served()
        let pictures = pictures()
        set(.always)
        _ = await pictures.answer(kept, ask: .chosen, inFeed: false)

        #expect(isLoaded(await pictures.answer(kept, ask: .cached, inFeed: true)))
        #expect(await pictures.answer(missing, ask: .cached, inFeed: true) == .waiting)
        #expect(keptRequests() == 1)
        #expect(missingRequests() == 0)
    }

    @Test func anAddressWithoutTLSIsRefusedUnderEverySetting() async {
        let address = URL(string: "http://\(PictureStub.newHost())/a.png")!
        let pictures = pictures()

        for setting in RemotePictureSetting.allCases {
            set(setting)
            #expect(await pictures.answer(address, ask: .chosen, inFeed: true) == .refused(.notSecure))
        }
    }

    @Test func aRefusedPictureIsNotKeptAndCanBeChosenAgain() async {
        let text = "https://\(PictureStub.newHost())/a.png"
        let address = URL(string: text)!
        PictureStub.answer(text, with: .body([SamplePicture.page]))
        let pictures = pictures()

        #expect(await pictures.answer(address, ask: .chosen, inFeed: false) == .refused(.notAPicture))
        #expect(await pictures.answer(address, ask: .drawing, inFeed: false) == .waiting)
        PictureStub.answer(text, with: .body([SamplePicture.png()]))
        #expect(isLoaded(await pictures.answer(address, ask: .chosen, inFeed: false)))
        #expect(PictureStub.requests(to: text).count == 2)
    }

    @Test func theCacheKeepsTheMostRecentlyUsedWithinItsLimit() async throws {
        let size = SamplePicture.png(width: 64).count
        let pictures = pictures(limit: size * 2 + size / 2)
        let (first, _) = served(width: 64)
        let (second, _) = served(width: 64)
        let (third, _) = served(width: 64)

        _ = await pictures.answer(first, ask: .chosen, inFeed: false)
        try await Task.sleep(for: .milliseconds(20))  // gives the files different times of use
        _ = await pictures.answer(second, ask: .chosen, inFeed: false)
        try await Task.sleep(for: .milliseconds(20))
        _ = await pictures.cache.file(for: first)  // the first is used again, so the second is the oldest
        try await Task.sleep(for: .milliseconds(20))
        _ = await pictures.answer(third, ask: .chosen, inFeed: false)

        #expect(await pictures.cache.file(for: first) != nil)
        #expect(await pictures.cache.file(for: second) == nil)
        #expect(await pictures.cache.file(for: third) != nil)
    }

    @Test func removingAllLeavesNothingOfThePicturesKept() async {
        let (address, _) = served()
        let pictures = pictures()
        _ = await pictures.answer(address, ask: .chosen, inFeed: false)

        await PictureCache.removeAll(in: pictures.cache.folder)

        #expect(await pictures.cache.file(for: address) == nil)
        #expect(!FileManager.default.fileExists(atPath: pictures.cache.folder.path))
    }

    // MARK: How many are fetched at once

    /// Starts an answer for each address, all at once, as a note with many pictures does.
    private func chooseAll(_ addresses: [URL], in pictures: WebPictures) -> Task<[PictureAnswer], Never> {
        let asking = addresses.map { address in Task { await pictures.answer(address, ask: .chosen, inFeed: false) } }
        return Task {
            var answers: [PictureAnswer] = []
            for asked in asking { answers.append(await asked.value) }
            return answers
        }
    }

    @Test func noMoreThanFourPicturesAreFetchedAtOnceAndTheRestWaitTheirTurn() async throws {
        let resolver = HeldResolver()
        let pictures = pictures(resolver: resolver.resolver)
        let addresses = (0..<10).map { _ in served().address }

        let all = chooseAll(addresses, in: pictures)
        try #require(await eventually { resolver.active == 4 })
        try await Task.sleep(for: .milliseconds(200))  // gives a fifth fetch time to start, which it must not
        #expect(resolver.active == 4)
        resolver.release()
        let answers = await all.value

        #expect(answers.count == 10)
        #expect(answers.allSatisfy(isLoaded), "a picture that waited is fetched, not refused")
        #expect(resolver.peak == 4)
    }

    @Test func noMoreThanTwoPicturesAreFetchedAtOnceFromOneWebsite() async throws {
        let resolver = HeldResolver()
        let pictures = pictures(resolver: resolver.resolver)
        let host = PictureStub.newHost()
        let addresses = (0..<6).map { index -> URL in
            let text = "https://\(host)/\(index).png"
            PictureStub.answer(text, with: .body([SamplePicture.png()]))
            return URL(string: text)!
        }

        let all = chooseAll(addresses, in: pictures)
        try #require(await eventually { resolver.active == 2 })
        try await Task.sleep(for: .milliseconds(200))  // gives a third fetch time to start, which it must not
        #expect(resolver.active == 2)
        resolver.release()
        let answers = await all.value

        #expect(answers.allSatisfy(isLoaded))
        #expect(resolver.peak == 2)
    }

    @Test func aWebsiteAtItsLimitDoesNotHoldUpAnother() async throws {
        let resolver = HeldResolver()
        let pictures = pictures(resolver: resolver.resolver)
        let busy = PictureStub.newHost()
        let crowded = (0..<3).map { index -> URL in
            let text = "https://\(busy)/\(index).png"
            PictureStub.answer(text, with: .body([SamplePicture.png()]))
            return URL(string: text)!
        }
        let other = served().address

        let all = chooseAll(crowded + [other], in: pictures)

        try #require(await eventually { resolver.active == 3 })
        #expect(resolver.names.filter { $0 == busy }.count == 2)
        resolver.release()
        #expect(await all.value.allSatisfy(isLoaded))
    }

    // MARK: Nothing left behind

    private func fetched(in folder: TemporaryFolder, name: String = "fetched") throws -> FetchedPicture {
        let file = folder.url.appending(path: name)
        try SamplePicture.png().write(to: file)
        return FetchedPicture(file: file, format: .png, width: 8, height: 8)
    }

    @Test func aFileTheCacheCannotKeepIsRemoved() async throws {
        let blocked = folder.url.appending(path: "Blocked")
        try Data("a file where the cache's folder should be".utf8).write(to: blocked)
        let cache = PictureCache(folder: blocked)
        let picture = try fetched(in: folder)

        await #expect(throws: (any Error).self) {
            try await cache.store(picture, for: URL(string: "https://example.com/a.png")!, generation: cache.generation)
        }

        #expect(!FileManager.default.fileExists(atPath: picture.file.path))
    }

    @Test func aFileStoredAfterTheCacheWasEmptiedIsRemovedAndNothingIsKept() async throws {
        let cache = PictureCache(folder: folder.url.appending(path: "Cache"))
        let address = URL(string: "https://example.com/a.png")!
        let before = cache.generation
        let picture = try fetched(in: folder)

        await PictureCache.removeAll(in: cache.folder)

        await #expect(throws: CancellationError.self) { try await cache.store(picture, for: address, generation: before) }
        #expect(!FileManager.default.fileExists(atPath: picture.file.path))
        #expect(await cache.file(for: address) == nil)
        #expect(!FileManager.default.fileExists(atPath: cache.folder.path), "storing recreated nothing")
        #expect(cache.generation != before)
    }

    @Test func whatAnEarlierRunLeftWhereFetchesAreWrittenIsSweptAtTheFirstUse() async throws {
        let (address, _) = served()
        let pictures = pictures()
        let stale = pictures.cache.incoming.appending(path: ".incoming-left-by-a-run-that-quit")
        try FileManager.default.createDirectory(at: pictures.cache.incoming, withIntermediateDirectories: true)
        try SamplePicture.png().write(to: stale)

        let answer = await pictures.answer(address, ask: .chosen, inFeed: false)

        #expect(isLoaded(answer))
        #expect(!FileManager.default.fileExists(atPath: stale.path))
    }

    @Test func aPictureThatArrivesAfterTheLibraryWasDisconnectedIsNotKept() async throws {
        let resolver = HeldResolver()
        let pictures = pictures(resolver: resolver.resolver)
        let (address, requests) = served()

        let answer = Task { await pictures.answer(address, ask: .chosen, inFeed: false) }
        try #require(await eventually { resolver.active == 1 })
        await PictureCache.removeAll(in: pictures.cache.folder)
        resolver.release()

        #expect(await answer.value == .refused(.failed))
        #expect(requests() == 0, "the address was checked after the disconnect, so nothing was asked of the website")
        #expect(await pictures.cache.file(for: address) == nil)
        #expect(
            !FileManager.default.fileExists(atPath: pictures.cache.folder.path),
            "no folder was made, not even the one fetches are written in")
    }

    @Test func theLockTheEmptyingTakesIsFreeWhileTheCacheTrims() async throws {
        let free = Mutex<Bool?>(nil)
        let cache = PictureCache(folder: folder.url.appending(path: "Cache")) { free.withLock { $0 = PictureCache.isUnlocked } }

        _ = try await cache.store(fetched(in: folder), for: URL(string: "https://example.com/a.png")!, generation: cache.generation)

        #expect(free.withLock { $0 } == true)
    }

    @Test func aPictureWaitingItsTurnWhenTheLibraryIsDisconnectedIsNeverFetched() async throws {
        let resolver = HeldResolver()
        let queue = PictureQueue(total: 1, perHost: 1)
        let pictures = pictures(resolver: resolver.resolver, queue: queue)
        let (first, _) = served()
        let (second, secondRequests) = served()

        let running = Task { await pictures.answer(first, ask: .chosen, inFeed: false) }
        try #require(await eventually { resolver.active == 1 })
        let waiting = Task { await pictures.answer(second, ask: .chosen, inFeed: false) }
        try #require(await eventuallyAsking { await queue.waitingCount == 1 })
        await PictureCache.removeAll(in: pictures.cache.folder)
        resolver.release()

        #expect(await running.value == .refused(.failed))
        #expect(await waiting.value == .refused(.failed))
        #expect(secondRequests() == 0)
        #expect(resolver.names.count == 1, "the second was not even looked up")
    }
}
