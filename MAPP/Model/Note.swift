import Foundation

nonisolated struct Note: Identifiable, Hashable {
    let id: UUID
    /// Where the note's file is, relative to the notes folder, with `/` between components. A new note has no
    /// file until its first line is written, and a deleted note keeps the path it had.
    var path: String? {
        didSet { refreshText() }
    }
    var file: NoteFile {
        didSet { refreshText() }
    }
    /// Read out of the file whenever it changes, so lists and sorting never parse markdown.
    private(set) var title: String
    private(set) var preview: String
    var created: Date
    var modified: Date
    /// A note with no folder is in the Inbox.
    var folderID: Folder.ID?
    /// When the note went to Recently Deleted, and its place in the bin there.
    var deleted: Date?
    var binID: UUID?
    /// The file's identity when last read, to know it again if another app renames it.
    var fileID: UInt64?
    /// The first line the note's name was taken from, while the note still goes by it; nil for a note named
    /// otherwise, which keeps its name whatever its first line says. A new note follows its first line too.
    var namedLine: String? {
        didSet { refreshText() }
    }

    init(
        id: UUID = UUID(),
        path: String? = nil,
        text: String,
        created: Date,
        modified: Date? = nil,
        folderID: Folder.ID? = nil,
        deleted: Date? = nil,
        binID: UUID? = nil
    ) {
        self.id = id
        self.path = path
        file = NoteFile(text: text)
        (title, preview) = ("", "")
        self.created = created
        self.modified = modified ?? created
        self.folderID = folderID
        self.deleted = deleted
        self.binID = binID
        namedLine = derivedNamedLine
        refreshText()
    }

    /// The line the file's name comes from, when it comes from the first line: the name is that line's and no
    /// other title has been given. A note with no words yet goes by the empty line, and New Note.
    private var derivedNamedLine: String? {
        guard let fileTitle else { return nil }
        let line = NoteText.firstLine(of: file.body) ?? ""
        return NoteText.isName(fileTitle, of: line) && (file.title == nil || file.title == line) ? line : nil
    }

    /// Takes in a change made outside, to the file's name or text. A note still carrying the name of the line
    /// it follows goes on following it, whichever change arrived first; otherwise it follows its first line
    /// only if it is named after it, and a `title` given elsewhere always stops it.
    mutating func reviewNaming() {
        if let named = namedLine, let fileTitle, NoteText.isName(fileTitle, of: named), file.title == nil || file.title == named {
            return
        }
        namedLine = derivedNamedLine
    }

    var body: String { file.body }
    var isFavorite: Bool { file.isFavorite }
    var isDeleted: Bool { deleted != nil }
    /// A note not yet written to a file.
    var isDraft: Bool { path == nil }

    /// The directory the note's file is in, relative to the notes folder; empty at the top.
    var directory: String {
        guard let path, let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// The file's name without its extension.
    var fileTitle: String? {
        path.map { (($0 as NSString).lastPathComponent as NSString).deletingPathExtension }
    }

    /// Whether the note's name comes from its first line, so it changes as the line does.
    var followsFirstLine: Bool { isDraft || namedLine != nil }

    /// As Marfa reads a note: its `title` property, otherwise its file name. A note named after its first line
    /// shows the line as it now reads, which its name takes once the note is left.
    private mutating func refreshText() {
        let line = NoteText.firstLine(of: file.body)
        title = (followsFirstLine ? line : nil) ?? file.title ?? fileTitle ?? String(localized: "New Note")
        preview = NoteText.preview(of: file.body, title: title)
    }
}
