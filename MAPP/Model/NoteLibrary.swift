import Foundation
import Observation

/// Every note and folder, held in memory. Each change a person can make is undoable through the
/// undo manager it is given.
@Observable
final class NoteLibrary {
    private(set) var notes: [Note]
    private(set) var folders: [Folder]
    @ObservationIgnored let now: () -> Date

    init(notes: [Note] = [], folders: [Folder] = [], now: @escaping () -> Date = Date.init) {
        self.notes = notes
        self.folders = folders
        self.now = now
    }

    // MARK: Reading

    func note(_ id: Note.ID) -> Note? {
        notes.first { $0.id == id }
    }

    func folder(_ id: Folder.ID) -> Folder? {
        folders.first { $0.id == id }
    }

    func notes(in item: SidebarItem) -> [Note] {
        switch item {
        case .inbox: notes.filter { !$0.isDeleted && $0.folderID == nil }
        case .allNotes: notes.filter { !$0.isDeleted }
        case .pinned: notes.filter { !$0.isDeleted && $0.isPinned }
        case .folder(let id): notes.filter { !$0.isDeleted && $0.folderID == id }
        case .recentlyDeleted: notes.filter(\.isDeleted)
        }
    }

    /// Search covers every note that has not been deleted, whichever sidebar item is selected.
    func notes(matching query: String) -> [Note] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return notes.filter {
            !$0.isDeleted && $0.body.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    func count(in item: SidebarItem) -> Int {
        notes(in: item).count
    }

    func name(of item: SidebarItem) -> String {
        switch item {
        case .inbox: String(localized: "Inbox")
        case .allNotes: String(localized: "All Notes")
        case .pinned: String(localized: "Pinned")
        case .folder(let id): folder(id)?.name ?? ""
        case .recentlyDeleted: String(localized: "Recently Deleted")
        }
    }

    // MARK: Notes

    /// A new, empty note placed where it will show in `item`: in that folder, pinned when made from Pinned,
    /// and in the Inbox otherwise.
    @discardableResult
    func newNote(in item: SidebarItem, undoManager: UndoManager? = nil) -> Note {
        var note = Note(body: "", created: now())
        switch item {
        case .folder(let id): note.folderID = id
        case .pinned: note.isPinned = true
        case .inbox, .allNotes, .recentlyDeleted: break
        }
        insert([note], undoManager: undoManager, name: String(localized: "New Note"))
        return note
    }

    func updateBody(of id: Note.ID, to body: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].body != body else { return }
        notes[index].body = body
        notes[index].modified = now()
    }

    func delete(_ ids: Set<Note.ID>, undoManager: UndoManager? = nil) {
        let date = now()
        edit(ids, undoManager: undoManager, name: deleteName(ids.count)) { $0.deleted = date }
    }

    func restore(_ ids: Set<Note.ID>, undoManager: UndoManager? = nil) {
        edit(ids, undoManager: undoManager, name: String(localized: "Recover")) { $0.deleted = nil }
    }

    func deletePermanently(_ ids: Set<Note.ID>, undoManager: UndoManager? = nil) {
        remove(ids, undoManager: undoManager, name: deleteName(ids.count))
    }

    /// Moving a note into a folder, or back to the Inbox with `nil`, also recovers it if it was deleted.
    func move(_ ids: Set<Note.ID>, to folderID: Folder.ID?, undoManager: UndoManager? = nil) {
        edit(ids, undoManager: undoManager, name: String(localized: "Move")) {
            $0.folderID = folderID
            $0.deleted = nil
        }
    }

    func setPinned(_ ids: Set<Note.ID>, _ pinned: Bool, undoManager: UndoManager? = nil) {
        let name = pinned ? String(localized: "Pin") : String(localized: "Unpin")
        edit(ids, undoManager: undoManager, name: name) { $0.isPinned = pinned }
    }

    // MARK: Folders

