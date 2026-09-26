import AppKit
import UniformTypeIdentifiers
import WebKit

/// Hands the page the files of the notes folder that a note points at, such as its images, when the page asks
/// for one by its path in the folder, and nothing outside the folder: a path that leads out of it, or through a
/// link, is refused. The page loads nothing itself.
final class NoteFiles: NSObject, WKScriptMessageHandlerWithReply {
    /// The notes folder, asked for each time, since the person can change it.
    var root: () -> URL? = { nil }

    /// Replies with the image as a data URL the page can show, or nothing.
    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage,
        replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void
    ) {
        guard let path = message.body as? String, let file = file(at: path),
              let type = UTType(filenameExtension: file.pathExtension), type.conforms(to: .image),
              let data = try? Data(contentsOf: file)
        else { return replyHandler(nil, nil) }
        replyHandler("data:\(type.preferredMIMEType ?? "image/png");base64,\(data.base64EncodedString())", nil)
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

/// Images on a pasteboard, as files to put in the attachments folder: image files by their own names, and
/// image data, as a screenshot is copied, under a name of the moment.
enum PastedImages {
    static func files(on pasteboard: NSPasteboard) -> [(name: String, data: Data)] {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: [UTType.image.identifier],
        ]) as? [URL] ?? []
        if !urls.isEmpty {
            return urls.compactMap { url in (try? Data(contentsOf: url)).map { (url.lastPathComponent, $0) } }
        }
        let types = [NSPasteboard.PasteboardType.png, NSPasteboard.PasteboardType(UTType.jpeg.identifier)]
        if let type = pasteboard.availableType(from: types), let data = pasteboard.data(forType: type) {
            return [(name(extension: type == .png ? "png" : "jpg"), data)]
        }
        guard pasteboard.canReadObject(forClasses: [NSImage.self], options: nil),
              let image = NSImage(pasteboard: pasteboard), let tiff = image.tiffRepresentation,
              let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:])
        else { return [] }
        return [(name(extension: "png"), png)]
    }

    private static func name(extension ext: String) -> String {
        let stamp = Date.now.formatted(.verbatim(
            "\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)",
            timeZone: .current, calendar: .current
        ))
        return String(localized: "Image \(stamp).\(ext)")
    }
}
