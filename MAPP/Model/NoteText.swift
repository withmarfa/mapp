import Foundation

/// Names for the files MAPP saves or attaches.
nonisolated enum NoteText {
    /// A name as a file can take it: characters no file name can hold replaced, leading dots dropped, which
    /// would hide the file, and short enough for any file system. The one place a name is made safe, for a file
    /// the person saves or attaches.
    static func fileSafe(_ name: String) -> String {
        fitted(
            name.replacing(unsafeInName, with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingPrefix { $0 == "." }
                .trimmingCharacters(in: .whitespaces)
        ).trimmingCharacters(in: .whitespaces)
    }

    private nonisolated(unsafe) static let unsafeInName = /[\/\\:\x00-\x1F\x7F]/

    /// A name short enough for any file system, which counts bytes, with `room` left for an extension.
    private static func fitted(_ name: String, room: Int = 0) -> String {
        var name = name
        while name.utf8.count > 200 - room { name.removeLast() }
        return name
    }

    /// A file's name as an attachment can take it, keeping its extension, which says what it is.
    static func attachmentName(_ name: String) -> String {
        // A name such as `.png` is all extension.
        let bare = name.hasPrefix(".") && !name.dropFirst().contains(".")
        let ext = bare ? String(name.dropFirst()) : (name as NSString).pathExtension
        let stem = bare ? "" : fileSafe((name as NSString).deletingPathExtension)
        let short = fitted(stem, room: ext.utf8.count + 1)
        let base = short.isEmpty ? String(localized: "Image") : short
        return ext.isEmpty ? base : "\(base).\(fileSafe(ext))"
    }
}
