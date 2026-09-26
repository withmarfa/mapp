import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected notes and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var sidebarItem: SidebarItem? = .allNotes
    var selection: Set<Note.ID> = []
    var searchText = ""
    /// The note whose file name is being asked for.
    var renamingNote: Note.ID?
    /// The folder whose name is being edited in the sidebar.
    var renamingFolder: Folder.ID?
    /// The folder whose deletion awaits confirmation.
    var folderToDelete: Folder.ID?
    /// Where the keyboard should go next, asked for by an action such as New Note or Search Notes. Whatever
    /// can take it grants it once, when it is able to, and clears it.
    var focusRequest: Pane?

    nonisolated enum Pane: Hashable {
        case sidebar, list, page, search
    }

    var item: SidebarItem { sidebarItem ?? .allNotes }

    /// The folder the sidebar has selected, which the folder commands act on.
    var selectedFolder: Folder.ID? {
        if case .folder(let id) = item { id } else { nil }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The notes the list shows: the search results while searching, the sidebar item's notes otherwise.
    func notes(in library: NoteLibrary) -> [Note] {
        isSearching ? library.notes(matching: searchText) : library.notes(in: item)
    }

    /// The selected notes that still exist.
    func selectedNotes(in library: NoteLibrary) -> [Note] {
        selection.compactMap { library.note($0) }
    }

    /// The list's sections. Pinned notes lead wherever pins mean something: not in Pinned itself, where every
    /// note is pinned, nor in Recently Deleted or search results.
    func sections(in library: NoteLibrary, order: NoteOrder, now: Date) -> [NoteSection] {
        NoteGroup.sections(
            of: notes(in: library),
            sort: order.sort,
            pinnedFirst: !isSearching && item != .pinned && item != .recentlyDeleted,
            groupsByDate: order.groupsByDate,
            now: now
        )
    }

    /// Whether the list mixes notes from several places, so each row says where its note lives.
    var showsFolders: Bool {
        isSearching || item == .allNotes || item == .pinned || item == .recentlyDeleted
    }

    /// Shows a sidebar item as a person picks it: any search is cleared and the list's first note is selected.
    func show(_ item: SidebarItem, in library: NoteLibrary, order: NoteOrder) {
        searchText = ""
        sidebarItem = item
        selectFirstNote(in: library, order: order)
    }

    func selectFirstNote(in library: NoteLibrary, order: NoteOrder) {
        let first = sections(in: library, order: order, now: library.now()).first?.notes.first
        selection = first.map { [$0.id] } ?? []
    }

    /// A new note where the list can show it. Recently Deleted cannot hold one, so it goes to the Inbox, and a
    /// search is cleared so the note is not hidden by it.
    func newNote(in library: NoteLibrary, undoManager: UndoManager?) {
        if item == .recentlyDeleted { sidebarItem = .inbox }
        searchText = ""
        let note = library.newNote(in: item, undoManager: undoManager)
        selection = [note.id]
        focusRequest = .page
    }

    func newFolder(in library: NoteLibrary, order: NoteOrder, undoManager: UndoManager?) {
        let folder = library.newFolder(undoManager: undoManager)
        show(.folder(folder.id), in: library, order: order)
        renamingFolder = folder.id
    }

    /// Notes in the list go to Recently Deleted, which undoes. Notes already there are erased for good once the
    /// person confirms, since that cannot be undone.
    static func delete(_ ids: Set<Note.ID>, in library: NoteLibrary, undoManager: UndoManager?) {
        let alreadyDeleted = Set(ids.compactMap { library.note($0) }.filter(\.isDeleted).map(\.id))
        if !alreadyDeleted.isEmpty { library.notesToPurge = alreadyDeleted }
        library.delete(ids.subtracting(alreadyDeleted), undoManager: undoManager)
    }

    /// A folder that is gone, by deletion or by undoing its creation, can no longer be shown; All Notes is.
    func folderRemoved(in library: NoteLibrary, order: NoteOrder) {
        if case .folder(let id) = sidebarItem, library.folder(id) == nil {
            show(.allNotes, in: library, order: order)
        }
        if let renamingFolder, library.folder(renamingFolder) == nil {
            self.renamingFolder = nil
        }
        if let folderToDelete, library.folder(folderToDelete) == nil {
            self.folderToDelete = nil
        }
    }

    // MARK: Keeping the selection in the list

    /// When selected notes leave the list (deleted, moved elsewhere, filtered out by a search), the selection
    /// keeps whichever are still there. If none are, it moves to the note that followed them, or failing that
    /// the one before, as Notes and Mail do.
    static func selection(_ selection: Set<Note.ID>, keptFrom old: [Note.ID], in new: [Note.ID]) -> Set<Note.ID> {
        let visible = Set(new)
        let kept = selection.intersection(visible)
        guard kept.isEmpty, let first = old.firstIndex(where: selection.contains) else { return kept }
        let candidates = old[first...].dropFirst() + old[..<first].reversed()
        return candidates.first { visible.contains($0) && !selection.contains($0) }.map { [$0] } ?? []
    }

    // MARK: Restoring a window

    /// What a window brings back when the app opens again, by where things are in the notes folder, since that
    /// is what lasts from one launch to the next.
    struct Snapshot: Codable, Equatable {
        var sidebarItem: Item?
        var selection: [String]

        enum Item: Codable, Equatable {
            case inbox, allNotes, pinned, recentlyDeleted
            case folder(String)
        }
    }

    func snapshot(in library: NoteLibrary) -> Snapshot {
        let item: Snapshot.Item? = sidebarItem.map { item in
            switch item {
            case .inbox: .inbox
            case .allNotes: .allNotes
            case .pinned: .pinned
            case .recentlyDeleted: .recentlyDeleted
            case .folder(let id): .folder(library.folder(id)?.name ?? "")
            }
        }
        let paths = selection.compactMap { library.note($0)?.path }.sorted()
        return Snapshot(sidebarItem: item, selection: paths)
    }

    /// Restores what still exists: a folder deleted since gives way to All Notes, and notes no longer in the
    /// list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: NoteLibrary, order: NoteOrder) {
        switch snapshot.sidebarItem {
        case .inbox: sidebarItem = .inbox
        case .pinned: sidebarItem = .pinned
        case .recentlyDeleted: sidebarItem = .recentlyDeleted
        case .folder(let name):
            sidebarItem = library.folders.first { $0.name == name }.map { .folder($0.id) } ?? .allNotes
        case .allNotes, nil: sidebarItem = .allNotes
        }
        let paths = Set(snapshot.selection)
        selection = Set(notes(in: library).filter { $0.path.map(paths.contains) == true }.map(\.id))
        if selection.isEmpty { selectFirstNote(in: library, order: order) }
    }
}
