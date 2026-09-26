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

    /// Waits until every queued change is made, as the app quits.
    func drain()

    /// Told when a change could not use the path it was given, because a file the library does not know of is
    /// there, and used this one instead. Changes queued meanwhile for the first path go to the second. Called on
    /// the main actor.
    var relocated: @MainActor @Sendable (_ from: String, _ to: String) -> Void { get set }

    /// Told when a change could not be made, with what went wrong, so the person hears of it. Called on the
    /// main actor.
    var failed: @MainActor @Sendable (_ path: String, _ message: String) -> Void { get set }
}

nonisolated struct StoredNote: Sendable {
    var path: String
    var text: String
    var created: Date
    var modified: Date
    /// The file's own identity, which a rename keeps, so a note moved by another app is still the same note.
    var fileID: UInt64? = nil
}

nonisolated struct TrashedNote: Sendable {
    var id: UUID
    var note: StoredNote
    var trashed: Date
}

nonisolated struct StoredLibrary: Sendable {
    var folders: [String] = []
    var notes: [StoredNote] = []
    var trash: [TrashedNote] = []
}

nonisolated enum StoreChange: Sendable, Equatable {
    /// A new note's file, written only if nothing is at the path yet.
    case create(path: String, text: String)
    /// A note's new text, written only if the bytes differ.
    case write(path: String, text: String)
    case move(from: String, to: String)
    /// Takes the note out of the folder and into the trash, under an identifier the library keeps.
    case trash(path: String, id: UUID, date: Date)
    /// Puts a trashed note back at the path.
    case restore(id: UUID, path: String)
    /// Erases a trashed note for good.
    case purge(id: UUID)
    /// Erases whatever has been in the trash since before the date.
    case purgeTrash(before: Date)
    case createFolder(path: String)
    case moveFolder(from: String, to: String)
    /// Removes a folder left with nothing in it but hidden files.
    case removeFolder(path: String)
}

extension StoreChange {
    /// The note or folder the change is about, to name it when the change fails.
    nonisolated var path: String? {
        switch self {
        case .create(let path, _), .write(let path, _), .trash(let path, _, _), .restore(_, let path),
             .createFolder(let path), .removeFolder(let path):
            path
        case .move(_, let to), .moveFolder(_, let to):
            to
        case .purge, .purgeTrash:
            nil
        }
    }
}
