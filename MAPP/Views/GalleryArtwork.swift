import AppKit
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// The picture a gallery card shows in its thumbnail, in place of the drawn page.
nonisolated struct GalleryArtwork: @unchecked Sendable {
    let image: CGImage
    /// A document's first page, which reads from its top edge; a photograph is centered.
    let isDocument: Bool
}

/// Makes and keeps the pictures cards show. Only a visible card asks, a file is fetched only when it is small,
/// and a picture is kept by what decides it (`Basis`) and rough width, so scrolling back or resizing a little costs nothing.
enum GalleryArtworkCache {
    /// What decides a card's picture: the item's own version, and for a note the state of each embed its picture
    /// is chosen from (`EmbedState`: what the embed is bound to, and that file's title, state and version). A file
    /// binned, renamed or restored changes none of the note's own facts, so it is read from the library here, and
    /// a card whose basis changes makes its picture again.
    nonisolated struct Basis: Hashable, Sendable {
        let item: ItemID
        let version: ItemVersion
        let embeds: [EmbedState]
        /// The image files attached to it, which a bookmark's cover is: each one's version and whether it is in the bin.
        let attached: [Attached]
    }

    nonisolated struct Attached: Hashable, Sendable {
        let file: ItemID
        let version: ItemVersion
        let trashed: Bool
    }

    /// Reads the embeds' files from the library, so a view calling it follows them as it follows its item.
    /// `attachments` are the items attached to it, which the caller read once (`CardAttachments`).
    static func basis(of item: Item, attachments: [Item], in library: any ItemLibrary) -> Basis {
        let embeds = item.boundEmbeds.prefix(GalleryPreview.embedLimit).map { library.embedState(of: $0) }
        let attached = attachments
            .filter(\.isFile).map { Attached(file: $0.id, version: $0.version, trashed: $0.state == .trashed) }
            .sorted { $0.file.rawValue < $1.file.rawValue }
        return Basis(item: item.id, version: item.version, embeds: embeds, attached: attached)
    }

    nonisolated private final class Key: NSObject {
        let basis: Basis
        let bucket: Int

        init(_ basis: Basis, _ bucket: Int) {
            self.basis = basis
            self.bucket = bucket
        }

        override var hash: Int {
            var hasher = Hasher()
            hasher.combine(basis)
            hasher.combine(bucket)
            return hasher.finalize()
        }

        override func isEqual(_ object: Any?) -> Bool {
            guard let other = object as? Key else { return false }
            return other.basis == basis && other.bucket == bucket
        }
    }

    private final class Entry {
        let artwork: GalleryArtwork?
        init(_ artwork: GalleryArtwork?) { self.artwork = artwork }
    }

    private static let storage: NSCache<Key, Entry> = {
        let cache = NSCache<Key, Entry>()
        cache.countLimit = 900
        cache.totalCostLimit = 160 << 20
        return cache
    }()

    /// Widths round up to a step so a window resize does not make every card again.
    private static let step: CGFloat = 96

    private static func bucket(_ width: CGFloat) -> CGFloat { (width / step).rounded(.up) * step }

    /// What is already made, so a card scrolled back into view draws its picture in its first frame.
    static func peek(_ basis: Basis, width: CGFloat) -> GalleryArtwork? {
        storage.object(forKey: Key(basis, Int(bucket(width))))?.artwork
    }

    /// What making an item's picture came to.
    enum Outcome: Sendable {
        case picture(GalleryArtwork)
        /// The item has no picture to show.
        case none
        /// It couldn't be made now, as when a file can't be fetched offline: not kept, so a view asks again when it
        /// next shows.
        case failed
    }

    /// How many pictures are made at once, so a screenful of cards does not fetch and decode every file together.
    static let gate = PreviewGate(limit: 3)

