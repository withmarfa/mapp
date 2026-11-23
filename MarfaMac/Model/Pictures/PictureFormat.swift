import Foundation
import ImageIO

/// The kinds of picture that are loaded from a web address, told by the first bytes of what arrived and never by what
/// the server said it was. An SVG is not among them: it can carry script.
nonisolated enum PictureFormat: String, CaseIterable, Sendable {
    case png, jpeg, gif, webp, heic, avif

    /// How many bytes it takes to tell the formats apart.
    static let prefixLength = 64

    init?(sniffing bytes: Data) {
        let start = bytes.startIndex
        func at(_ offset: Int, _ expected: [UInt8]) -> Bool {
            bytes.count >= offset + expected.count && Array(bytes[(start + offset)..<(start + offset + expected.count)]) == expected
        }
        func ascii(_ text: String) -> [UInt8] { Array(text.utf8) }
        if at(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) {
            self = .png
        } else if at(0, [0xFF, 0xD8, 0xFF]) {
            self = .jpeg
        } else if at(0, ascii("GIF87a")) || at(0, ascii("GIF89a")) {
            self = .gif
        } else if at(0, ascii("RIFF")) && at(8, ascii("WEBP")) {
            self = .webp
        } else if at(4, ascii("ftyp")) {
            // The brands of an ISO base media file: the major brand, then the compatible ones to the end of the box.
            let size = bytes.count >= 4 ? bytes[start..<(start + 4)].reduce(0) { $0 << 8 | Int($1) } : 0
            var brands: [String] = []
            var offset = 8
            while offset + 4 <= min(max(size, 16), bytes.count) {
                if offset != 12 { brands.append(String(decoding: bytes[(start + offset)..<(start + offset + 4)], as: UTF8.self)) }
                offset += 4
            }
            if brands.contains(where: { $0 == "avif" || $0 == "avis" }) {
                self = .avif
            } else if brands.contains(where: { ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs"].contains($0) }) {
                self = .heic
            } else {
                return nil
            }
        } else {
            return nil
        }
    }

    var fileExtension: String { self == .jpeg ? "jpg" : rawValue }

    /// The most pixels a picture may have. The page decodes what it is given, and a small file can hold a very large
    /// image.
    static let largestPixelCount = 100_000_000

    /// The size of the picture in pixels, from the image the file holds; nil where the system cannot read it as one.
    static func pixelSize(of file: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(file as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return (width, height)
    }
}
