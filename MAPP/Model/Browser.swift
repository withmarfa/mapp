import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected notes and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var sidebarItem: SidebarItem? = .allNotes
    var selection: Set<ItemID> = [] {
        didSet {
            guard !isMovingThroughHistory, !isSelectingAutomatically || history.entries.isEmpty else { return }
            history.record(selection, in: item)
        }
    }
    /// The items the person chose in this window, for Back and Forward: a click, a key in the list, a link or a
    /// palette jump's destination. The app's own moves (the first note of a place, the next note after a delete
    /// or a search) are left out, except the note the window opens on, so Back can return to it. Kept for the
    /// life of the window, not across launches.
    private(set) var history = SelectionHistory()
    @ObservationIgnored private var isMovingThroughHistory = false
    @ObservationIgnored private var isSelectingAutomatically = false
    var viewMode: ItemViewMode = .list {
        didSet {
            isCollectionItemPresented = false
            if viewMode.spansWindow {
                isCreatingItem = false
                focusRequest = .list
            }
        }
    }
    var isCollectionItemPresented = false
    /// How each place's table is grouped, sorted and filtered, as the person left it, for the life of the window.
    var tableOptions: [SidebarItem: ItemTableOptions] = [:]
    var boardFields: [SidebarItem: String] = [:]
    var compactBoards: [SidebarItem: Bool] = [:]
    var agendaFields: [SidebarItem: String] = [:]
    /// Whether the window shows Settings in place of the list and the item page. The place the window was
    /// showing, its selection and its draft are kept, so choosing that place again returns to them.
    private(set) var showsSettings = false
    /// The page of Settings shown, and the one shown next time Settings is.
    var settingsPage = SettingsPage.appearance
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
    /// The palette that is out, if any: ⌘K's commands, or ⇧⌘P's search of every note.
    var palette: Palette?
    /// Whether the list's search is out as a field, rather than a button beside View Options.
    var isSearchExpanded = false
    /// Counts each request for the list's search, so a field already out takes the keyboard again.
    var searchFocusRequests = 0
    var isCreatingItem = false
    var itemDraft: NewItemDraft?
    /// The item made from the draft, until the library shows it: a Marfa library answers a create only when its
    /// source says so, so the draft stays on the page, as typed, until then.
    private(set) var creation: Creation?
    var isImportingFiles = false
    /// A file the library had to fetch to show, so the commands that share it have its location too.
    private(set) var fetchedFile: (id: ItemID, url: URL)?
    /// The library this window was last shown, so a different one starts the window afresh.
    @ObservationIgnored private var libraryID: ObjectIdentifier?
    /// That library, held until the window shows another, so a create still awaited can be asked about as the
    /// window leaves it: by then the app has let it go.
    @ObservationIgnored private var shownLibrary: (any ItemLibrary)?

    struct Creation {
        let id: ItemID
        let typeID: String
        /// The library the create was sent to; another one that has loaded without the item never will hold it.
        let library: any ItemLibrary
    }

    nonisolated enum Palette: Hashable {
        case commands, search
    }

    nonisolated enum Pane: Hashable {
        case sidebar, list, page, search
    }

    var item: SidebarItem { sidebarItem ?? .allNotes }
    var showsSidebarIndex: Bool { !showsSettings && !isCreatingItem && (item == .sources || item == .collections) }
    var canSearchList: Bool { !showsSettings && item != .sources && item != .collections }

    /// Shows Settings, at `page` when one is given and at the page shown last otherwise.
    func showSettings(_ page: SettingsPage? = nil) {
        if let page { settingsPage = page }
        showsSettings = true
    }

    /// Settings gives way to whatever the window showed, or to a place chosen in the sidebar.
    func leaveSettings() { showsSettings = false }

    /// The folder the sidebar has selected, which the folder commands act on.
    var selectedFolder: ItemID? {
        if case .folder(let id) = item { id } else { nil }
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the window shows the gallery or the table, which span it, rather than the list beside the page.
    var usesCollection: Bool { viewMode.spansWindow }
    var showsCollection: Bool { usesCollection && !isCollectionItemPresented && !isCreatingItem }

    func openCollectionSelection() {
        leaveSettings()
        guard usesCollection, selection.count == 1 else { return }
        isCollectionItemPresented = true
        focusRequest = nil
    }

    func reveal(_ item: Item, in library: any ItemLibrary, order: NoteOrder) {
        leaveSettings()
        if !items(in: library).contains(where: { $0.id == item.id }) {
            show(.allNotes, in: library, order: order)
        }
        selection = [item.id]
        if usesCollection { openCollectionSelection() }
        else { focusRequest = .list }
    }

    /// Shows the note a link in the page names, as choosing it in the list does: the window's place, search, undo
    /// and the rest of its state are left as they are unless the note is not in the list, which then shows All Items.
    /// The keyboard stays with the page, as it does when a link is followed anywhere.
    func open(linked item: Item, in library: any ItemLibrary, order: NoteOrder) {
        reveal(item, in: library, order: order)
        if !usesCollection { focusRequest = .page }
    }

    /// Whether an earlier item the window showed can still be shown again.
    func canGoBack(in library: any ItemLibrary) -> Bool {
        history.target(.back, in: library, shown: selection) != nil
    }

    func canGoForward(in library: any ItemLibrary) -> Bool {
        history.target(.forward, in: library, shown: selection) != nil
    }

    /// Shows the item before, or after, the one shown, skipping any that are gone. It is shown in the place it was
    /// last seen when that place still lists it, and in All Items otherwise; any search is put away to show it.
    func go(_ direction: SelectionHistory.Direction, in library: any ItemLibrary) {
        guard let (index, entry) = history.target(direction, in: library, shown: selection) else { return }
        leaveSettings()
        isMovingThroughHistory = true
        defer { isMovingThroughHistory = false }
        isCreatingItem = false
        isCollectionItemPresented = false
        if isSearching || sidebarItem != entry.place {
            searchText = ""
            isSearchExpanded = false
            sidebarItem = entry.place
        }
        if !items(in: library).contains(where: { $0.id == entry.id }) { sidebarItem = .allNotes }
        selection = [entry.id]
        history.move(to: index)
        focusRequest = .list
    }

    func returnToCollection() {
        isCreatingItem = false
        isCollectionItemPresented = false
        focusRequest = .list
    }

    /// The items the list shows: the search results while searching, the sidebar item's items otherwise.
    func items(in library: any ItemLibrary) -> [Item] {
        isSearching ? library.items(matching: searchText) : library.items(in: item)
    }

    /// The selected items that still exist.
    func selectedItems(in library: any ItemLibrary) -> [Item] {
        isCreatingItem ? [] : selection.compactMap { library.item($0) }
    }

    /// The list's sections. Favorites lead wherever they mean something: not in Favorites itself, where every
    /// note is one, nor in search results.
    func sections(in library: any ItemLibrary, order: NoteOrder, now: Date) -> [NoteSection] {
        NoteGroup.sections(
            of: items(in: library),
            sort: order.sort,
            favoritesFirst: !isSearching && !showsOnlyFavorites,
            groupsByDate: order.groupsByDate,
            now: now
        )
    }

    /// Whether the list mixes notes from several places, so each row says where its note lives.
    var showsFolders: Bool {
        isSearching || item == .allNotes || showsOnlyFavorites
    }

    /// What the rows of the list say about themselves: the type where the list holds several, the place where it
    /// mixes places, and nothing that the list itself already says.
    func metaContext(for items: [Item]) -> ItemMeta.Context {
        var context = ItemMeta.Context()
        context.mixesTypes = Set(items.lazy.map(\.type)).count > 1
        context.showsPlaces = showsFolders
        if !isSearching {
            if case .collection(let id) = item { context.collection = id }
            context.isInbox = item == .inbox
        }
        return context
    }

    private var showsOnlyFavorites: Bool {
        if case .favoriteItem = item { return true }
        return item == .favorites
    }

    /// Shows a sidebar item as a person picks it: any search is cleared and the list's first note is selected.
    func show(_ item: SidebarItem, in library: any ItemLibrary, order: NoteOrder) {
        leaveSettings()
        isCreatingItem = false
        isCollectionItemPresented = false
        searchText = ""
        isSearchExpanded = false
        sidebarItem = item
        selectFirstNote(in: library, order: order)
    }

    func selectFirstNote(in library: any ItemLibrary, order: NoteOrder) {
        let first = sections(in: library, order: order, now: library.now()).first?.items.first
        selectAutomatically(first.map { [$0.id] } ?? [])
    }

    /// Moves the selection as the app does, not as the person chose, so Back does not stop there.
    private func selectAutomatically(_ ids: Set<ItemID>) {
        isSelectingAutomatically = true
        defer { isSelectingAutomatically = false }
        selection = ids
    }

    /// Keeps the selection in the list after notes leave it or the search changes it (see `selection(_:keptFrom:in:)`).
    func keepSelection(from old: [ItemID], to new: [ItemID]) {
        let kept = Self.selection(selection, keptFrom: old, in: new)
        if kept != selection { selectAutomatically(kept) }
    }

    /// A draft belongs to the window, so leaving its page never discards what was typed.
    func startItemDraft(typeID: String? = nil) {
        leaveSettings()
        if itemDraft == nil || (typeID != nil && itemDraft?.hasText == false && creation == nil) {
            itemDraft = NewItemDraft(place: item)
            if let typeID { itemDraft?.typeID = typeID }
        }
        isCreatingItem = true
        focusRequest = .page
    }

    /// Only an explicit discard confirmation may replace text. The identity check prevents an old dialog
    /// from discarding a newer draft, and a submitted creation must settle before another starts.
    @discardableResult
    func replaceItemDraft(_ confirmedDraft: NewItemDraft, typeID: String) -> Bool {
        guard itemDraft === confirmedDraft, creation == nil else { return false }
        itemDraft = nil
        startItemDraft(typeID: typeID)
        return true
    }

    /// Blank titles receive a unique name without requiring a naming dialog before typing. A library that shows
    /// the new item at once hands over to it here; one that shows it later, as a Marfa library does when its
    /// source answers, keeps the draft until `finishCreation` finds the item.
    func createDraft(in library: any ItemLibrary, undoManager: UndoManager?) -> ItemID? {
        // A second Return while the first is awaited makes nothing more.
        if let creation { return creation.id }
        guard let draft = itemDraft else { return nil }
        var title = NoteName.trimmed(draft.title)
        if title.isEmpty {
            let untitled = String(localized: "Untitled")
            title = untitled
            var suffix = 2
            while library.isItemTitleTaken(title) {
                title = "\(untitled) \(suffix)"
                suffix += 1
            }
        }
        guard let id = library.createItem(typeID: draft.typeID, title: title, body: draft.body, parentID: draft.parentID, in: draft.place, undoManager: undoManager) else { return nil }
        creation = Creation(id: id, typeID: draft.typeID, library: library)
        finishCreation(in: library)
        return id
    }

    /// Whether the item made from the draft is now held by the library, or was refused, and so is to be handed
    /// over to, or given back.
    func isCreationSettled(in library: any ItemLibrary) -> Bool {
        guard let creation else { return false }
        return library.item(creation.id) != nil || isRefused(creation, in: library)
    }

    /// Refused once queued, so its text is also in the problem the refusal shows, or refused before it was
    /// queued, so the draft holds the only copy. A create sent to another library counts as refused once this
    /// one has loaded without it, since it will not come.
    private func isRefused(_ creation: Creation, in library: any ItemLibrary) -> Bool {
        if creation.library !== library { return library.isLoaded }
        return library.wasRefused(creating: creation.id) || library.syncReport.problems.contains { $0.itemID == creation.id }
    }

    /// Hands the window over to the item made from the draft once the library holds it. The draft is kept until
    /// then, and given back to edit and send again if the item is refused; the library tells the person why.
    func finishCreation(in library: any ItemLibrary) {
        guard let creation else { return }
        guard library.item(creation.id) != nil else {
            if isRefused(creation, in: library) {
                self.creation = nil
                if creation.library !== library { fitDraft(to: library) }
            }
            return
        }
        self.creation = nil
        isCreatingItem = false
        itemDraft = nil
        isCollectionItemPresented = usesCollection
        searchText = ""
        isSearchExpanded = false
        if !library.items(in: item).contains(where: { $0.id == creation.id }) {
            sidebarItem = .itemType(creation.typeID)
        }
        selection = [creation.id]
        focusRequest = .page
    }

    /// Whether the draft has been sent and is waiting to be shown.
    var isAwaitingCreation: Bool { creation != nil }

    /// Starts the window afresh for a library other than the one it showed, the first time it is shown one: what
    /// it selected, searched or was renaming named items the new library may not have, and the window's undo
    /// would act on the library left. A draft is kept, since it is the person's text, unless the library left
    /// already holds the item made from it. One not yet answered stays sent, not editable, until the new library
    /// has loaded: a copy opened again over the same queue then shows the item, and the window hands over to it
    /// rather than let a second Return make it twice; a library that loads without it gives the draft back.
    func adopt(_ library: any ItemLibrary, undoManager: UndoManager? = nil) {
        let id = ObjectIdentifier(library)
        guard libraryID != id else { return }
        let isFirst = libraryID == nil
        let left = shownLibrary
        libraryID = id
        shownLibrary = library
        guard !isFirst else { return }
        undoManager?.removeAllActions()
        tableOptions = [:]
        boardFields = [:]
        compactBoards = [:]
        agendaFields = [:]
        selection = []
        history = SelectionHistory()
        isCollectionItemPresented = false
        sidebarItem = .allNotes
        searchText = ""
        isSearchExpanded = false
        renamingNote = nil
        renamingFolder = nil
        folderToDelete = nil
        palette = nil
        fetchedFile = nil
        if let creation, left?.item(creation.id) != nil {
            self.creation = nil
            itemDraft = nil
            isCreatingItem = false
        }
        finishCreation(in: library)
    }

    /// Fits the draft to the library the window shows once it has loaded, since before then it cannot say what it
    /// lacks. What changes is told to the person, never made silently. Nil where nothing changed.
    @discardableResult
    func fitDraft(to library: any ItemLibrary) -> (title: String, message: String)? {
        guard library.isLoaded, creation == nil, let changed = itemDraft?.fit(to: library) else { return nil }
        library.failure = changed
        return changed
    }

    func fileFetched(_ id: ItemID, at url: URL?) {
        fetchedFile = url.map { (id, $0) }
    }

    /// Where an item's file is, for sharing: the library's own answer, or the file it fetched to show.
    func fileURL(of id: ItemID, in library: any ItemLibrary) -> URL? {
        library.fileURL(for: id) ?? fetchedFile.flatMap { $0.id == id ? $0.url : nil }
    }

    func newFolder(in library: any ItemLibrary, order: NoteOrder, undoManager: UndoManager?) {
        guard library.capabilities.contains(.folders) else { return }
        let folder = library.newFolder(undoManager: undoManager)
        show(.folder(folder.id), in: library, order: order)
        renamingFolder = folder.id
    }

    /// Notes in the list go to Recently Deleted, which undoes. Notes already there are erased for good once the
    /// person confirms, since that cannot be undone, where the library can erase them.
    static func delete(_ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?) {
        let alreadyDeleted = Set(ids.compactMap { library.item($0) }.filter { $0.state == .trashed }.map(\.id))
        if !alreadyDeleted.isEmpty, library.capabilities.contains(.purge) { library.notesToPurge = alreadyDeleted }
        library.delete(ids.subtracting(alreadyDeleted), undoManager: undoManager)
    }

    /// Dropped items move into a folder or the Inbox, where the library moves items.
    static func canDrop(on place: SidebarItem, in library: any ItemLibrary) -> Bool {
        switch place {
        case .inbox, .folder: library.capabilities.contains(.move)
        case .recents, .allNotes, .favorites, .favoriteItem, .itemType, .collection, .collections, .sources, .source, .files, .recentlyDeleted: false
        }
    }

    /// A folder that is gone, by deletion or by undoing its creation, can no longer be shown; All Notes is. So is a type that no longer holds an item.
    func folderRemoved(in library: any ItemLibrary, order: NoteOrder) {
        if case .folder(let id) = sidebarItem, library.folder(id) == nil {
            show(.allNotes, in: library, order: order)
        }
        if case .collection(let id) = sidebarItem, library.item(id)?.state != .active {
            show(.allNotes, in: library, order: order)
        }
        // A type is in the sidebar while it holds an item, so one whose last item went has no row to stay on.
        if case .itemType(let type) = sidebarItem, library.isLoaded, library.count(in: .itemType(type)) == 0 {
            show(.allNotes, in: library, order: order)
        }
        if case .favoriteItem(let id) = sidebarItem,
           library.item(id).map({ $0.state == .active && $0.isFavorite }) != true {
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
        var viewMode: ItemViewMode = .list
    }

    func snapshot() -> Snapshot {
        Snapshot(place: item, selection: selection.sorted { $0.rawValue < $1.rawValue }, viewMode: viewMode)
    }

    /// Restores a window from what it kept. A snapshot that does not read, one kept in an earlier form say,
    /// leaves the window at its default.
    func restore(from data: Data?, in library: any ItemLibrary, order: NoteOrder) {
        if let data, let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) {
            restore(snapshot, in: library, order: order)
        } else {
            selectFirstNote(in: library, order: order)
        }
    }

    /// Restores what still exists: a place gone since gives way to All Notes, or Favorites for a favorite, and
    /// items no longer in the list are dropped, leaving the top row selected if none remain.
    func restore(_ snapshot: Snapshot, in library: any ItemLibrary, order: NoteOrder) {
        viewMode = snapshot.viewMode
        sidebarItem = switch snapshot.place {
        case .favoriteItem(let id):
            library.item(id).flatMap { $0.isFavorite && $0.state == .active ? snapshot.place : nil } ?? .favorites
        case .collection(let id): library.item(id).map { _ in snapshot.place } ?? .allNotes
        case .folder(let id): library.folder(id).map { _ in snapshot.place } ?? .allNotes
        case .itemType(let type):
            library.itemTypeCounts.contains { $0.id.rawValue == type } ? snapshot.place : .allNotes
        case .inbox, .recents, .allNotes, .favorites, .files, .sources, .source, .collections, .recentlyDeleted: snapshot.place
        }
        let ids = Set(snapshot.selection)
        selectAutomatically(Set(items(in: library).map(\.id).filter(ids.contains)))
        if selection.isEmpty { selectFirstNote(in: library, order: order) }
    }
}

