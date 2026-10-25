import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GalleryPreview {
    /// An image file's picture, or a note's first embedded image that Marfa's core bound to a file item.
    static func image(for item: Item, in library: any ItemLibrary) async -> CGImage? {
        let candidates: [Item] = switch item.content {
        case .file: [item]
        case .markdown: item.boundEmbeds.prefix(8).compactMap { embed in
            if case .resolved(let id) = embed.resolution { library.item(id) } else { nil }
        }
        }
        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            guard case .file(let type, _) = candidate.content, type.conforms(to: .image),
                  let url = await fileURL(of: candidate, in: library), !Task.isCancelled
            else { continue }
            if let image = await thumbnail(at: url) { return image }
        }
        return nil
    }

    /// The file, fetched when it is small enough that a grid of cards can afford it. A larger file shows its type's
    /// icon until the person opens it.
    static func fileURL(of item: Item, in library: any ItemLibrary) async -> URL? {
        guard case .file(_, let byteCount) = item.content, byteCount <= fetchLimit else { return nil }
        return try? await library.fileURL(of: item.id)
    }

    private static let fetchLimit: Int64 = 8 << 20

    @concurrent private static func thumbnail(at url: URL) async -> CGImage? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source)
    }

    nonisolated private static func thumbnail(_ source: CGImageSource) -> CGImage? {
        CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary)
    }
}
