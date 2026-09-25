import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected notes and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var sidebarItem: SidebarItem? = .allNotes
    var selection: Set<Note.ID> = []
    var searchText = ""
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

    /// Notes in the list go to Recently Deleted; notes already there are deleted for good. Both undo.
    static func delete(_ ids: Set<Note.ID>, in library: NoteLibrary, undoManager: UndoManager?) {
        let alreadyDeleted = Set(ids.compactMap { library.note($0) }.filter(\.isDeleted).map(\.id))
        library.deletePermanently(alreadyDeleted, undoManager: undoManager)
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

    /// What a window brings back when the app opens again.
    struct Snapshot: Codable, Equatable {
        var sidebarItem: SidebarItem?
        var selection: Set<Note.ID>
    }

    var snapshot: Snapshot { Snapshot(sidebarItem: sidebarItem, selection: selection) }

    /// Restores what still exists: a folder deleted since gives way to All Notes, and notes no longer in the
    /// list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: NoteLibrary, order: NoteOrder) {
        if case .folder(let id) = snapshot.sidebarItem, library.folder(id) == nil {
            sidebarItem = .allNotes
        } else {
            sidebarItem = snapshot.sidebarItem ?? .allNotes
        }
        selection = snapshot.selection.intersection(notes(in: library).map(\.id))
        if selection.isEmpty { selectFirstNote(in: library, order: order) }
    }
}