/// The single items a window has shown, oldest first, and which of them it shows now.
struct SelectionHistory {
    struct Entry: Equatable {
        let place: SidebarItem
        let id: ItemID
    }

    nonisolated enum Direction { case back, forward }

    private static let limit = 100
    private(set) var entries: [Entry] = []
    private var position = -1

    /// Notes the selection after a change. Only one item shown is an entry; showing it again leaves the history as
    /// it is, and showing another drops whatever lay ahead.
    mutating func record(_ selection: Set<ItemID>, in place: SidebarItem) {
        guard selection.count == 1, let id = selection.first else { return }
        if entries.indices.contains(position), entries[position].id == id { return }
        entries.removeSubrange((position + 1)...)
        entries.append(Entry(place: place, id: id))
        if entries.count > Self.limit { entries.removeFirst(entries.count - Self.limit) }
        position = entries.count - 1
    }

    mutating func move(to index: Int) {
        guard entries.indices.contains(index) else { return }
        position = index
    }

    /// The nearest entry in a direction whose item still exists and is not the one shown now (the app can move the
    /// selection off the entry the history is at). A deleted item is not shown, since no place lists it.
    func target(_ direction: Direction, in library: any ItemLibrary, shown: Set<ItemID>) -> (index: Int, entry: Entry)? {
        let candidates = direction == .back ? Array(entries.indices.prefix(max(position, 0)).reversed()) : Array(entries.indices.dropFirst(position + 1))
        return candidates.lazy.map { ($0, entries[$0]) }.first { _, entry in
            guard shown != [entry.id], let item = library.item(entry.id) else { return false }
            return item.state != .trashed
        }
    }
}

