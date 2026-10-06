import Foundation
import Synchronization

/// Two notes are equal when one is an unchanged copy of the other: every change takes a revision no other note
/// has had, so comparing notes never compares their text.
nonisolated struct Note: Identifiable, Hashable {
    let id: ItemID
    /// Also the item's version.
    private(set) var revision = SessionRevision.next()
    /// Where the note's file is, relative to the notes folder, with `/` between components. A deleted note keeps
    /// the path it had.
    var path: String {
        didSet { refreshText() }
    }
    var file: NoteFile {
        didSet {
            refreshText()
            if file.body != oldValue.body { bodyRevision = revision }
        }
    }
    /// The revision at which the body last changed, so an edit typed on older text can be told apart.
    private(set) var bodyRevision: Int64 = 0
    /// Read out of the file whenever it changes, so lists and sorting never parse markdown.
    private(set) var title: String
    private(set) var preview: String
    var created: Date { didSet { revise() } }
    var modified: Date { didSet { revise() } }
    /// A note with no folder is in the Inbox.
    var folderID: ItemID? { didSet { revise() } }
    /// When the note went to Recently Deleted, and its place in the bin there.
    var deleted: Date? { didSet { revise() } }
    var binID: UUID?
    /// The first line the note's name was taken from, while the note still goes by it; nil for a note named
    /// otherwise, which keeps its name whatever its first line says.
    var namedLine: String? {
        didSet { refreshText() }
    }

    init(
        id: ItemID = .mint(),
        path: String,
        text: String,
        created: Date,
        modified: Date? = nil,
        folderID: ItemID? = nil,
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
        bodyRevision = revision
    }

    /// The line the file's name comes from, when it comes from the first line: the name is that line's and no
    /// other title has been given. A note with no words yet goes by the empty line, and New Note.
    private var derivedNamedLine: String? {
        let line = NoteText.firstLine(of: file.body) ?? ""
        return NoteText.isName(fileTitle, of: line) && (file.title == nil || file.title == line) ? line : nil
    }

    /// Takes in a change made outside, to the file's name or text. A note still carrying the name of the line
    /// it follows goes on following it, whichever change arrived first; otherwise it follows its first line
    /// only if it is named after it, and a `title` given elsewhere always stops it.
    mutating func reviewNaming() {
        if let named = namedLine, NoteText.isName(fileTitle, of: named), file.title == nil || file.title == named {
            return
        }
        namedLine = derivedNamedLine
    }

    var body: String { file.body }
    var isFavorite: Bool { file.isFavorite }
    var isDeleted: Bool { deleted != nil }

    /// The directory the note's file is in, relative to the notes folder; empty at the top.
    var directory: String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }

    /// The file's name without its extension.
    var fileTitle: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// Whether the note's name comes from its first line, so it changes as the line does.
    var followsFirstLine: Bool { namedLine != nil }

    /// As Marfa reads a note: its `title` property, otherwise its file name. A note named after its first line
    /// shows the line as it now reads, which its name takes once the note is left.
    private mutating func refreshText() {
        let line = NoteText.firstLine(of: file.body)
        title = (followsFirstLine ? line : nil) ?? file.title ?? fileTitle
        preview = NoteText.preview(of: file.body, title: title)
        revise()
    }

    private mutating func revise() {
        revision = SessionRevision.next()
    }

    static func == (lhs: Note, rhs: Note) -> Bool {
        lhs.id == rhs.id && lhs.revision == rhs.revision
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(revision)
    }
}

/// One counter for the session, so a revision taken from it is never another value's, whichever note or file it
/// was taken for.
nonisolated enum SessionRevision {
    private static let counter = Atomic<Int64>(0)

    static func next() -> Int64 {
        counter.add(1, ordering: .relaxed).newValue
    }
}
