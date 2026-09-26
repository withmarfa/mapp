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
        refreshText()
    }

    var body: String { file.body }
    var isPinned: Bool { file.isPinned }
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

    /// As Marfa reads a note: its `title` property, otherwise its file name. A note with no file yet takes its
    /// first line, which its file will be named after.
    private mutating func refreshText() {
        let firstLine = NoteText.titleAndPreview(of: file.body)
        title = file.title ?? fileTitle ?? firstLine.title
        preview = NoteText.preview(of: file.body, title: title)
    }
}
