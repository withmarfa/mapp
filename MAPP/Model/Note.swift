import Foundation

struct Note: Identifiable, Hashable {
    let id: UUID
    var body: String
    var created: Date
    var modified: Date
    /// A note with no folder is in the Inbox.
    var folderID: Folder.ID?
    var isPinned: Bool
    var deleted: Date?

    init(
        id: UUID = UUID(),
        body: String,
        created: Date,
        modified: Date? = nil,
        folderID: Folder.ID? = nil,
        isPinned: Bool = false,
        deleted: Date? = nil
    ) {
        self.id = id
        self.body = body
        self.created = created
        self.modified = modified ?? created
        self.folderID = folderID
        self.isPinned = isPinned
        self.deleted = deleted
    }

    var isDeleted: Bool { deleted != nil }
    var title: String { NoteText.title(of: body) }
    var preview: String { NoteText.preview(of: body) }
}
