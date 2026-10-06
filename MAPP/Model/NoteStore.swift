import Foundation

/// Where notes are kept, in Marfa's words: active notes are listed, trashed, restored and purged. The library
/// decides every path and hands the store one change at a time, which the store makes in order, away from the
/// main thread. Files in a folder are one store; Marfa, keeping the trash, restore and purge, is meant to be
/// another.
nonisolated protocol NoteStore: AnyObject, Sendable {
    /// Every active note and folder, and the trash.
    func load() throws -> StoredLibrary

    /// Queues a change; changes are made in the order they are queued.
    func perform(_ change: StoreChange)

    /// A readable file within the selected library, never a path outside it.
    func fileURL(for path: String) -> URL?

    /// Called after an imported file is available on disk, with the request and the new item's identifier.
    var imported: @MainActor @Sendable (_ request: UUID, _ id: UUID) -> Void { get set }

    /// Waits until every queued change is made, as the app quits.
    func drain()

    /// A path in the attachments folder for a file of this name that nothing has, or will have once the changes
    /// queued are made, numbered as the Finder numbers a copy.
    func freeAttachmentPath(named name: String) -> String

    /// Told when a change could not use the path it was given, because a file the library does not know of is
    /// there, and used this one instead, or because a move failed and the file is still where it was. Changes
    /// queued meanwhile for the first path go to the second. Called on the main actor.
    var relocated: @MainActor @Sendable (_ from: String, _ to: String) -> Void { get set }

    /// The library has taken in a relocation, so changes it queues from now on for the old path mean that path.
    func acknowledgeRelocation(of path: String)

    /// Told when a change could not be made, with what went wrong, so the person hears of it. Called on the
    /// main actor.
    var failed: @MainActor @Sendable (_ path: String, _ message: String) -> Void { get set }
}

/// The store keeps each item's identifier across renames and launches, so a note moved by another app, even
/// while MAPP was closed, is still the same note.
nonisolated struct StoredNote: Sendable {
    var id: UUID
    var path: String
    var text: String
    var created: Date
    var modified: Date
}

nonisolated struct TrashedNote: Sendable {
    var id: UUID
    var note: StoredNote
    var trashed: Date
}

nonisolated struct StoredFile: Sendable {
    var id: UUID
    var path: String
    var created: Date
    var modified: Date
    var byteCount: Int64
}

nonisolated struct StoredFolder: Sendable {
    var id: UUID
    var name: String
}

nonisolated struct StoredLibrary: Sendable {
    var folders: [StoredFolder] = []
    var notes: [StoredNote] = []
    var trash: [TrashedNote] = []
    var files: [StoredFile] = []
}

nonisolated enum StoreChange: Sendable, Equatable {
    /// A new note's file, written only if nothing is at the path yet, under the identifier the library gave it.
    case create(path: String, text: String, id: UUID)
    /// A note's new text, written only if the bytes differ.
    case write(path: String, text: String)
    case move(from: String, to: String)
    /// Takes the note out of the folder and into the trash, under an identifier the library keeps.
    case trash(path: String, id: UUID, date: Date)
    /// Puts a trashed note back at the path.
    case restore(id: UUID, path: String)
    /// Erases a trashed note for good.
    case purge(id: UUID)
    /// A file a note points at, such as a pasted image, written into the attachments folder.
    case attach(path: String, data: Data)
    /// Copies a user-selected regular file without changing its bytes.
    case importFile(path: String, source: URL, requestID: UUID = UUID())
    /// Erases whatever has been in the trash since before the date.
    case purgeTrash(before: Date)
    case createFolder(path: String, id: UUID)
    case moveFolder(from: String, to: String)
    /// Removes a folder left with nothing in it but hidden files.
    case removeFolder(path: String)
}

extension StoreChange {
    /// The note or folder the change is about, to name it when the change fails.
    nonisolated var path: String? {
        switch self {
        case .create(let path, _, _), .write(let path, _), .trash(let path, _, _), .restore(_, let path), .attach(let path, _),
             .createFolder(let path, _), .removeFolder(let path), .importFile(let path, _, _):
            path
        case .move(_, let to), .moveFolder(_, let to):
            to
        case .purge, .purgeTrash:
            nil
        }
    }
}

nonisolated extension NoteStore {
    func fileURL(for path: String) -> URL? { nil }
    var imported: @MainActor @Sendable (UUID, UUID) -> Void {
        get { { _, _ in } }
        set {}
    }
}
