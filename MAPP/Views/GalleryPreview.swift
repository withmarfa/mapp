import Foundation
import ImageIO
import UniformTypeIdentifiers

nonisolated struct GalleryPreviewRequest: Hashable {
    let id: ItemID
    let version: ItemVersion
    let body: String?
}

enum GalleryPreview {
    static func image(for item: Item, body: String?, in library: any ItemLibrary) async -> CGImage? {
        if case .file(let type, _) = item.content {
            guard type.conforms(to: .image), let url = try? await library.fileURL(of: item.id), !Task.isCancelled else { return nil }
            return await thumbnail(at: url)
        }
        guard let body else { return nil }
        for reference in GalleryImageReferences.inBody(body).prefix(8) {
            guard !Task.isCancelled else { return nil }
            guard let file = await library.openEmbeddedFile(reference, in: item.id),
                  UTType(filenameExtension: file.url.pathExtension)?.conforms(to: .image) == true,
                  file.length <= 32 << 20,
                  let data = await file.read(at: 0, count: Int(file.length)), !Task.isCancelled
            else { continue }
            if let image = await thumbnail(data: data) { return image }
        }
        return nil
    }

    @concurrent private static func thumbnail(at url: URL) async -> CGImage? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return thumbnail(source)
    }

    @concurrent private static func thumbnail(data: Data) async -> CGImage? {
        guard !Task.isCancelled, let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
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

/// Reads thumbnail candidates without changing Markdown. Resolution uses the editor's checked file descriptors.
nonisolated enum GalleryImageReferences {
    static func inBody(_ body: String) -> [EmbedReference] {
        var result: [EmbedReference] = []
        var fence: (marker: Character, count: Int)?
        for line in body.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let first = trimmed.first, first == "`" || first == "~" {
                let count = trimmed.prefix(while: { $0 == first }).count
                if count >= 3 {
                    if let open = fence {
                        if open.marker == first && count >= open.count && trimmed.dropFirst(count).trimmingCharacters(in: .whitespaces).isEmpty { fence = nil }
                    } else { fence = (first, count) }
                    continue
                }
            }
            guard fence == nil, !line.hasPrefix("    "), !line.hasPrefix("\t") else { continue }
            let text = String(line).replacing(inlineCode, with: "")
            for match in text.matches(of: image) {
                guard text[..<match.range.lowerBound].reversed().prefix(while: { $0 == "\\" }).count.isMultiple(of: 2) else { continue }
                if let wiki = match.output.1 {
                    let name = String(wiki.prefix { $0 != "|" && $0 != "#" }).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { result.append(.name(name)) }
                } else if let path = match.output.2 {
                    let value = path.hasPrefix("<") ? String(path.dropFirst().dropLast()) : String(path)
                    if !EmbedPaths.isAddress(value) { result.append(.path(value)) }
                }
            }
        }
        return result
    }

    private nonisolated(unsafe) static let inlineCode = /`+[^`]*`+/
    private nonisolated(unsafe) static let image = /!\[\[([^\]\n]+)\]\]|!\[[^\]\n]*\]\((<[^>\n]+>|(?:[^\s()]|\([^()\n]*\))+)(?:[ \t]+[^\n)]*)?\)/
}
