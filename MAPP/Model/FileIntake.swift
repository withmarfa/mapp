import Foundation
import UniformTypeIdentifiers

/// Turns what a drop or a nearby device hands the window into files on disk, the one form `Browser.importFiles`
/// takes. A file dragged from Finder is read where it is; a photo or scan from an iPhone arrives as data held only
/// while the system's handler runs, so it is copied into a folder of the app's own, which `Gathered.remove` empties.
@MainActor
enum FileIntake {
    /// The kinds of content the window asks nearby devices for: a photo or sketch is an image, a scan a PDF.
    nonisolated static let deviceTypes: [UTType] = [.image, .pdf]

    struct Gathered {
        let urls: [URL]
        /// How many of the providers could not be read as a file, such as a link dragged from a browser.
        let unreadable: Int
        fileprivate let folder: URL?

        /// Removes the copies made from device content. A file read where it is stays where it is.
        func remove() {
            if let folder { try? FileManager.default.removeItem(at: folder) }
        }
    }

    static func files(from providers: [NSItemProvider]) async -> Gathered {
        var urls: [URL] = []
        var unreadable = 0
        var folder: URL?
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                if let url = await fileURL(of: provider), url.isFileURL { urls.append(url) } else { unreadable += 1 }
            } else if let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .data) }) {
                let staging = folder ?? QuickLookFile.processFolder("Device Import").appending(path: UUID().uuidString, directoryHint: .isDirectory)
                folder = staging
                if let url = await stage(provider, as: type, in: staging) { urls.append(url) } else { unreadable += 1 }
            } else {
                unreadable += 1
            }
        }
        return Gathered(urls: urls, unreadable: unreadable, folder: folder)
    }

    /// The file a provider names, where it is.
    static func fileURL(of provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
        }
    }

    /// Copies the content, which the system removes once its handler returns, to a file named after it, in a folder of
    /// its own inside `folder`, since several photos of one device share a name.
    private static func stage(_ provider: NSItemProvider, as type: UTType, in folder: URL) async -> URL? {
        let folder = folder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let name = QuickLookFile.name(for: provider.suggestedName ?? String(localized: "Photo"), type: type)
        return await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                guard let url else { return continuation.resume(returning: nil) }
                let copy = folder.appending(path: name, directoryHint: .notDirectory)
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try FileManager.default.copyItem(at: url, to: copy)
                    continuation.resume(returning: copy)
                } catch {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
