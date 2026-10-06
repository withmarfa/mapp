import AppKit
import UniformTypeIdentifiers

/// Images to put in the attachments folder: image files by their own names, and image data, as a screenshot
/// is copied, under a name of the moment.
enum PastedImages {
    /// The largest image taken in by a paste or drop.
    nonisolated static let largestImage = 50 * 1024 * 1024

    /// An image to attach: a file still to be read, or bytes already in hand.
    enum Source: Sendable {
        case file(URL)
        case data(name: String, Data)
    }

    static func sources(on pasteboard: NSPasteboard) -> [Source] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        if !urls.isEmpty { return urls.map(Source.file) }
        let types = [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
        if let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) {
            return [.data(name: name(extension: type == .png ? "png" : "jpg"), data)]
        }
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
              let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return [] }
        return [.data(name: name(extension: "png"), png)]
    }

    /// The images' names and bytes, read away from the main thread, since a file can be large. A file chosen in
    /// an open panel is read under its security scope.
    @concurrent nonisolated static func read(_ sources: [Source]) async -> [(name: String, data: Data)] {
        sources.compactMap { source in
            switch source {
            case .data(let name, let data):
                return (name, data)
            case .file(let url):
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                return readImage(url).map { (url.lastPathComponent, $0) }
            }
        }
    }

    /// An ordinary file's bytes, when it is no larger than an image is taken in at.
    nonisolated static func readImage(_ file: URL) -> Data? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= largestImage
        else { return nil }
        return try? Data(contentsOf: file)
    }

    private static func name(extension ext: String) -> String {
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
        return String(localized: "Image \(stamp).\(ext)")
    }
}
