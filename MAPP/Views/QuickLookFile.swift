import Foundation
import UniformTypeIdentifiers

/// A file as an app that chooses by name can be given it (Quick Look, a browser). Quick Look picks a previewer from the file's name, and a Marfa copy keeps
/// a file's bytes under their hash with no extension, so it is shown a copy of them named after the item.
nonisolated struct QuickLookFile {
    let folder: URL
    let url: URL

    /// The longest a file name can be, in UTF-8 bytes.
    static let longestName = 255

    /// The item's title, made safe as a file name, ending in an extension that fits `type`, and cut to fit the
    /// longest name a file can have without splitting a character.
    static func name(for title: String, type: UTType) -> String {
        let unsafe = CharacterSet(charactersIn: "/:").union(.controlCharacters)
        var name = title.components(separatedBy: unsafe).joined(separator: "-").trimmingCharacters(in: .whitespaces)
        while name.hasPrefix(".") { name.removeFirst() }
        if name.isEmpty { name = String(localized: "File") }
        var ending = ""
        if type != .data, let preferred = type.preferredFilenameExtension {
            let held = (name as NSString).pathExtension
            if !held.isEmpty, UTType(filenameExtension: held)?.conforms(to: type) == true {
                ending = "." + held
                name = String(name.dropLast(ending.count))
            } else {
                ending = "." + preferred
            }
        }
        var size = ending.utf8.count
        var kept = name.prefix { character in
            size += String(character).utf8.count
            return size <= longestName
        }
        while kept.last?.isWhitespace == true { kept.removeLast() }
        return String(kept) + ending
    }

    /// A copy of `file` in a folder of its own under `folderName`, or nil where it cannot be made and the file is better shown as it is.
    /// On APFS the copy is a clone, so it costs no space, and an app that changes it cannot change the kept bytes.
    /// With `key`, the copy's folder is named by it and an earlier copy under that key is replaced, so repeating the
    /// request for the same thing leaves one copy; without it each copy has a folder of its own.
    static func copy(of file: URL, titled title: String, as type: UTType, in folderName: String = "Quick Look", key: String? = nil) -> QuickLookFile? {
        let folder = URL.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: key.map { name(for: $0, type: .data) } ?? UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: name(for: title, type: type), directoryHint: .notDirectory)
        do {
            if key != nil { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: file, to: url)
            return QuickLookFile(folder: folder, url: url)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    /// A file holding `text`, named after the item as `copy` names its own, or nil where it cannot be made.
    static func write(_ text: String, titled title: String, as type: UTType, in folderName: String = "Quick Look", key: String? = nil) -> QuickLookFile? {
        let folder = URL.temporaryDirectory.appending(path: folderName, directoryHint: .isDirectory)
            .appending(path: key.map { name(for: $0, type: .data) } ?? UUID().uuidString, directoryHint: .isDirectory)
        let url = folder.appending(path: name(for: title, type: type), directoryHint: .notDirectory)
        do {
            if key != nil { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
            return QuickLookFile(folder: folder, url: url)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
    }

    /// Removes the folders earlier runs left in the temporary folder: copies shown, dragged out or opened elsewhere,
    /// which the receiving app may read for as long as it likes, so nothing else can say when they are done with.
    static func removeLeftovers() {
        for folder in ["Quick Look", ItemReference.folder, "Web Pages", "Device Import"] {
            try? FileManager.default.removeItem(at: URL.temporaryDirectory.appending(path: folder, directoryHint: .isDirectory))
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }
}