    static func outcome(for item: Item, attachments: [Item], width: CGFloat, scale: CGFloat, in library: any ItemLibrary) async -> Outcome {
        let bucket = bucket(width)
        let key = Key(basis(of: item, attachments: attachments, in: library), Int(bucket))
        if let entry = storage.object(forKey: key) { return entry.artwork.map(Outcome.picture) ?? .none }
        // A card that leaves the screen cancels its task, which ends the wait for a place or the work in it.
        guard let made = try? await gate.run({ await make(for: item, attachments: attachments, width: bucket, scale: scale, in: library) }),
              !Task.isCancelled
        else { return .failed }
        storage.setObject(Entry(made), forKey: key, cost: made.map { $0.image.bytesPerRow * $0.image.height } ?? 1)
        return made.map(Outcome.picture) ?? .none
    }

    /// Nil when there is no picture or it couldn't be made now (`outcome` tells the two apart).
    static func artwork(for item: Item, attachments: [Item], width: CGFloat, scale: CGFloat, in library: any ItemLibrary) async -> GalleryArtwork? {
        if case .picture(let artwork) = await outcome(for: item, attachments: attachments, width: width, scale: scale, in: library) { artwork } else { nil }
    }

    /// Nil for a picture that couldn't be made now; `.some(nil)` for an item with none.
    private static func make(for item: Item, attachments: [Item], width: CGFloat, scale: CGFloat, in library: any ItemLibrary) async -> GalleryArtwork?? {
        if case .file(let type, _) = item.content, !type.conforms(to: .image) {
            let url: URL?
            do { url = try await GalleryPreview.fileURL(of: item, in: library) } catch { return nil }
            guard let url, !Task.isCancelled else { return .some(nil) }
            let isVideo = CardPicture.kind(of: type) == .video
            let image = await quickLook(at: url, width: width, height: isVideo ? width * 0.75 : width * 1.5, scale: scale)
            return .some(image.map { GalleryArtwork(image: $0, isDocument: !isVideo) })
        }
        // Twice the side, as a tall picture fills a square by its width; a list row's is far smaller than a card's.
        switch await GalleryPreview.image(for: item, attachments: attachments, maxPixels: min(800, Int(width * scale * 2)), in: library) {
        case .image(let image): return GalleryArtwork(image: image, isDocument: false)
        case .none: return .some(nil)
        case .failed: return nil
        }
    }

    /// A document's request is tall, since a page fits inside it by its height; the card then fills its frame from the
    /// page's top. A video's is wide, as its frame is.
    @concurrent private static func quickLook(at url: URL, width: CGFloat, height: CGFloat, scale: CGFloat) async -> CGImage? {
        let request = ThumbnailRequest(QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: width, height: height), scale: scale, representationTypes: .thumbnail))
        // The generator keeps working on a request after its task is cancelled unless it is told to stop.
        return await withTaskCancellationHandler {
            try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request.value).cgImage
        } onCancel: {
            QLThumbnailGenerator.shared.cancel(request.value)
        }
    }
}

private nonisolated struct ThumbnailRequest: @unchecked Sendable {
    let value: QLThumbnailGenerator.Request
    init(_ value: QLThumbnailGenerator.Request) { self.value = value }
}

/// Lets a few pieces of work run at once and the rest wait their turn in order. A waiting caller whose task is
/// cancelled leaves the queue at once and holds no place.
actor PreviewGate {
    private let limit: Int
    private var running = 0
    private var waiting: [(id: UUID, continuation: CheckedContinuation<Void, any Error>)] = []

    init(limit: Int) { self.limit = limit }

    nonisolated(nonsending) func run<T>(_ work: () async -> T) async throws -> T {
        try await acquire()
        let result = await work()
        await release()
        return result
    }

    fileprivate func acquire() async throws {
        try Task.checkCancellation()
        if running < limit {
            running += 1
            return
        }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiting.append((id, continuation))
                }
            }
        } onCancel: {
            Task { await self.leave(id) }
        }
    }

    private func leave(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    fileprivate func release() {
        if waiting.isEmpty {
            running -= 1
        } else {
            // The place passes straight to the next in line.
            waiting.removeFirst().continuation.resume()
        }
    }
}
