import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected items and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var showing: PlaceView? = .library {
        // A scroll position belongs to the place and layout it was made in.
        didSet {
            guard showing != oldValue else { return }
            modalItem = nil
            listMemory.scrollOffset = nil
            viewPanelPlaceChanged()
        }
    }
    /// Whether the sidebar's Types block lists every type rather than the first few. The window mounts its split view
    /// afresh when the place changes shape (list, gallery, index, Settings), which drops the sidebar's own state, so
    /// this is kept here, where Show More stays open through that.
    var sidebarShowsAllTypes = false
    /// Whether this window is arranging its sidebar in place. The layout is shared by every window of the library, but
    /// arranging is this window's: Done ends it only here.
    var customizesSidebar = false
    /// The identifier of the tab this window has open; nil, or a tab since removed, is the first.
    var sidebarTab: String?
    /// The rest of what the sidebar keeps through that: its scroll position and its foot's measures.
    @ObservationIgnored let sidebarMemory = ColumnMemory()
    /// How far the list, table or gallery is scrolled, kept for the same reasons and for the next launch (`snapshot()`).
    @ObservationIgnored let listMemory = ColumnMemory()
    /// The rows of the Items index under each tab, kept by the window so they survive an item's full page (`ItemIndexModel`).
    @ObservationIgnored let itemIndex = ItemIndexModel()
    /// The item whose row Items scrolls into view once it shows it, asked for by a reveal (`revealOnItems`).
    var itemToScrollTo: ItemID?
    var selection: Set<ItemID> = [] {
        didSet {
            // The modal shows the one item it was opened on, so any other selection, whoever made it, is the end of it.
            if let open = modalItem, selection != [open] { modalItem = nil }
            guard !isMovingThroughHistory, !isSelectingAutomatically || history.entries.isEmpty else { return }
            history.record(selection, in: shown)
        }
    }
    /// The items the person chose in this window, for Back and Forward: a click, a key in the list, a link or a
    /// palette jump's destination. The app's own moves (the first item of a place, the next item after a delete
    /// or a search) are left out, except the item the window opens on, so Back can return to it. Kept for the
    /// life of the window, not across launches.
    private(set) var history = SelectionHistory()
    @ObservationIgnored private var isMovingThroughHistory = false
    @ObservationIgnored var isSelectingAutomatically = false
    var viewMode: ItemViewMode = .list {
        didSet {
            if viewMode != oldValue {
                showsCalendarMonth = false
                listMemory.scrollOffset = nil
                recordLayout(from: oldValue)
            }
            isCollectionItemPresented = false
            modalItem = nil
            if viewMode.spansWindow { focusRequest = .list }
        }
    }
    /// Whether an item's page takes the window in place of the layout, with a Back button: opened as a full page from
    /// a layout that spans the window or from the list (`open(_:as:)`).
    var isCollectionItemPresented = false
    /// The item open in the modal over the window, or nil. The selection is always this item while it is set
    /// (`selection`'s observer ends the modal otherwise), so the page, the toolbar and the commands read the selection
    /// as they do anywhere else. Set only through `open(_:as:)`, `moveModal` and `closeModal` (`Browser+Opening`).
    var modalItem: ItemID?
    /// Opens items in windows of their own, which only a view can do. The window wires it where it makes its editor.
    @ObservationIgnored var windowOpener: ((Set<ItemID>) -> Void)?

    /// The layouts the current place can show. Search is left out, so a search with no results keeps the layout.
    /// A type's own place counts the type even while it holds no items. The last answer stands until the library's
    /// membership, the place or its stacking changes, since the window asks on every click and edit.
    func availableViewModes(in library: any ItemLibrary) -> [ItemViewMode] {
        guard library.isLoaded else { return ItemViewMode.allCases }
        let membership = library.membershipRevision
        // A saved view lists what the library reads for it, later, and without a membership change.
        let key = ViewModesKey(
            library: ObjectIdentifier(library), membership: membership, place: shown, listing: listing,
            viewItems: isViewPlace ? placeItems(in: library).map(\.id) : nil)
        if let held = viewModesMemo, held.key == key { return held.modes }
        let modes = Cost.measure(.viewModes) {
            var types = Set(placeItems(in: library).map(\.type))
            if case .type(let type) = shown.place { types.insert(type) }
            return ItemViewMode.available(forTypes: types, catalogue: library.catalogue)
        }
        viewModesMemo = (key, modes)
        return modes
    }

    private struct ViewModesKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let place: PlaceView
        let listing: PlaceListing
        let viewItems: [ItemID]?
    }

    /// Where each item stands in the sort the board's cards follow: the place's sort where the person or the view set
    /// one, else nil, which keeps the cards by title.
    func boardCardOrder(in library: any ItemLibrary) -> [ItemID: Int]? {
        guard tableOptions[shown]?.sort?.isEmpty == false else { return nil }
        let rows = tableContent(in: library).rows
        return Dictionary(rows.enumerated().map { ($0.element.item.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }

    /// How a field's column is named among the table's columns (`ItemTableLayout.columns`).
    nonisolated static let fieldColumnPrefix = "field."

    /// The date fields a timeline of the place's items can place them on: the fields come from the types the items have,
    /// which change only with the library's membership or catalogue, so an edit asks nothing of the items.
    func timelineFieldChoices(in library: any ItemLibrary) -> [ItemTypeInfo.Field] {
        let derived = fieldsKey(in: library)
        if let held = fieldsMemo, held.key == derived.key, let fields = held.timeline { return fields }
        let fields = ItemTimelineLayout.fields(for: derived.items ?? items(in: library), catalogue: library.catalogue)
        fieldsMemo = FieldsMemo(key: derived.key, timeline: fields)
        return fields
    }

    /// Sets the date field the timeline places every item by, or, with nil, lets each item sit on the date its type's
    /// look names. Nil is no choice, so a place that is not a view has only what its default view kept and a view writes no day grouping.
    func setTimelineField(_ key: String?, in library: any ItemLibrary) {
        timelineFields[shown] = key
    }

    private func fieldsKey(in library: any ItemLibrary) -> (key: FieldsKey, items: [Item]?) {
        let listed = isSearching || isViewPlace ? items(in: library) : nil
        let key = FieldsKey(
            library: ObjectIdentifier(library), membership: library.membershipRevision, place: shown, listing: listing,
            ids: listed?.map(\.id))
        return (key, listed)
    }

    private struct FieldsKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let place: PlaceView
        let listing: PlaceListing
        let ids: [ItemID]?
    }

    private struct FieldsMemo {
        let key: FieldsKey
        var timeline: [ItemTypeInfo.Field]?
    }

    /// A window left on a layout its place cannot show goes back to the list without saying so. The indexes of
    /// collections and sources have no layout, so they leave it as it is for the place that follows to judge.
    func fallBackToListIfUnavailable(in library: any ItemLibrary) {
        guard !showsSidebarIndex, !availableViewModes(in: library).contains(viewMode) else { return }
        set(layout: .list)
    }
    /// How each place's table is grouped, sorted and filtered, as the person left it. A place that is not a saved view
    /// keeps them in its default view too (`Browser+PlaceDefaults`).
    var tableOptions: [PlaceView: ItemTableOptions] = [:]
    /// The pages of the table the person has loaded, with what they belong to. Held apart from the table's content,
    /// which a page never makes again, and read as one page once the key has changed (`tablePaging`).
    var pagingState: (key: TablePagingKey, paging: TablePaging)?
    @ObservationIgnored var tableMemo: (key: TableKey, content: ItemTableContent)?
    @ObservationIgnored var sectionsMemo: (key: SectionsKey, sections: [ItemSection])?
    @ObservationIgnored private var viewModesMemo: (key: ViewModesKey, modes: [ItemViewMode])?
    @ObservationIgnored private var fieldsMemo: FieldsMemo?
    /// The last Group by offer, while the table's content and the layout it was made for stand (`Browser+Grouping`).
    @ObservationIgnored var groupOfferMemo: GroupOfferMemo?
    /// The content of the list's rows, held between passes (`Browser+Rows`).
    @ObservationIgnored let rowContents = RowContents()
    /// The person's chosen looks for this library's types, which the window's root seeds and keeps current (`RootView`).
    /// The list, the gallery, the board and the table read the looks they resolve to (`looks(in:)`), so a change of
    /// choice works each out again.
    var lookChoices: [TypeID: TypeLookChoice] = [:]
    @ObservationIgnored var looksMemo: (key: LooksKey, looks: [TypeID: TypeLook])?
    /// Held by `paletteIndex(in:)`.
    @ObservationIgnored var paletteMemo: (key: PaletteIndexKey, index: PaletteIndex)?
    var compactBoards: [PlaceView: Bool] = [:]
    /// The date field each place's timeline shows its items by, where the person chose one. A view's own comes from
    /// its day grouping (`followView`).
    var timelineFields: [PlaceView: String] = [:]
    /// Opens the Settings window at a page, or where it was left when none is given. Settings is a window of its own, so
    /// the browser keeps nothing of it; the window's views set this to the app's launcher.
    @ObservationIgnored var openSettings: (SettingsPage?, SettingsSubpage?) -> Void = { _, _ in }
    var searchText = "" {
        didSet { if !isSearching { relevanceChoice = nil } }
    }
    /// What the person chose for the order of the search under way: relevance, or one of the sorts. Nil leaves the
    /// layout's own start (`ordersByRelevance`). It is forgotten when the search ends, so the next one starts again
    /// and the person's own sort, which relevance never touches, is the order once more.
    var relevanceChoice: Bool?
    /// Whether the search covers only the place shown rather than everything. It applies wherever the place can be
    /// searched alone (`SearchScope.narrows`) and means everything elsewhere.
    var searchesPlace = false
    /// Where the keyboard should go next, asked for by an action such as New Item or Search Items. Whatever
    /// can take it grants it once, when it is able to, and clears it.
    var focusRequest: Pane?
    /// The palette that is out, if any: ⌘K's commands, or ⇧⌘P's search of every item. One panel is out at a time,
    /// so the palette puts quick add away, keeping its draft.
    var palette: Palette? {
        didSet {
            guard palette != nil else { return }
            Telemetry.event(.navigation, "palette.open")
            quickAdd.isPresented = false
        }
    }
    /// What the next palette starts with typed, as ⌘K's "Search Items for" hands its words on.
    var paletteSeed = ""
    /// Counts the ⌘J (Palette Actions) pressed while a palette is out, which opens or shuts its Actions.
    var paletteActionsRequests = 0

    /// Whether a floating panel, the palette or quick add, is out over the window, which the views beneath it
    /// are sent no pointer exit for.
    var panelIsOut: Bool { palette != nil || (quickAdd.isPresented && quickAdd.draft != nil) || isModalPresented }
    /// The window's quick-add panel and what is typed in it.
    let quickAdd = QuickAdd()
    /// Whether the list's search is out as a field, rather than a button beside View Options.
    var isSearchExpanded = false
    /// Counts each request for the list's search, so a field already out takes the keyboard again.
    var searchFocusRequests = 0
    /// The item quick add made that the window opens once its library holds it (see `NewItem`).
    var newItem: NewItem?
    /// What Quick Look shows for the window, while it is open.
    var quickLook: QuickLookRequest?
    /// Counts Quick Look requests, so a slow one the person has since replaced or closed knows to stop.
    @ObservationIgnored var quickLookGeneration = 0
    /// Where the page puts the caret when it next takes the keyboard for a new item.
    var focusCaret: PageCaret?
    /// What the page writes for the files quick add attached to a new item, which it puts at the end of the text
    /// once it shows that item.
    var newEmbeds: NewEmbeds?
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

    var shown: PlaceView { showing ?? .library }
    /// Whether the window shows Items as an index, the table of every item with its right sidebar. Items has no list
    /// column and no layout, so whatever layout the window was last left on is not shown there. An item opened from it
    /// as a full page takes the window until Back.
    var showsItemsIndex: Bool { shown == .library && !isCollectionItemPresented }
    var showsSidebarIndex: Bool { shown == .sources || shown == .collections || showsItemsIndex }
    /// Whether an item's page is what the window shows, as against a collection, an index or Settings. The editor
    /// stays mounted behind the others, so every command that acts on the page asks this first. An item open in the
    /// modal is shown over an index as over any layout.
    var showsPage: Bool { isModalPresented || (!showsCollection && !showsSidebarIndex) }

    /// Shows Settings, at `page` when one is given and where it was left otherwise.
    func showSettings(_ page: SettingsPage? = nil, subpage: SettingsSubpage? = nil) {
        openSettings(page, subpage)
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the search lists its results as the library ranked them rather than by a sort. The list and Items start on
    /// relevance; the gallery and the table start on their own sorts and use relevance only once it is picked there.
    var ordersByRelevance: Bool {
        isSearching && (relevanceChoice ?? (viewMode == .list || shown == .library))
    }

    /// Picks relevance or one of the sorts for the search under way. Outside a search there is nothing to pick.
    func orderSearch(byRelevance: Bool) {
        if isSearching { relevanceChoice = byRelevance }
    }

    /// Whether the window shows the gallery or the table, which span it, rather than the list beside the page. Items is
    /// an index, not a layout, so it never does.
    var usesCollection: Bool { viewMode.spansWindow && shown != .library }
    var showsCollection: Bool { usesCollection && !isCollectionItemPresented }

    /// Whether the view's options are on offer: the list and the gallery always, the table, board and timeline only
    /// while they are showing, not an item page opened from them, which hides their controls.
    var offersViewOptions: Bool { !isCollectionItemPresented }

    /// Shows the place that lists an item no place on screen does: All Items, or for a deleted item Settings >
    /// Recently Deleted, the only list that holds it.
    private func showListing(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        if item.state == .trashed {
            showSettings(.recentlyDeleted)
        } else {
            show(.library, in: library, order: order)
        }
    }

    func reveal(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        // An item reached from the modal, by a link or the palette, is shown in the modal.
        let staysInModal = isModalPresented
        select(item, in: library, order: order)
        if staysInModal { open([item.id], as: .modal) }
        else if followsCollection { open([item.id], as: .fullPage) }
        else { focusRequest = .list }
    }

    /// Selects `item`, showing the place that lists it when the window's list does not.
    private func select(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        if !items(in: library).contains(where: { $0.id == item.id }) {
            showListing(item, in: library, order: order)
        }
        selection = [item.id]
        if shown == .library { revealOnItems(item) }
    }

    /// Shows the item a link in the page names, as choosing it in the list does: the window's place, search, undo
    /// and the rest of its state are left as they are unless the item is not in the list, which then shows the place
    /// that lists it (`showListing`). The keyboard stays with the page, as it does when a link is followed anywhere.
    func open(linked item: Item, in library: any ItemLibrary, order: ItemOrder) {
        reveal(item, in: library, order: order)
        if !followsCollection, !showsItemsIndex { focusRequest = .page }
    }

    /// Opens the item a link in the item's text names the way Settings > General > Open Items says, as Return does in
    /// the list: the item is selected where the window lists it, then shown in the modal, as a full page or in a
    /// window. An item reached from the modal stays in the modal, as `reveal` keeps it.
    func follow(link item: Item, in library: any ItemLibrary, order: ItemOrder, defaults: UserDefaults = .standard) {
        let staysInModal = isModalPresented
        select(item, in: library, order: order)
        open([item.id], as: staysInModal ? .modal : nil, defaults: defaults)
    }

    /// External links stay in this window even when Open Items is set to New Window.
    func open(itemLink item: Item, in library: any ItemLibrary, order: ItemOrder, defaults: UserDefaults = .standard) {
        let way: ItemOpening = !isModalPresented && ItemOpening.stored(in: defaults) == .fullPage ? .fullPage : .modal
        select(item, in: library, order: order)
        open([item.id], as: way, defaults: defaults)
    }

    /// Whether an earlier item the window showed can still be shown again.
    func canGoBack(in library: any ItemLibrary) -> Bool {
        history.target(.back, in: library, shown: selection) != nil
    }

    func canGoForward(in library: any ItemLibrary) -> Bool {
        history.target(.forward, in: library, shown: selection) != nil
    }

    /// Whether Back has anywhere to go, as the View menu and the sidebar's title bar offer it: out of a page opened from a
    /// collection's layout, or to an earlier item where the list is showing.
    func canStepBack(in library: any ItemLibrary) -> Bool {
        if usesCollection || isCollectionItemPresented { return isCollectionItemPresented }
        return canGoBack(in: library)
    }

    func canStepForward(in library: any ItemLibrary) -> Bool {
        !usesCollection && !isCollectionItemPresented && canGoForward(in: library)
    }

    func stepBack(in library: any ItemLibrary) {
        if isCollectionItemPresented { returnToCollection() } else { go(.back, in: library) }
    }

    func stepForward(in library: any ItemLibrary) {
        go(.forward, in: library)
    }

    /// Shows the item before, or after, the one shown, skipping any that are gone. It is shown in the place it was
    /// last seen when that place still lists it, and in All Items otherwise; any search is put away to show it.
    func go(_ direction: SelectionHistory.Direction, in library: any ItemLibrary) {
        guard let (index, entry) = history.target(direction, in: library, shown: selection) else { return }
        isMovingThroughHistory = true
        defer { isMovingThroughHistory = false }
        isCollectionItemPresented = false
        modalItem = nil
        if isSearching || showing != entry.place {
            searchText = ""
            isSearchExpanded = false
            showing = entry.place
        }
        if !items(in: library).contains(where: { $0.id == entry.id }) { showing = .library }
        selection = [entry.id]
        if shown == .library, let held = library.item(entry.id) { revealOnItems(held) }
        history.move(to: index)
        focusRequest = .list
    }

    func returnToCollection() {
        isCollectionItemPresented = false
        focusRequest = .list
    }

    /// The selected items that still exist.
    func selectedItems(in library: any ItemLibrary) -> [Item] {
        selection.compactMap { library.item($0) }
    }

    /// The selected items as a header shows them. A toolbar reads this: a keystroke, or a publish of only the version,
    /// preview, sync or embeds, is not a change it shows.
    func selectedHeaderItems(in library: any ItemLibrary) -> [Item] {
        selection.compactMap { library.headerItem($0) }
    }

    /// The links the table's shown columns hold, which its rows read besides those the looks and the options name.
    /// The table sets it (`showRelations(of:)`); it never changes what an observer reads, only what a row holds.
    @ObservationIgnored private(set) var shownRelations: Set<Relation> = []

    /// Notes which links the table shows, so its rows hold them. Returns whether that changed what the rows read, in
    /// which case the table asks for its content again.
    func showRelations(of columns: [ItemTableColumn]) -> Bool {
        let shown = Set(columns.compactMap(\.relation))
        guard shown != shownRelations else { return false }
        shownRelations = shown
        return true
    }

    /// The list a search that has not yet answered replaced, for the answer to be compared with.
    @ObservationIgnored var listBeforePendingSearch: [ItemID]?

    /// Whether the window still shows `library`, which a long task checks after each wait, since the person may have
    /// changed library meanwhile.
    func isShowing(_ library: any ItemLibrary) -> Bool { libraryID == ObjectIdentifier(library) }

    /// Starts the window afresh for a library other than the one it showed, the first time it is shown one: what
    /// it selected or searched named items the new library may not have, and the window's undo
    /// would act on the library left. A new item awaited there will not come. Quick add's draft has already gone to
    /// the clipboard, as the window's view of the library left went (`QuickAdd.Departure.libraryChanged`).
    func adopt(_ library: any ItemLibrary, undoManager: UndoManager? = nil) {
        let id = ObjectIdentifier(library)
        if let undoManager { self.undoManager = undoManager }
        guard libraryID != id else { return }
        self.library = library
        let isFirst = libraryID == nil
        libraryID = id
        pagingState = nil
        itemIndex.reset()
        itemToScrollTo = nil
        tableMemo = nil
        sectionsMemo = nil
        viewModesMemo = nil
        fieldsMemo = nil
        paletteMemo = nil
        guard !isFirst else { return }
        dismissQuickLook()
        undoManager?.removeAllActions()
        tableOptions = [:]
        viewSeeds = [:]
        deletingView = nil
        viewPanel?.handOff(because: .libraryChanged)
        viewPanel = nil
        observedChoices = [:]
        filterRowChoice = [:]
        toldUnkept = [:]
        replacedGroups = [:]
        writingViews = []
        pendingViewWrites = []
        placeCards = [:]
        placeHidesEmptyGroups = [:]
        placeProperties = [:]
        placeCalendarScales = [:]
        calendarDay = nil
        showsCalendarMonth = false
        compactBoards = [:]
        timelineFields = [:]
        selection = []
        history = SelectionHistory()
        isCollectionItemPresented = false
        showing = .library
        sidebarShowsAllTypes = false
        customizesSidebar = false
        sidebarTab = nil
        sidebarMemory.forget()
        listMemory.forget()
        searchText = ""
        searchesPlace = false
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

    // MARK: Saved views

    /// The view the window asks the person to confirm deleting.
    var deletingView: ItemID?

    /// The right sidebar's panel for editing a view, while it is open (`Browser+ViewPanel`). It holds the name typed,
    /// of a new view or a rename, until the server takes it, so a window that closes or changes library can give it back.
    var viewPanel: ViewPanel?

    /// Views this window is deleting, whose absence from the library is its own doing and not news from elsewhere.
    @ObservationIgnored var viewsBeingDeleted: Set<ItemID> = []

    /// The window's undo manager, which takes back a change of a view's or a place's choices (`Browser+ViewWrites`).
    @ObservationIgnored var undoManager: UndoManager?

    /// The library the window shows, which a change undone is written to.
    @ObservationIgnored var library: (any ItemLibrary)?

    /// What each place's choices were when last looked at, so a change of them is the person's (`Browser+ViewWrites`).
    @ObservationIgnored var observedChoices: [PlaceView: ViewChoices] = [:]

    /// The views this window is writing, and those that changed again meanwhile (`Browser+ViewWrites`).
    @ObservationIgnored var writingViews: Set<ItemID> = []
    @ObservationIgnored var rewritingViews: Set<ItemID> = []
    /// Name writes and other work waiting for the write under way on a view to end (`lockView`).
    @ObservationIgnored var viewWaiters: [ItemID: [CheckedContinuation<Void, Never>]] = [:]
    /// Views whose choices changed while the window showed another place, written when it shows them again.
    @ObservationIgnored var pendingViewWrites: Set<ItemID> = []
    @ObservationIgnored var toldOffline: Set<ItemID> = []
    @ObservationIgnored var toldUnkept: [ItemID: Set<ViewDraft.Unkept>] = [:]
    /// Each view's groups this window replaced, by field, so grouping by that field again (an Undo, or a choice made
    /// back) gives back the groups another app ordered and hid there.
    @ObservationIgnored var replacedGroups: [ItemID: [String: LibraryViewGroup]] = [:]

    /// Whether the row of filters above the list shows in a place the person chose, which is window state and never
    /// saved (`Browser+FilterRow`). A place the person did not choose for shows it by what it holds.
    var filterRowChoice: [PlaceView: Bool] = [:]

    /// Whether Add Filter… asked for its panel, which the row opens and then clears (`Browser+FilterRow`).
    var isAddFilterRequested = false

    /// Whether the index page has scrolled its title and tabs out of view, which brings the tabs and their buttons into
    /// the window's toolbar (`Browser+IndexPage`). The page reports it; nothing else sets it.
    var isIndexHeaderAway = false

    /// Whether the Items page's Edit popover is out, which puts a minus badge on each tile of the New row.
    var isEditingNewRow = false

    /// The sources the Collections page is narrowed to, by name; empty lists every collection (`Browser+IndexPage`).
    var collectionSourceFilter: Set<String> = []

    /// What the gallery draws on each card in a place that is not a saved view, as its default view keeps it
    /// (`Browser+PlaceDefaults`).
    var placeCards: [PlaceView: ViewCards] = [:]
    /// The scale of each place's calendar that is not a saved view, as its default view keeps it (`calendarScale`).
    var placeCalendarScales: [PlaceView: CalendarScale] = [:]
    /// The places whose default view leaves out the groups with no items.
    var placeHidesEmptyGroups: [PlaceView: Bool] = [:]
    /// The Properties list of each place that is not a saved view, as its default view keeps it (`properties`).
    var placeProperties: [PlaceView: ViewProperties] = [:]
    /// A day in the week or month the calendar shows, or nil for the one that holds today. Kept for the window.
    var calendarDay: Date?
    /// Counts the moves of the calendar by its buttons, menu or keys, so the month card can follow one that leaves the day as it was.
    var calendarMoves = 0
    /// Whether the calendar's month card is open above the corner's buttons. It closes when the layout changes.
    var showsCalendarMonth = false
    /// Counts the asks to scroll the timeline to today (`requestTimelineToday`).
    var timelineTodayRequests = 0

    /// Counts the changes to the densities this Mac keeps for places, which a list reads to know its own changed
    /// (`Browser+SavedViews`).
    var densityRevision = 0

    /// Where this Mac's settings for views are kept. Under the unit tests each window model keeps them apart, so what
    /// one test leaves in a place's default view never reaches another's.
    @ObservationIgnored var defaults: UserDefaults = Browser.initialDefaults

    /// What `isDefaultViewChanged` last worked out, and the stored data it worked it out from (`Browser+PlaceDefaults`).
    @ObservationIgnored var changedMemo: (place: PlaceView, inputs: [Data?], changed: Bool)?
    @ObservationIgnored var isApplyingLayout = false

    /// The order and grouping each view opened with (`Browser+SavedViews`).
    var viewSeeds: [ItemID: ViewSeed] = [:]
}
