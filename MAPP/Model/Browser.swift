import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected notes and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var sidebarItem: SidebarItem? = .allNotes
    var selection: Set<ItemID> = []
    var searchText = ""
    /// The note whose file name is being asked for.
    var renamingNote: ItemID?
    /// The folder whose name is being edited in the sidebar.
    var renamingFolder: ItemID?
    /// The folder whose deletion awaits confirmation.
    var folderToDelete: ItemID?
    /// Where the keyboard should go next, asked for by an action such as New Note or Search Notes. Whatever
    /// can take it grants it once, when it is able to, and clears it.
    var focusRequest: Pane?
    /// The palette that is out, if any: ⌘K's commands, or ⌘P's search of every note.
    var palette: Palette?
    /// Whether the list's search is out as a field, rather than a button beside Sort.
    var isSearchExpanded = false
    /// What Marfa Types' page is searched for.
    var typesQuery = ""
    /// Counts each request for the list's search, so a field already out takes the keyboard again.
    var searchFocusRequests = 0
    var isCreatingItem = false
    var itemDraft: NewItemDraft?
    var isImportingFiles = false

    nonisolated enum Palette: Hashable {
        case commands, search
    }

    nonisolated enum Pane: Hashable {
        case sidebar, list, page, search
        /// The search of Marfa Types, which searches its page rather than the notes.
        case typesSearch
    }

    var item: SidebarItem { sidebarItem ?? .allNotes }

    /// The folder the sidebar has selected, which the folder commands act on.
    var selectedFolder: ItemID? {
        if case .folder(let id) = item { id } else { nil }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the window shows Marfa's types in place of the list and the note.
    var showsTypes: Bool { item == .marfaTypes }

    /// The notes the list shows: the search results while searching, the sidebar item's notes otherwise.
    func notes(in library: NoteLibrary) -> [Note] {
        isSearching ? library.notes(matching: searchText) : library.notes(in: item)
    }

    /// The selected notes that still exist.
    func files(in library: NoteLibrary) -> [AppFile] {
        let files: [AppFile]
        switch item {
        case .allNotes, .files: files = library.files
        case .inbox: files = library.files.filter { $0.folderID == nil }
        case .folder(let id): files = library.files.filter { $0.folderID == id }
        default: files = []
        }
        guard isSearching else { return files }
        return library.files.filter { $0.title.localizedStandardContains(searchText) }
    }

    func selectedNotes(in library: NoteLibrary) -> [Note] {
        isCreatingItem ? [] : selection.compactMap { library.note($0) }
    }

    /// The list's sections. Favorites lead wherever they mean something: not in Favorites itself, where every
    /// note is one, nor in Recently Deleted or search results.
    func sections(in library: NoteLibrary, order: NoteOrder, now: Date) -> [NoteSection] {
        NoteGroup.sections(
            of: notes(in: library),
            sort: order.sort,
            favoritesFirst: !isSearching && !showsOnlyFavorites && item != .recentlyDeleted,
            groupsByDate: order.groupsByDate,
            now: now
        )
    }

    /// Whether the list mixes notes from several places, so each row says where its note lives.
    var showsFolders: Bool {
        isSearching || item == .allNotes || showsOnlyFavorites || item == .recentlyDeleted
    }

    private var showsOnlyFavorites: Bool {
        if case .favoriteItem = item { return true }
        return item == .favorites
    }

    /// Shows a sidebar item as a person picks it: any search is cleared and the list's first note is selected.
    func show(_ item: SidebarItem, in library: NoteLibrary, order: NoteOrder) {
        isCreatingItem = false
        searchText = ""
        typesQuery = ""
        isSearchExpanded = false
        sidebarItem = item
        selectFirstNote(in: library, order: order)
    }

    func selectFirstNote(in library: NoteLibrary, order: NoteOrder) {
        let first = sections(in: library, order: order, now: library.now()).first?.notes.first
        selection = (first?.id ?? files(in: library).first?.id).map { [$0] } ?? []
    }

    /// A draft belongs to the window, so leaving its page never discards what was typed.
    func startItemDraft() {
        if itemDraft == nil { itemDraft = NewItemDraft(place: item) }
        isCreatingItem = true
        focusRequest = .page
    }

    /// Blank titles receive a unique name without requiring a naming dialog before typing.
    func createDraft(in library: NoteLibrary, undoManager: UndoManager?) -> Note? {
        guard let draft = itemDraft else { return nil }
        var title = NoteName.trimmed(draft.title)
        if title.isEmpty {
            let untitled = String(localized: "Untitled")
            title = untitled
            var suffix = 2
            while library.notes.contains(where: { !$0.isDeleted && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
                title = "\(untitled) \(suffix)"
                suffix += 1
            }
        }
        guard let note = library.createItem(typeID: draft.typeID, title: title, body: draft.body, parentID: draft.parentID, in: draft.place, undoManager: undoManager) else { return nil }
        isCreatingItem = false
        itemDraft = nil
        searchText = ""
        isSearchExpanded = false
        if !library.notes(in: item).contains(where: { $0.id == note.id }) {
            sidebarItem = .itemType(draft.typeID)
        }
        selection = [note.id]
        focusRequest = .page
        return note
    }

    func newFolder(in library: NoteLibrary, order: NoteOrder, undoManager: UndoManager?) {
        let folder = library.newFolder(undoManager: undoManager)
        show(.folder(folder.id), in: library, order: order)
        renamingFolder = folder.id
    }

    /// Notes in the list go to Recently Deleted, which undoes. Notes already there are erased for good once the
    /// person confirms, since that cannot be undone.
    static func delete(_ ids: Set<ItemID>, in library: NoteLibrary, undoManager: UndoManager?) {
        let alreadyDeleted = Set(ids.compactMap { library.note($0) }.filter(\.isDeleted).map(\.id))
        if !alreadyDeleted.isEmpty { library.notesToPurge = alreadyDeleted }
        library.delete(ids.subtracting(alreadyDeleted), undoManager: undoManager)
    }

    /// A folder that is gone, by deletion or by undoing its creation, can no longer be shown; All Notes is.
    func folderRemoved(in library: NoteLibrary, order: NoteOrder) {
        if case .folder(let id) = sidebarItem, library.folder(id) == nil {
            show(.allNotes, in: library, order: order)
        }
        if case .project(let id) = sidebarItem, library.note(id)?.isDeleted != false {
            show(.allNotes, in: library, order: order)
        }
        if case .favoriteItem(let id) = sidebarItem,
           library.note(id).map({ !$0.isDeleted && $0.isFavorite }) != true {
            show(.favorites, in: library, order: order)
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
    static func selection(_ selection: Set<ItemID>, keptFrom old: [ItemID], in new: [ItemID]) -> Set<ItemID> {
        let visible = Set(new)
        let kept = selection.intersection(visible)
        guard kept.isEmpty, let first = old.firstIndex(where: selection.contains) else { return kept }
        let candidates = old[first...].dropFirst() + old[..<first].reversed()
        return candidates.first { visible.contains($0) && !selection.contains($0) }.map { [$0] } ?? []
    }

    // MARK: Restoring a window

    /// What a window brings back when the app opens again, by the identifiers of what it showed, which last from
    /// one launch to the next. A snapshot in any other form reads as none.
    struct Snapshot: Codable, Equatable {
        var place: SidebarItem
        var selection: [ItemID]
    }

    func snapshot() -> Snapshot {
        Snapshot(place: item, selection: selection.sorted { $0.rawValue < $1.rawValue })
    }

    /// Restores a window from what it kept. A snapshot that does not read, one kept in an earlier form say,
    /// leaves the window at its default.
    func restore(from data: Data?, in library: NoteLibrary, order: NoteOrder) {
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            restore(snapshot, in: library, order: order)
        } else {
            selectFirstNote(in: library, order: order)
        }
    }

    /// Restores what still exists: a place gone since gives way to All Notes, or Favorites for a favorite, and
    /// items no longer in the list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: NoteLibrary, order: NoteOrder) {
        sidebarItem = switch snapshot.place {
        case .favoriteItem(let id):
            library.note(id).flatMap { $0.isFavorite && !$0.isDeleted ? snapshot.place : nil } ?? .favorites
        case .project(let id): library.note(id).map { _ in snapshot.place } ?? .allNotes
        case .folder(let id): library.folder(id).map { _ in snapshot.place } ?? .allNotes
        case .itemType(let type): WorkbenchSchema.definition(type).map { _ in snapshot.place } ?? .allNotes
        case .inbox, .allNotes, .favorites, .recentlyDeleted, .marfaTypes, .files: snapshot.place
        }
        let ids = Set(snapshot.selection)
        selection = Set(notes(in: library).map(\.id).filter(ids.contains))
        selection.formUnion(files(in: library).map(\.id).filter(ids.contains))
        if selection.isEmpty { selectFirstNote(in: library, order: order) }
    }
}

@Observable
final class NewItemDraft {
    var typeID: String
    var title = ""
    var body = ""
    var parentID: ItemID?
    let place: SidebarItem

    init(place: SidebarItem) {
        self.place = place
        if case .itemType(let id) = place { typeID = id } else { typeID = "core.note" }
        if case .project(let id) = place { parentID = id }
    }
}
