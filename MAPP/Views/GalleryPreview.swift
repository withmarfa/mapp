import Foundation
import ImageIO
import UniformTypeIdentifiers

enum GalleryPreview {
    /// What a card can show: a picture, nothing, or nothing for now, as when a file can't be fetched offline.
    enum Picture {
        case image(CGImage)
        case none
        case failed
    }

    /// An image file's picture, or a note's first embedded image, which the embed resolver opens.
    static func image(for item: Item, in library: any ItemLibrary) async -> Picture {
        switch item.content {
        case .file(let type, _):
            guard type.conforms(to: .image) else { return .none }
            let url: URL
            do {
                guard let fetched = try await fileURL(of: item, in: library) else { return .none }
                url = fetched
            } catch {
                return .failed
            }
            return await thumbnail(at: url).map(Picture.image) ?? .none
        case .markdown:
            var failed = false
            for embed in item.boundEmbeds.prefix(8) {
                guard !Task.isCancelled else { return .failed }
                let resolution = await library.openEmbeddedFile(EmbedReference(text: embed.text), in: item.id, if: isSmallImage)
                switch resolution {
                case .file(let file):
                    if let image = await thumbnail(of: file) { return .image(image) }
                case .unavailable:
                    failed = true
                case .missing:
                    continue
                }
            }
            return failed ? .failed : .none
        }
    }

    /// The file, fetched when it is small enough that a grid of cards can afford it. A larger file shows its type's
    /// icon until the person opens it.
    static func fileURL(of item: Item, in library: any ItemLibrary) async throws -> URL? {
        guard case .file(_, let byteCount) = item.content, byteCount <= fetchLimit else { return nil }
        return try await library.fileURL(of: item.id)
    }

    private static func isSmallImage(_ item: Item) -> Bool {
        guard case .file(let type, let byteCount) = item.content else { return false }
        return type.conforms(to: .image) && byteCount <= fetchLimit
    }

    nonisolated private static let fetchLimit: Int64 = 8 << 20

    /// Read from the descriptor the resolver checked, never reopened by path.
    @concurrent private static func thumbnail(of file: OpenFile) async -> CGImage? {
        guard file.length <= fetchLimit, let data = await file.read(at: 0, count: Int(file.length)),
              !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return thumbnail(source)
    }

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
