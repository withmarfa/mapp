import Foundation
import UniformTypeIdentifiers

/// A file as an app that chooses by name can be given it (Quick Look, a browser). Quick Look picks a previewer from the file's name, and a Marfa copy keeps
/// a file's bytes under their hash with no extension, so it is shown a copy of them named after the item.
nonisolated struct QuickLookFile {
    let folder: URL
    let url: URL

    /// The item's title, made safe as a file name and ending in an extension that fits `type`.
    static func name(for title: String, type: UTType) -> String {
        let unsafe = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        var name = title.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = String(localized: "File") }
        guard type != .data, let preferred = type.preferredFilenameExtension else { return name }
        let held = (name as NSString).pathExtension
        if !held.isEmpty, UTType(filenameExtension: held)?.conforms(to: type) == true { return name }
        return name + "." + preferred
    }

    /// A copy of `file` in a folder of its own under `folderName`, or nil where it cannot be made and the file is better shown as it is.
    /// On APFS the copy is a clone, so it costs no space, and an app that changes it cannot change the kept bytes.
    static func copy(of file: URL, titled title: String, as type: UTType, in folderName: String = "Quick Look") -> QuickLookFile? {
        let folder = URL.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: name(for: title, type: type), directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: url)
            return QuickLookFile(folder: folder, url: url)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
