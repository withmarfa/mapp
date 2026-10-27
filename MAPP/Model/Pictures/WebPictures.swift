import Foundation

/// What a note's page is told about a picture at a web address.
nonisolated enum PictureAnswer: Equatable, Sendable {
    /// The picture is on this Mac, at this file in the cache.
    case loaded(URL)
    /// Nothing was fetched, and the person may choose to.
    case waiting
    /// Nothing is fetched, because the Remote Pictures setting is Never.
    case off
    case refused(PictureFailure)
}

/// How the page came to ask for a picture.
nonisolated enum PictureAsk: String, Sendable {
    /// The page is drawing the picture and the person has said nothing about it.
    case drawing
    /// The person chose to load it, one picture or all those waiting.
    case chosen
    /// Printing or exporting: only what the cache holds.
    case cached
}

/// Decides which pictures at web addresses are fetched, by the Remote Pictures setting, and keeps what is fetched.
/// The page asks here for every one, and nothing else in the app fetches them.
@MainActor final class WebPictures {
    let cache: PictureCache
    private let fetcher: PictureFetcher
    private let defaults: UserDefaults
    private let queue: PictureQueue
    private var fetching: [URL: Task<Result<URL, PictureFailure>, Never>] = [:]

    init(
        cache: PictureCache = PictureCache(), fetcher: PictureFetcher = PictureFetcher(), defaults: UserDefaults = .standard,
        queue: PictureQueue = PictureQueue()
    ) {
        self.cache = cache
        self.fetcher = fetcher
        self.defaults = defaults
        self.queue = queue
    }

    /// Read at each question, so a change in Settings applies to the next one.
    var setting: RemotePictureSetting { RemotePictureSetting.current(in: defaults) }

    /// Answers a question about the picture at `address`. `inFeed` is whether the item holding the picture is in the
    /// feed tier (`Item.tier`): Always loads a picture there without asking, and asks in the library tier, where the
    /// person's own notes are, since the website would learn they opened one.
    ///
    /// A picture already kept shows under every setting, since showing it asks nothing of the website.
    func answer(_ address: URL, ask: PictureAsk, inFeed: Bool) async -> PictureAnswer {
        if address.scheme?.lowercased() != "https" { return .refused(.notSecure) }
        if let kept = await cache.file(for: address) { return .loaded(kept) }
        let setting = setting
        switch ask {
        case .cached: return .waiting
        case .drawing:
            switch setting {
            case .never: return .off
            case .ask: return .waiting
            case .always: if !inFeed { return .waiting }
            }
        case .chosen:
            if setting == .never { return .off }
        }
        return await load(address)
    }

    /// Fetches the picture, once however many ask at the same time, and a few at a time (`PictureQueue`).
    ///
    /// The library may be disconnected while a fetch is waiting or on its way, which empties the cache
    /// (`PictureCache.generation`): such a fetch is not started, or its picture is not stored.
    private func load(_ address: URL) async -> PictureAnswer {
        let generation = cache.generation
        let task = fetching[address] ?? Task { [cache, fetcher, queue] in
            await cache.sweepIncomingOnce()
            return await queue.run(host: address.host(percentEncoded: false)?.lowercased() ?? "") {
                do {
                    guard cache.generation == generation else { throw CancellationError() }
                    let picture = try await fetcher.fetch(address, into: cache.incoming)
                    return .success(try await cache.store(picture, for: address, generation: generation))
                } catch let failure as PictureFailure {
                    return .failure(failure)
                } catch {
                    return .failure(.failed)
                }
            }
        }
        fetching[address] = task
        let result = await task.value
        fetching[address] = nil
        switch result {
        case .success(let file): return .loaded(file)
        case .failure(let failure): return .refused(failure)
        }
    }
}

extension WebPictures {
    /// The one used by every window, so a picture two notes share is fetched once.
    static let standard = WebPictures()
}
