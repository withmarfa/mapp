import Foundation
import Marfa
import Observation

/// What one main window is showing: the sidebar item, the selected items and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var showing: PlaceView? = .library {
        // A new view's words are worked out while the window still shows the place it began on.
        willSet {
            if !(newValue.map { $0.isSame(showing) } ?? (showing == nil)) { viewPanel?.settleHandOffText() }
        }
        // A scroll position belongs to the place and layout it was made in.
        didSet {
            // A saved view that moves to another home is still what the window shows.
            guard !(showing.map { $0.isSame(oldValue) } ?? (oldValue == nil)) else { return }
            modalItem = nil
            listMemory.scrollOffset = nil
            laterPlace = nil
            if openedView.map({ showing?.savedView != $0.id }) == true { openedView = nil }
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
    /// The place a later copy wrote for this window, kept as written until the person goes elsewhere.
    @ObservationIgnored var laterPlace: [String: String]?
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
    /// The column beside a layout that has the page, by the identity it gave itself, or nil. The window's one editor is
    /// then on that page. A column that is shown puts itself here and one that goes, with the layout it stood beside,
    /// takes itself away, so a window on an index or on Version History never reads as one with a page. Only the
    /// column that is named here can clear it, since a layout's column may be replaced by the next one's before it goes.
    private(set) var besideColumnHost: UUID?
    /// Whether the page is in the column beside a layout that spans the window (`showsBesidePage`).
    var showsBesideColumn: Bool { besideColumnHost != nil }

    /// Says whether the column `host` shows the page now. Only a column that shows it, or the one that did, changes the answer.
    func columnBeside(_ host: UUID, isShown: Bool) {
        if isShown {
            if besideColumnHost != host { besideColumnHost = host }
        } else if besideColumnHost == host {
            besideColumnHost = nil
        }
    }
    /// Opens items in windows of their own, which only a view can do. The window wires it where it makes its editor.
    @ObservationIgnored var windowOpener: ((Set<ItemID>) -> Void)?

    /// The layouts the current place can show. Search is left out, so a search with no results keeps the layout.
    /// A type's own place counts the type even while it holds no items. The last answer stands until the library's
    /// membership, the place or its stacking changes, since the window asks on every click and edit.
    func availableViewModes(in library: any ItemLibrary) -> [ItemViewMode] {
        guard library.isLoaded else { return ItemViewMode.allCases }
        let membership = library.membershipRevision
        // A saved view lists what the library reads for it, later, and without a membership change.
        let viewItems = isViewPlace ? placeItems(in: library) : nil
        let emptyViewLayout = viewItems?.isEmpty == true ? shown.savedView.flatMap { macSettings(for: $0).layout } : nil
        let key = ViewModesKey(
            library: ObjectIdentifier(library), membership: membership, place: shown, listing: listing,
            viewItems: viewItems?.map(\.id), emptyViewLayout: emptyViewLayout)
        if let held = viewModesMemo, held.key == key { return held.modes }
        let modes = Cost.measure(.viewModes) {
            var types = Set((viewItems ?? placeItems(in: library)).map(\.type))
            if case .type(let type) = shown.place { types.insert(type) }
            var available = ItemViewMode.available(forTypes: types, catalogue: library.catalogue)
            // A just-created view's items are read asynchronously. It opens in its saved layout while it is empty.
            if let emptyViewLayout, !available.contains(emptyViewLayout) { available.append(emptyViewLayout) }
            return available
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
        let emptyViewLayout: ItemViewMode?
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

    /// A window left on a layout its place cannot show goes back to the list without saying so. Types, Collections and
    /// Sources have no layout, so they leave it as it is for the place that follows to judge.
    func fallBackToListIfUnavailable(in library: any ItemLibrary) {
        guard viewPanel?.isNew != true, !showsPlaceIndex, !availableViewModes(in: library).contains(viewMode) else { return }
        set(layout: .list)
    }
    /// How each place's table is grouped, sorted and filtered, as the person left it. A place that is not a saved view
    /// keeps them in its default view too (`Browser+PlaceDefaults`).
    var tableOptions: PlaceMemory<ItemTableOptions> = [:]
    /// The pages of the table the person has loaded, with what they belong to. Held apart from the table's content,
    /// which a page never makes again, and read as one page once the key has changed (`tablePaging`).
    var pagingState: (key: TablePagingKey, paging: TablePaging)?
    /// Which items the list, the gallery or the timeline draws, with what they belong to (`listDrawn`).
    var listPagingState: (key: TablePagingKey, drawn: ListDrawn)?
    /// The items the listed types may have as a parent, held for the types and what the library holds.
    @ObservationIgnored var parentMemo: (key: ParentKey, options: [SearchOffers.Option])?
    /// The search's offers for the last key they were worked out for (`searchOffers`).
    @ObservationIgnored var offerMemo: (key: OfferKey, offers: [SearchOffer])?
    @ObservationIgnored var tableMemo: (key: TableKey, content: ItemTableContent)?
    /// The last table of each large place, shown while its next is arranged off the main actor (`Browser+PlaceContent`).
    @ObservationIgnored var heldTables: PlaceMemory<(key: TableKey, content: ItemTableContent)> = [:]
    /// The last table of a large search, shown while the next is arranged off the main actor. Apart from `heldTables`, so
    /// a search never drops the Library's table nor shows it for its results.
    @ObservationIgnored var heldSearch: (key: TableKey, content: ItemTableContent)?
    /// The arrangement under way, what it is for, and the token its task ends it by, so a task that was replaced never
    /// ends its successor's record.
    @ObservationIgnored var arranging: (key: TableKey, token: UUID, task: Task<Void, Never>)?
    /// The table last asked for, which an arrangement must be for to land, as `PlaceWork`'s runs must.
    @ObservationIgnored var askedTable: TableKey?
    /// The last arrangement begun, ended or not, which the next waits for.
    @ObservationIgnored var lastArrangement: Task<Void, Never>?
    /// Counts the arrangements that landed, which a view reads through `tableContent(in:)` to draw the new one.
    var tableArrangements = 0
    /// The rows of Types, Collections or Sources, held while what they read stands (`Browser+PlaceIndex`).
    @ObservationIgnored var indexRowsMemo: (key: IndexRowsKey, rows: [IndexRow])?
    /// The list's sections, worked out off the main actor for a large place (`sections(in:order:now:)`).
    @ObservationIgnored var sectionsWork = PlaceWork<SectionsKey, ListArrangement>()
    /// Counts what landed from work off the main actor besides the table, which a layout reads to draw it.
    var placeWorkLanded = 0
    /// How often the window worked a place's table or list out whole, and how often it updated one, which tests read.
    @ObservationIgnored var placeWorkCounts = PlaceWorkCounts()
    /// The board's lanes, the calendar's entries and the timeline's days, worked out off the main actor for a large place (`placed`).
    @ObservationIgnored var boardWork = PlaceWork<PlacingKey<BoardChoice>, BoardLanes>()
    @ObservationIgnored var calendarWork = PlaceWork<PlacingKey<CalendarChoice>, CalendarPlacing>()
    @ObservationIgnored var timelineWork = PlaceWork<PlacingKey<TimelineChoice>, TimelinePlacing>()
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
    var compactBoards: PlaceMemory<Bool> = [:]
    /// The date field each place's timeline shows its items by, where the person chose one. A view's own comes from
    /// its day grouping (`followView`).
    var timelineFields: PlaceMemory<String> = [:]
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
    /// What the search's tokens filter by, joined by AND beside the place's own filters (`Browser+Search`). Like the
    /// text, they belong to the field and are never saved; a change of place clears both.
    var searchTokens: [FilterClause] = []
    /// Where the keyboard should go next, asked for by an action such as New Item or Search Items. Whatever
    /// can take it grants it once, when it is able to, and clears it.
    var focusRequest: Pane?
    /// The palette that is out, if any: ⌘K's commands, or ⇧⌘P's search of every item. One panel is out at a time,
    /// so the palette puts the new item away, keeping its draft.
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

    /// Whether a floating panel, the palette or the new item, is out over the window, which the views beneath it
    /// are sent no pointer exit for.
    var panelIsOut: Bool { palette != nil || (quickAdd.isPresented && quickAdd.draft != nil) || isModalPresented }
    /// The window's new item, in the line or the text form, and what is typed in it.
    let quickAdd = QuickAdd()
    /// Whether the list's search is out as a field, rather than a button beside the View button.
    var isSearchExpanded = false
    /// Counts each request for the list's search, so a field already out takes the keyboard again.
    var searchFocusRequests = 0
    /// The items the window made that it waits for its library to hold (see `NewItem`).
    var newItems: [NewItem] = []
    /// What Quick Look shows for the window, while it is open.
    var quickLook: QuickLookRequest?
    /// Counts Quick Look requests, so a slow one the person has since replaced or closed knows to stop.
    @ObservationIgnored var quickLookGeneration = 0
    /// Where the page puts the caret when it next takes the keyboard for a new item.
    var focusCaret: PageCaret?
    /// What the page writes for the files the new-item form attached to a new item, which it puts at the end of the text
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
    /// Whether the window shows Library › Types, Collections or Sources: a table of places, with no layout.
    var showsPlaceIndex: Bool { !shown.listsItems }
    /// Whether an item's page is what the window shows, as against a collection, an index or Settings. The editor
    /// stays mounted behind the others, so every command that acts on the page asks this first. An item open in the
    /// modal is shown over an index as over any layout.
    var showsPage: Bool { isModalPresented || showsBesideColumn || (!showsCollection && !showsPlaceIndex) }

    /// Shows Settings, at `page` when one is given and where it was left otherwise.
    func showSettings(_ page: SettingsPage? = nil, subpage: SettingsSubpage? = nil) {
        openSettings(page, subpage)
    }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Whether the search lists its results as the library ranked them rather than by a sort. The list starts on
    /// relevance; the other layouts start on their own sorts and use relevance only once it is picked there.
    var ordersByRelevance: Bool {
        isSearching && (relevanceChoice ?? (viewMode == .list))
    }

    /// Picks relevance or one of the sorts for the search under way. Outside a search there is nothing to pick.
    func orderSearch(byRelevance: Bool) {
        if isSearching { relevanceChoice = byRelevance }
    }

    /// Whether the window shows a layout that spans it, rather than the list beside the page.
    var usesCollection: Bool { viewMode.spansWindow }
    var showsCollection: Bool { usesCollection && !isCollectionItemPresented }

    /// Whether the view's options are on offer: the list and the gallery always, the table, board and timeline only
    /// while they are showing, not an item page opened from them, which hides their controls.
    var offersViewOptions: Bool { !isCollectionItemPresented }

    /// Shows the place that lists an item no place on screen does: the Archive for an archived item, the Feed or the
    /// Library by its tier, or for a deleted item Settings > Recently Deleted, the only list that holds it.
    private func showListing(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        guard let place = Self.listing(of: item) else { return showSettings(.recentlyDeleted) }
        show(PlaceView(place), in: library, order: order)
    }

    /// The place that lists an item whatever else does: the Archive, or the Library or the Feed by its tier. None lists a
    /// deleted item.
    nonisolated static func listing(of item: Item) -> Place? {
        switch item.state {
        case .trashed: nil
        case .archived: .archive
        default: item.tier == .feed ? .feed : .library
        }
    }

    func reveal(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        // An item reached from the modal, by a link or the palette, is shown in the modal.
        let staysInModal = isModalPresented
        select(item, in: library, order: order)
        if staysInModal { open([item.id], as: .modal) }
        else if followsCollection { open([item.id], as: wayToFollowInCollection()) }
        else { focusRequest = .list }
    }

    /// Selects `item`, showing the place that lists it when the window's list does not.
    private func select(_ item: Item, in library: any ItemLibrary, order: ItemOrder) {
        if !items(in: library).contains(where: { $0.id == item.id }) {
            showListing(item, in: library, order: order)
        }
        selection = [item.id]
    }

    /// Shows the item a link in the page names, as choosing it in the list does: the window's place, search, undo
    /// and the rest of its state are left as they are unless the item is not in the list, which then shows the place
    /// that lists it (`showListing`). The keyboard stays with the page, as it does when a link is followed anywhere.
    func open(linked item: Item, in library: any ItemLibrary, order: ItemOrder) {
        reveal(item, in: library, order: order)
        if !followsCollection { focusRequest = .page }
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
        let way: ItemOpening = !isModalPresented && itemOpening(defaults: defaults) == .fullPage ? .fullPage : .modal
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
    /// last seen when that place still lists it, and in the Library otherwise; any search is put away to show it.
    func go(_ direction: SelectionHistory.Direction, in library: any ItemLibrary) {
        guard let (index, entry) = history.target(direction, in: library, shown: selection) else { return }
        isMovingThroughHistory = true
        defer { isMovingThroughHistory = false }
        isCollectionItemPresented = false
        modalItem = nil
        if isSearching || hasSearchTokens || !entry.place.isSame(showing) {
            clearSearch()
            showing = entry.place.savedView.map { PlaceView.saved($0, in: library) } ?? entry.place
        }
        if !items(in: library).contains(where: { $0.id == entry.id }) { showing = .library }
        selection = [entry.id]
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
    /// would act on the library left. A new item awaited there will not come. The new item's draft is kept already,
    /// for that library, as the window's view of the library left went (`QuickAdd.leave`).
    func adopt(_ library: any ItemLibrary, undoManager: UndoManager? = nil) {
        let id = ObjectIdentifier(library)
        Browser.open.add(self)
        if let undoManager { self.undoManager = undoManager }
        guard libraryID != id else { return }
        viewPanel?.settleHandOffText()
        self.library = library
        let isFirst = libraryID == nil
        libraryID = id
        pagingState = nil
        listPagingState = nil
        tableMemo = nil
        heldTables = [:]
        heldSearch = nil
        arranging?.task.cancel()
        arranging = nil
        askedTable = nil
        indexRowsMemo = nil
        offerMemo = nil
        parentMemo = nil
        sectionsWork.reset()
        boardWork.reset()
        calendarWork.reset()
        timelineWork.reset()
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
        toldUnkept = [:]
        replacedGroups = [:]
        writingViews = []
        pendingViewWrites = []
        placeCards = [:]
        placeHidesEmptyGroups = [:]
        placeQuickActions = [:]
        placeOpenings = [:]
        placeMaps = [:]
        placeDigests = [:]
        digestDisplay = nil
        openedView = nil
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
        clearSearch()
        palette = nil
        fetchedFile = nil
        giveUpNewItems(because: .windowLeft)
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

    /// The active View popover. It holds a typed name so the window can hand it back if the server has yet to take it.
    var viewPanel: ViewPanel?

    /// The saved view the window shows as it was when the window opened it, which Revert View puts back.
    var openedView: OpenedView?

    struct OpenedView {
        let id: ItemID
        /// The view's choices as the window opened it, for the settings this window has not changed since: another
        /// app's change to one of those moves it, so Revert View never puts back what another app changed.
        var choices: ViewChoices
        var mac: ViewMacSettings
        /// The settings this window changed since it opened the view, and its choices after its last change: Revert
        /// View puts back only those, and only where the view still holds what this window made.
        var changed: Set<ViewChoices.Part> = []
        var mine: ViewChoices?
        /// Each setting as Marfa held it when the window opened the view, whole, with what the app cannot show: Revert
        /// View writes these back, never the window's reading of them.
        var raw: LibraryView
        /// Each setting as Marfa returned it after this Mac last wrote it. Revert View writes a setting back only while
        /// Marfa still holds this (or, unwritten, `raw`), so another app's change, even one the window cannot show, stays.
        var written = LibraryViewChange()
        /// The settings Revert View put back, as `raw` holds them: while the window shows one as it opened, it is
        /// written so, through an Undo and a Redo too (`Browser.viewUpdate`).
        var reverting: LibraryViewChange?
        /// Each of this Mac's settings for the view that this window changed, by its path, as the window last wrote it
        /// (`.null` where it cleared it). Revert View puts one back only while it is still stored so.
        var macWritten: [ViewMacSettings.Path: JSONValue] = [:]

        /// Notes the values a change of this Mac's settings for the view wrote.
        mutating func wrote(from before: ViewMacSettings, to after: ViewMacSettings) {
            let before = before.leaves, after = after.leaves
            for path in Set(before.keys).union(after.keys) where before[path] != after[path] { macWritten[path] = after[path] ?? .null }
        }

        /// Takes the view's choices as read for `parts`, but where they are still this window's own change: a setting
        /// another app changed becomes the opening one, and no longer this window's to put back.
        mutating func follow(_ parts: Set<ViewChoices.Part>, of other: ViewChoices, raw view: LibraryView) {
            let own = mine.map { changed.subtracting(other.parts(differingFrom: $0)) } ?? []
            let taken = parts.subtracting(own)
            choices.take(taken, from: other)
            changed.subtract(taken)
            for setting in Self.settings(of: taken) where Self.parts(of: setting).isDisjoint(with: changed) {
                take(setting, of: view)
            }
        }

        /// Takes a setting of the view as it now stands for the opening one, which this window no longer changed.
        mutating func take(_ setting: PendingViewChanges.Setting, of view: LibraryView) {
            switch setting {
            case .sort: raw.sort = view.sort; written.sort = nil; reverting?.sort = nil
            case .group: raw.group = view.group; written.group = nil; reverting?.group = nil
            case .query: raw.query = view.query; written.query = nil; reverting?.query = nil
            }
        }

        /// Notes what Marfa holds of each setting a write of this Mac's sent.
        mutating func wrote(_ change: LibraryViewChange, returned view: LibraryView) {
            if change.sort != nil { written.sort = view.sort }
            if change.group != nil { written.group = view.group.map { .set($0) } ?? .clear }
            if change.query != nil { written.query = view.query }
        }

        /// Whether Marfa still holds a setting as this Mac last left it, compared as Marfa holds it.
        func holdsWhatItLeft(_ setting: PendingViewChanges.Setting, in view: LibraryView) -> Bool {
            switch setting {
            case .sort: view.sort == (written.sort ?? raw.sort)
            case .group:
                switch written.group {
                case .set(let group): view.group == group
                case .clear: view.group == nil
                case nil: view.group == raw.group
                }
            case .query: view.query == (written.query ?? raw.query)
            }
        }

        /// The opening value of each setting, as a change that writes it back.
        func opening(_ settings: Set<PendingViewChanges.Setting>) -> LibraryViewChange {
            var change = LibraryViewChange()
            if settings.contains(.sort) { change.sort = raw.sort }
            if settings.contains(.group) { change.group = raw.group.map { .set($0) } ?? .clear }
            if settings.contains(.query) { change.query = raw.query }
            return change
        }

        /// The settings of the view that hold these choices: the filters and the listing are both its query.
        static func settings(of parts: Set<ViewChoices.Part>) -> Set<PendingViewChanges.Setting> {
            Set(parts.map { part in
                switch part {
                case .sort: .sort
                case .grouping: .group
                case .filters, .listing: .query
                }
            })
        }

        static func parts(of setting: PendingViewChanges.Setting) -> Set<ViewChoices.Part> {
            switch setting {
            case .sort: [.sort]
            case .group: [.grouping]
            case .query: [.filters, .listing]
            }
        }
    }

    /// Views this window is deleting, whose absence from the library is its own doing and not news from elsewhere.
    @ObservationIgnored var viewsBeingDeleted: Set<ItemID> = []

    /// The window's undo manager, which takes back a change of a view's or a place's choices (`Browser+ViewWrites`).
    @ObservationIgnored var undoManager: UndoManager?

    /// The library the window shows, which a change undone is written to.
    @ObservationIgnored var library: (any ItemLibrary)?

    /// What each place's choices were when last looked at, so a change of them is the person's (`Browser+ViewWrites`).
    @ObservationIgnored var observedChoices: PlaceMemory<ViewChoices> = [:]

    /// The views this window is writing, and those that changed again meanwhile (`Browser+ViewWrites`).
    @ObservationIgnored var writingViews: Set<ItemID> = []
    @ObservationIgnored var rewritingViews: Set<ItemID> = []
    /// Name writes and other work waiting for the write under way on a view to end (`lockView`).
    @ObservationIgnored var viewWaiters: [ItemID: [CheckedContinuation<Void, Never>]] = [:]
    /// Views whose choices changed while the window showed another place, written when it shows them again.
    @ObservationIgnored var pendingViewWrites: Set<ItemID> = []
    /// What names this window's own changes among those kept offline (`PendingViewChanges`).
    @ObservationIgnored let pendingOwner = UUID().uuidString
    /// Views with a change waiting for the server, which their pills say on hover.
    var toldOffline: Set<ItemID> = []
    @ObservationIgnored var toldUnkept: [ItemID: Set<ViewDraft.Unkept>] = [:]
    /// Each view's groups this window replaced, by field, so grouping by that field again (an Undo, or a choice made
    /// back) gives back the groups another app ordered and hid there.
    @ObservationIgnored var replacedGroups: [ItemID: [String: LibraryViewGroup]] = [:]

    /// What the gallery draws on each card in a place that is not a saved view, as its default view keeps it
    /// (`Browser+PlaceDefaults`).
    var placeCards: PlaceMemory<ViewCards> = [:]
    /// The scale of each place's calendar that is not a saved view, as its default view keeps it (`calendarScale`).
    var placeCalendarScales: PlaceMemory<CalendarScale> = [:]
    /// The places whose default view leaves out the groups with no items.
    var placeHidesEmptyGroups: PlaceMemory<Bool> = [:]
    /// Whether each place that is not a saved view offers its rows' quick actions, as its default view keeps it.
    var placeQuickActions: PlaceMemory<Bool> = [:]
    /// Where each place that is not a saved view opens its items, as its default view keeps it; none follows Settings.
    var placeOpenings: PlaceMemory<ItemOpening> = [:]
    /// The map's choices of each place that is not a saved view, as its default view keeps them (`mapChoices`).
    var placeMaps: PlaceMemory<MapChoices> = [:]
    var placeDigests: PlaceMemory<DigestChoices> = [:]
    var digestDisplay: DigestLayout.Display?
    /// The Properties list of each place that is not a saved view, as its default view keeps it (`properties`).
    var placeProperties: PlaceMemory<ViewProperties> = [:]
    /// A day in the week or month the calendar shows, or nil for the one that holds today. Kept for the window.
    var calendarDay: Date?
    /// Counts the moves of the calendar by its buttons, menu or keys, so the month card can follow one that leaves the day as it was.
    var calendarMoves = 0
    /// Whether the calendar's month card is open above the corner's buttons. It closes when the layout changes.
    var showsCalendarMonth = false
    /// Counts the asks to scroll the timeline to today (`requestTimelineToday`).
    var timelineTodayRequests = 0
    /// Counts the asks to fit every marker on the map (`requestMapFit`).
    var mapFitRequests = 0

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