@Observable
final class NewItemDraft {
    var typeID: String
    var title = ""
    var body = ""
    var parentID: ItemID?
    let place: SidebarItem

    var hasText: Bool { !title.isEmpty || !body.isEmpty }

    init(place: SidebarItem) {
        self.place = place
        if case .itemType(let id) = place { typeID = id } else { typeID = "core.note" }
        if case .collection(let id) = place { parentID = id }
    }

    /// A type picked before the page opens must validate its inherited parent just like a later type change.
    func validateParent(in library: any ItemLibrary) {
        guard library.isLoaded, let parentID else { return }
        if !library.creationParentCandidates(typeID: typeID).contains(where: { $0.id == parentID }) {
            self.parentID = nil
        }
    }

    /// A draft carried to another library keeps its text and what the loaded library can still hold: a parent it
    /// does not have is dropped, and a kind it does not know gives way to a note. Answers what changed, in words
    /// for the person, or nil where nothing did.
    func fit(to library: any ItemLibrary) -> (title: String, message: String)? {
        guard library.isLoaded else { return nil }
        let losesParent = parentID.map { library.item($0) == nil } ?? false
        let losesType = library.catalogue.itemTypes[TypeID(typeID)] == nil
        if losesParent { parentID = nil }
        if losesType { typeID = "core.note" }
        let message: String
        switch (losesType, losesParent) {
        case (true, true):
            message = String(localized: "The library now open doesn’t have the kind of item you chose or the item you chose as its parent, so your new item is a note with no parent. Check it before you create it.")
        case (true, false):
            message = String(localized: "The library now open doesn’t have the kind of item you chose, so your new item is a note. Check it before you create it.")
        case (false, true):
            message = String(localized: "The library now open doesn’t have the item you chose as its parent, so your new item has no parent. Check it before you create it.")
        case (false, false):
            return nil
        }
        return (String(localized: "New Item Changed"), message)
    }
}
