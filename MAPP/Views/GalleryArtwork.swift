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
/// and a picture is kept by item, version and rough width, so scrolling back or resizing a little costs nothing.
enum GalleryArtworkCache {
    private final class Entry {
        let artwork: GalleryArtwork?
        init(_ artwork: GalleryArtwork?) { self.artwork = artwork }
    }

    private static let storage: NSCache<NSString, Entry> = {
        let cache = NSCache<NSString, Entry>()
        cache.countLimit = 900
        return cache
    }()

    /// Widths round up to a step so a window resize does not make every card again.
    private static let step: CGFloat = 96

    private static func bucket(_ width: CGFloat) -> CGFloat { (width / step).rounded(.up) * step }

    private static func key(_ item: Item, _ bucket: CGFloat) -> NSString {
        "\(item.id.rawValue)|\(item.version.rawValue)|\(Int(bucket))" as NSString
    }

    /// What is already made, so a card scrolled back into view draws its picture in its first frame.
    static func peek(_ item: Item, width: CGFloat) -> GalleryArtwork? {
        storage.object(forKey: key(item, bucket(width)))?.artwork
    }

    /// Nil when there is no picture. A picture that couldn't be made now, as when a file can't be fetched offline,
    /// is not kept, so the card asks again when it next shows.
    static func artwork(for item: Item, width: CGFloat, scale: CGFloat, in library: any ItemLibrary) async -> GalleryArtwork? {
        let bucket = bucket(width)
        let key = key(item, bucket)
        if let entry = storage.object(forKey: key) { return entry.artwork }
        let made = await make(for: item, width: bucket, scale: scale, in: library)
        guard let made else { return nil }
        if !Task.isCancelled { storage.setObject(Entry(made), forKey: key) }
        return made
    }

    /// Nil for a picture that couldn't be made now; `.some(nil)` for an item with none.
    private static func make(for item: Item, width: CGFloat, scale: CGFloat, in library: any ItemLibrary) async -> GalleryArtwork?? {
        if case .file(let type, _) = item.content, !type.conforms(to: .image) {
            let url: URL?
            do { url = try await GalleryPreview.fileURL(of: item, in: library) } catch { return nil }
            guard let url, !Task.isCancelled else { return .some(nil) }
            return .some(await quickLook(at: url, width: width, scale: scale).map { GalleryArtwork(image: $0, isDocument: true) })
        }
        switch await GalleryPreview.image(for: item, in: library) {
        case .image(let image): return GalleryArtwork(image: image, isDocument: false)
        case .none: return .some(nil)
        case .failed: return nil
        }
    }

    /// A tall request, since a page fits inside it by its height; the card then fills its frame from the page's top.
    @concurrent private static func quickLook(at url: URL, width: CGFloat, scale: CGFloat) async -> CGImage? {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: width, height: width * 1.5), scale: scale, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }
}
