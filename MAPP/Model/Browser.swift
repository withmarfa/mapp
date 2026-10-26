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
            if viewMode.spansWindow { focusRequest = .list }
        }
    }
    var isCollectionItemPresented = false

    /// The layouts the current place can show. Search is left out, so a search with no results keeps the layout.
    /// A type's own place counts the type even while it holds no items.
    func availableViewModes(in library: any ItemLibrary) -> [ItemViewMode] {
        guard library.isLoaded else { return ItemViewMode.allCases }
        var types = Set(library.items(in: item).map(\.type))
        if case .itemType(let type) = item { types.insert(TypeID(type)) }
        return ItemViewMode.available(forTypes: types, catalogue: library.catalogue)
    }

    /// A window left on a layout its place cannot show goes back to the list without saying so. The indexes of
    /// collections and sources have no layout, so they leave it as it is for the place that follows to judge.
    func fallBackToListIfUnavailable(in library: any ItemLibrary) {
        guard !showsSidebarIndex, !showsSettings, !availableViewModes(in: library).contains(viewMode) else { return }
        viewMode = .list
    }
    /// How each place's table is grouped, sorted and filtered, as the person left it, for the life of the window.
    var tableOptions: [SidebarItem: ItemTableOptions] = [:]
    var boardFields: [SidebarItem: String] = [:]
    var compactBoards: [SidebarItem: Bool] = [:]
    var agendaFields: [SidebarItem: String] = [:]
    /// Whether the window shows Settings in place of the list and the item page. The place the window was
    /// showing, and its selection are kept, so choosing that place again returns to them.
    private(set) var showsSettings = false
    /// The page of Settings shown, and the one shown next time Settings is.
    var settingsPage = SettingsPage.appearance
    var searchText = ""
    /// Where the keyboard should go next, asked for by an action such as New Note or Search Notes. Whatever
    /// can take it grants it once, when it is able to, and clears it.
    var focusRequest: Pane?
    /// The palette that is out, if any: ⌘K's commands, or ⇧⌘P's search of every note. One panel is out at a time,
    /// so the palette puts quick add away, keeping its draft.
    var palette: Palette? {
        didSet { if palette != nil { quickAdd.isPresented = false } }
    }
    /// The window's quick-add panel and what is typed in it.
    let quickAdd = QuickAdd()
    /// Whether the list's search is out as a field, rather than a button beside View Options.
    var isSearchExpanded = false
    /// Counts each request for the list's search, so a field already out takes the keyboard again.
    var searchFocusRequests = 0
    /// The item quick add made that the window opens once its library holds it (see `NewItem`).
    var newItem: NewItem?
    /// Where the page puts the caret when it next takes the keyboard for a new item.
    var focusCaret: PageCaret?
    /// What the page writes for the files quick add attached to a new item, which it puts at the end of the text
    /// once it shows that item.
    var newEmbeds: NewEmbeds?
    /// The files of a new item being attached, kept so a test can wait for them.
    @ObservationIgnored var attachingNewItem: Task<Void, Never>?
    /// A file the library had to fetch to show, so the commands that share it have its location too.
    private(set) var fetchedFile: (id: ItemID, url: URL)?
    /// The library this window was last shown, so a different one starts the window afresh.
    @ObservationIgnored private var libraryID: ObjectIdentifier?

    nonisolated enum Palette: Hashable {
        case commands, search
    }

    nonisolated enum Pane: Hashable {
        case sidebar, list, page, search
        /// The page, with the item's title taking the keyboard.
        case title
    }

    var item: SidebarItem { sidebarItem ?? .allNotes }
    var showsSidebarIndex: Bool { !showsSettings && (item == .sources || item == .collections) }
    var canSearchList: Bool { !showsSettings && item != .sources && item != .collections }

    /// Shows Settings, at `page` when one is given and at the page shown last otherwise.
    func showSettings(_ page: SettingsPage? = nil) {
        if let page { settingsPage = page }
        showsSettings = true
    }

    /// Settings gives way to whatever the window showed, or to a place chosen in the sidebar.
    func leaveSettings() { showsSettings = false }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the window shows the gallery or the table, which span it, rather than the list beside the page.
    var usesCollection: Bool { viewMode.spansWindow }
    var showsCollection: Bool { usesCollection && !isCollectionItemPresented }

    /// Whether the view's options are on offer: the list and the gallery always, the table, board and agenda only
    /// while they are showing, not an item page opened from them, which hides their controls.
    var offersViewOptions: Bool { !usesCollection || showsCollection }

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
        isCollectionItemPresented = false
        focusRequest = .list
    }

    /// The items the list shows: the search results while searching, the sidebar item's items otherwise.
    func items(in library: any ItemLibrary) -> [Item] {
        isSearching ? library.items(matching: searchText) : library.items(in: item)
    }

    /// The selected items that still exist.
    func selectedItems(in library: any ItemLibrary) -> [Item] {
        selection.compactMap { library.item($0) }
    }

    /// Whether the list shows its place's own order rather than the chosen sort: a collection lists its members in
    /// the order Marfa keeps for them, until a search lists results instead.
    var keepsPlaceOrder: Bool {
        guard !isSearching, case .collection = item else { return false }
        return true
    }

    /// The list's sections. Favorites lead wherever they mean something: not in Favorites itself, where every
    /// note is one, nor in search results. A place that keeps its own order is one section, in that order.
    func sections(in library: any ItemLibrary, order: NoteOrder, now: Date) -> [NoteSection] {
        if keepsPlaceOrder {
            let items = items(in: library)
            return items.isEmpty ? [] : [NoteSection(group: nil, items: items)]
        }
        return NoteGroup.sections(
            of: items(in: library),
            sort: order.sort,
            favoritesFirst: !isSearching && !showsOnlyFavorites,
            groupsByDate: order.groupsByDate,
            now: now
        )
    }

    /// What the rows of the list say about themselves: the type where the list holds several, and nothing that the
    /// list itself already says.
    func metaContext(for items: [Item]) -> ItemMeta.Context {
        var context = ItemMeta.Context()
        context.mixesTypes = Set(items.lazy.map(\.type)).count > 1
        if !isSearching {
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
        isCollectionItemPresented = false
        searchText = ""
        isSearchExpanded = false
        sidebarItem = item
        fallBackToListIfUnavailable(in: library)
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

    /// Starts the window afresh for a library other than the one it showed, the first time it is shown one: what
    /// it selected or searched named items the new library may not have, and the window's undo
    /// would act on the library left. A new item awaited there will not come. Quick add's draft has already gone to
    /// the clipboard, as the window's view of the library left went (`QuickAdd.Departure.libraryChanged`).
    func adopt(_ library: any ItemLibrary, undoManager: UndoManager? = nil) {
        let id = ObjectIdentifier(library)
        guard libraryID != id else { return }
        let isFirst = libraryID == nil
        libraryID = id
        guard !isFirst else { return }
        undoManager?.removeAllActions()
        tableOptions = [:]
        viewSeeds = [:]
        viewEditing = nil
        viewTitleForm?.handOff(because: .libraryChanged)
        viewTitleForm = nil
        boardFields = [:]
        compactBoards = [:]
        agendaFields = [:]
        selection = []
        history = SelectionHistory()
        isCollectionItemPresented = false
        sidebarItem = .allNotes
        searchText = ""
        isSearchExpanded = false
        palette = nil
        fetchedFile = nil
        giveUpNewItem(because: .windowLeft)
        focusCaret = nil
        newEmbeds = nil
    }

    func fileFetched(_ id: ItemID, at url: URL?) {
        fetchedFile = url.map { (id, $0) }
    }

    /// Where an item's file is, for sharing: the file the window fetched to show.
    func fileURL(of id: ItemID) -> URL? {
        fetchedFile.flatMap { $0.id == id ? $0.url : nil }
    }

    /// Notes in the list go to Recently Deleted, which undoes. Notes already there are erased for good once the
    /// person confirms, since that cannot be undone, where the library can erase them.
    static func delete(_ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?) {
        let alreadyDeleted = Set(ids.compactMap { library.item($0) }.filter { $0.state == .trashed }.map(\.id))
        if !alreadyDeleted.isEmpty, library.canPurge { library.notesToPurge = alreadyDeleted }
        library.delete(ids.subtracting(alreadyDeleted), undoManager: undoManager)
    }

    /// A place that is gone can no longer be shown, so the window moves to All Items: a collection no longer
    /// active, a type that no longer holds an item, or a view deleted elsewhere.
    func placeRemoved(in library: any ItemLibrary, order: NoteOrder) {
        if case .collection(let id) = sidebarItem, library.item(id)?.state != .active {
            show(.allNotes, in: library, order: order)
        }
        // A type is in the sidebar while it holds an item, so one whose last item went has no row to stay on.
        if case .itemType(let type) = sidebarItem, library.isLoaded, library.count(in: .itemType(type)) == 0 {
            show(.allNotes, in: library, order: order)
        }
        if case .view(let id) = sidebarItem, library.isLoaded, !library.views.contains(where: { $0.id == id }) {
            show(.allNotes, in: library, order: order)
        }
        if case .favoriteItem(let id) = sidebarItem,
           library.item(id).map({ $0.state == .active && $0.isFavorite }) != true {
            show(.favorites, in: library, order: order)
        }
    }

    // MARK: Saved views

    /// A saved view the window is about to save, rename, update or delete, which asks the person first.
    nonisolated enum ViewEditing: Hashable, Identifiable {
        case new
        case rename(ItemID)
        case update(ItemID)
        case delete(ItemID)
        var id: Self { self }
    }

    var viewEditing: ViewEditing?

    /// The title the view sheet holds until the server takes it, kept here so a window that closes or changes
    /// library can give it back.
    var viewTitleForm: ViewTitleForm?

    /// The order and grouping a view opened with, and the version of the view they came from, which an update of
    /// them is based on.
    struct ViewSeed: Hashable {
        let version: Int64
        let options: ItemTableOptions
    }

    private(set) var viewSeeds: [ItemID: ViewSeed] = [:]

    /// Shows a view's own order and grouping the first time the window opens it, and again when the view changes,
    /// unless the person has changed them since: those stay, and an update of them is based on what they changed.
    func followView(in library: any ItemLibrary) {
        guard case .view(let id) = item, let view = library.views.first(where: { $0.id == id }) else { return }
        if let seed = viewSeeds[id] {
            guard seed.version != view.version, !ViewDraft.differs(tableOptions[item], from: seed.options) else { return }
        }
        seed(view)
    }

    private func seed(_ view: LibraryView) {
        let place = SidebarItem.view(view.id)
        var options = ViewDraft.options(for: view)
        let collapsed = tableOptions[place]?.collapsed
        viewSeeds[view.id] = ViewSeed(version: view.version, options: options)
        options.collapsed = collapsed
        tableOptions[place] = options
    }

    /// Whether the window's order, grouping or filters differ from those of the view it shows.
    var hasViewChanges: Bool {
        guard case .view(let id) = item, let seed = viewSeeds[id] else { return false }
        // Only the table shows a view's order, grouping and filters, so only the table offers to update it.
        return viewMode == .table && ViewDraft.differs(tableOptions[item], from: seed.options)
    }

    /// The change that saves the window's choices to the view it shows, the version it is based on, and what of
    /// the window it leaves out.
    func viewUpdate(_ window: ViewDraft.Window, in library: any ItemLibrary) -> ViewUpdate? {
        guard case .view(let id) = item, let seed = viewSeeds[id], let view = library.views.first(where: { $0.id == id }) else {
            return nil
        }
        let update = ViewDraft.change(window, options: tableOptions[item], seed: seed.options, view: view)
        return ViewUpdate(view: view, change: update.change, baseVersion: seed.version, unkept: update.unkept, unchanged: update.unchanged)
    }

    struct ViewUpdate {
        let view: LibraryView
        let change: LibraryViewChange
        let baseVersion: Int64
        /// What of the window the view will not keep.
        let unkept: [ViewDraft.Unkept]
        /// The conditions of the view's filter the window cannot show, which the update leaves as they are.
        let unchanged: [String]
    }

    /// After an update the view holds the window's choices, so its filters are the view's own.
    func viewUpdated(_ view: LibraryView) {
        seed(view)
    }

    /// An update refused because the view changed elsewhere puts the window back to the view as the library holds
    /// it, and to its next version when that arrives.
    func viewRefused(_ id: ItemID, in library: any ItemLibrary) {
        viewSeeds[id] = nil
        followView(in: library)
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
        case .itemType(let type):
            library.itemTypeCounts.contains { $0.id.rawValue == type } ? snapshot.place : .allNotes
        case .view(let id): library.views.contains { $0.id == id } ? snapshot.place : .allNotes
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
