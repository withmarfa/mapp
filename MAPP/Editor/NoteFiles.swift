import AppKit
import UniformTypeIdentifiers
import WebKit

/// Hands the page the files of the notes folder that a note points at, such as its images, when the page asks
/// for one by its path in the folder, and nothing outside the folder: a path that leads out of it, or through a
/// link, is refused. The page loads nothing itself.
final class NoteFiles: NSObject, WKScriptMessageHandlerWithReply {
    /// The notes folder, asked for each time, since the person can change it.
    var root: () -> URL? = { nil }

    /// The largest image the page is given, and the largest taken in by a paste or drop.
    nonisolated static let largestImage = 50 * 1024 * 1024

    /// Replies with the image as a data URL the page can show, or nothing. The file is read away from the main
    /// thread, and only if it is an ordinary file of a reasonable size.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let path = message.body as? String, let file = file(at: path),
              let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image)
        else { return replyHandler(nil, nil) }
        let mime = type.preferredMIMEType ?? "image/png"
        Task.detached {
            let reply = Self.readImage(file).map { "data:\(mime);base64,\($0.base64EncodedString())" }
            await MainActor.run { replyHandler(reply, nil) }
        }
    }

    /// An ordinary file's bytes, when it is no larger than the page is given.
    nonisolated static func readImage(_ file: URL) -> Data? {
        guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true, (values.fileSize ?? .max) <= largestImage
        else { return nil }
        return try? Data(contentsOf: file)
    }

    /// The file at a path in the notes folder, when it is inside the folder and reached without a symbolic link.
    func file(at path: String) -> URL? {
        guard let root = root()?.standardizedFileURL.resolvingSymlinksInPath() else { return nil }
        let components = path.split(separator: "/").map(String.init)
        guard !components.isEmpty, !components.contains(where: { $0 == ".." || $0 == "." }) else { return nil }
        var file = root
        for component in components { file.append(path: component, directoryHint: .notDirectory) }
        guard file.resolvingSymlinksInPath().path == file.path, file.path.hasPrefix(root.path + "/") else { return nil }
        return file
    }
}

/// Images to put in the attachments folder: image files by their own names, and image data, as a screenshot
/// is copied, under a name of the moment.
enum PastedImages {
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
                return NoteFiles.readImage(url).map { (url.lastPathComponent, $0) }
            }
        }
    }

    private static func name(extension ext: String) -> String {
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
        return String(localized: "Image \(stamp).\(ext)")
    }
}