    @discardableResult
    func newFolder(undoManager: UndoManager? = nil) -> Folder {
        let folder = Folder(name: uniqueFolderName(String(localized: "New Folder")))
        var order = folders
        order.append(folder)
        setFolders(order, undoManager: undoManager, name: String(localized: "New Folder"))
        return folder
    }

    func rename(_ id: Folder.ID, to name: String, undoManager: UndoManager? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let index = folders.firstIndex(where: { $0.id == id }),
              !name.isEmpty, folders[index].name != name else { return }
        var order = folders
        order[index].name = name
        setFolders(order, undoManager: undoManager, name: String(localized: "Rename Folder"))
    }

    /// Deleting a folder moves its notes to Recently Deleted, as Notes does.
    func deleteFolder(_ id: Folder.ID, undoManager: UndoManager? = nil) {
        guard folder(id) != nil else { return }
        let name = String(localized: "Delete Folder")
        undoManager?.beginUndoGrouping()
        let date = now()
        edit(Set(notes.filter { $0.folderID == id }.map(\.id)), undoManager: undoManager, name: name) {
            $0.folderID = nil
            $0.deleted = $0.deleted ?? date
        }
        setFolders(folders.filter { $0.id != id }, undoManager: undoManager, name: name)
        undoManager?.endUndoGrouping()
    }

    func moveFolders(from source: IndexSet, to destination: Int, undoManager: UndoManager? = nil) {
        var order = folders
        order.moveSubranges(RangeSet(source.rangeView.map { $0.lowerBound..<$0.upperBound }), to: destination)
        setFolders(order, undoManager: undoManager, name: String(localized: "Move Folder"))
    }

    // MARK: Undoable primitives
    //
    // Each primitive registers its own inverse, so undoing registers the redo without extra bookkeeping.

    private func edit(_ ids: Set<Note.ID>, undoManager: UndoManager?, name: String, _ change: (inout Note) -> Void) {
        let edited = notes.filter { ids.contains($0.id) }.map { note in
            var note = note
            change(&note)
            return note
        }
        replace(with: edited, undoManager: undoManager, name: name)
    }

    private func replace(with replacements: [Note], undoManager: UndoManager?, name: String) {
        guard !replacements.isEmpty else { return }
        var previous: [Note] = []
        for replacement in replacements {
            guard let index = notes.firstIndex(where: { $0.id == replacement.id }) else { continue }
            previous.append(notes[index])
            notes[index] = replacement
        }
        registerUndo(undoManager, name: name) { $0.replace(with: previous, undoManager: undoManager, name: name) }
    }

    private func insert(_ inserted: [Note], undoManager: UndoManager?, name: String) {
        guard !inserted.isEmpty else { return }
        notes.append(contentsOf: inserted)
        let ids = Set(inserted.map(\.id))
        registerUndo(undoManager, name: name) { $0.remove(ids, undoManager: undoManager, name: name) }
    }

    private func remove(_ ids: Set<Note.ID>, undoManager: UndoManager?, name: String) {
        let removed = notes.filter { ids.contains($0.id) }
        guard !removed.isEmpty else { return }
        notes.removeAll { ids.contains($0.id) }
        registerUndo(undoManager, name: name) { $0.insert(removed, undoManager: undoManager, name: name) }
    }

    private func setFolders(_ order: [Folder], undoManager: UndoManager?, name: String) {
        guard order != folders else { return }
        let previous = folders
        folders = order
        registerUndo(undoManager, name: name) { $0.setFolders(previous, undoManager: undoManager, name: name) }
    }

    private func registerUndo(_ undoManager: UndoManager?, name: String, _ handler: @escaping (NoteLibrary) -> Void) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self, handler: handler)
        undoManager.setActionName(name)
    }

    private func uniqueFolderName(_ base: String) -> String {
        let names = Set(folders.map(\.name))
        guard names.contains(base) else { return base }
        var number = 2
        while names.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    private func deleteName(_ count: Int) -> String {
        count == 1 ? String(localized: "Delete Note") : String(localized: "Delete Notes")
    }
}
