import Foundation

nonisolated struct Note: Identifiable, Hashable {
    let id: UUID
    var body: String {
        didSet { (title, preview) = NoteText.titleAndPreview(of: body) }
    }
    /// Read out of the body whenever it changes, so lists and sorting never parse markdown.
    private(set) var title: String
    private(set) var preview: String
    var created: Date
    var modified: Date
    var placement: Placement

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
        (title, preview) = NoteText.titleAndPreview(of: body)
        self.created = created
        self.modified = modified ?? created
        placement = Placement(folderID: folderID, isPinned: isPinned, deleted: deleted)
    }

    /// A note with no folder is in the Inbox.
    var folderID: Folder.ID? { placement.folderID }
    var isPinned: Bool { placement.isPinned }
    var deleted: Date? { placement.deleted }
    var isDeleted: Bool { deleted != nil }
}

/// Where a note sits, apart from its text. Moving, pinning and deleting change only this, so undoing them
/// never touches what was typed since.
nonisolated struct Placement: Hashable {
    var folderID: Folder.ID?
    var isPinned: Bool
    var deleted: Date?
}
