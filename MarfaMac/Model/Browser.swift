import Foundation
import Observation

/// What one main window is showing: the sidebar item, the selected items and the search. The window's views
/// and the menu bar's commands share it, so both act on the same selection.
@Observable
final class Browser {
    var sidebarItem: SidebarItem? = .allItems {
        // A scroll position belongs to the place and layout it was made in.
        didSet {
            guard sidebarItem != oldValue else { return }
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
            history.record(selection, in: item)
        }
    }
    /// The items the person chose in this window, for Back and Forward: a click, a key in the list, a link or a
    /// palette jump's destination. The app's own moves (the first item of a place, the next item after a delete
    /// or a search) are left out, except the item the window opens on, so Back can return to it. Kept for the
    /// life of the window, not across launches.
    private(set) var history = SelectionHistory()
    @ObservationIgnored private var isMovingThroughHistory = false
    @ObservationIgnored private var isSelectingAutomatically = false
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
            library: ObjectIdentifier(library), membership: membership, place: item, stacked: stacksType,
            viewItems: isViewPlace ? placeItems(in: library).map(\.id) : nil)
        if let held = viewModesMemo, held.key == key { return held.modes }
        let modes = Cost.measure(.viewModes) {
            var types = Set(placeItems(in: library).map(\.type))
            if case .itemType(let type) = item { types.insert(TypeID(type)) }
            return ItemViewMode.available(forTypes: types, catalogue: library.catalogue)
        }
        viewModesMemo = (key, modes)
        return modes
    }

    private struct ViewModesKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let place: SidebarItem
        let stacked: Bool
        let viewItems: [ItemID]?
    }

    /// Where each item stands in the sort the board's cards follow: the place's sort where the person or the view set
    /// one, else nil, which keeps the cards by title.
    func boardCardOrder(in library: any ItemLibrary) -> [ItemID: Int]? {
        guard tableOptions[item]?.sort?.isEmpty == false else { return nil }
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
        timelineFields[item] = key
    }

    private func fieldsKey(in library: any ItemLibrary) -> (key: FieldsKey, items: [Item]?) {
        let listed = isSearching || isViewPlace ? items(in: library) : nil
        let key = FieldsKey(
            library: ObjectIdentifier(library), membership: library.membershipRevision, place: item, stacked: stacksType,
            ids: listed?.map(\.id))
        return (key, listed)
    }

    private struct FieldsKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let place: SidebarItem
        let stacked: Bool
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
    var tableOptions: [SidebarItem: ItemTableOptions] = [:]
    /// The pages of the table the person has loaded, with what they belong to. Held apart from the table's content,
    /// which a page never makes again, and read as one page once the key has changed (`tablePaging`).
    var pagingState: (key: TablePagingKey, paging: TablePaging)?
    @ObservationIgnored private var tableMemo: (key: TableKey, content: ItemTableContent)?
    @ObservationIgnored private var sectionsMemo: (key: SectionsKey, sections: [ItemSection])?
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
    @ObservationIgnored private var stackableMemo: (key: StackableKey, type: String?)?
    /// Held by `paletteIndex(in:)`.
    @ObservationIgnored var paletteMemo: (key: PaletteIndexKey, index: PaletteIndex)?
    var compactBoards: [SidebarItem: Bool] = [:]
    /// The date field each place's timeline shows its items by, where the person chose one. A view's own comes from
    /// its day grouping (`followView`).
    var timelineFields: [SidebarItem: String] = [:]
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

    var item: SidebarItem { sidebarItem ?? .allItems }
    /// Whether the window shows Items as an index, the table of every item with its right sidebar. Items has no list
    /// column and no layout, so whatever layout the window was last left on is not shown there. An item opened from it
    /// as a full page takes the window until Back.
    var showsItemsIndex: Bool { item == .allItems && !isCollectionItemPresented }
    var showsSidebarIndex: Bool { item == .sources || item == .collections || showsItemsIndex }
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
        isSearching && (relevanceChoice ?? (viewMode == .list || item == .allItems))
    }

    /// Picks relevance or one of the sorts for the search under way. Outside a search there is nothing to pick.
    func orderSearch(byRelevance: Bool) {
        if isSearching { relevanceChoice = byRelevance }
    }

    /// Whether the window shows the gallery or the table, which span it, rather than the list beside the page. Items is
    /// an index, not a layout, so it never does.
    var usesCollection: Bool { viewMode.spansWindow && item != .allItems }
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
            show(.allItems, in: library, order: order)
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
        if self.item == .allItems { revealOnItems(item) }
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
        isMovingThroughHistory = true
        defer { isMovingThroughHistory = false }
        isCollectionItemPresented = false
        modalItem = nil
        if isSearching || sidebarItem != entry.place {
            searchText = ""
            isSearchExpanded = false
            sidebarItem = entry.place
        }
        if !items(in: library).contains(where: { $0.id == entry.id }) { sidebarItem = .allItems }
        selection = [entry.id]
        if self.item == .allItems, let held = library.item(entry.id) { revealOnItems(held) }
        history.move(to: index)
        focusRequest = .list
    }

    func returnToCollection() {
        isCollectionItemPresented = false
        focusRequest = .list
    }

    func searchScope(in library: any ItemLibrary) -> SearchScope {
        guard searchesPlace, SearchScope.narrows(item) else { return .everywhere }
        // A type's place lists its subtypes' items too while it includes them, and the search follows the list.
        if case .itemType(let type) = item, stacksSubtypes(in: library) { return .typeWithSubtypes(TypeID(type)) }
        return .place(item)
    }

    /// What the search finds, or nil while the window is not searching.
    func searchResults(in library: any ItemLibrary) -> SearchResults? {
        isSearching ? library.search(searchText, in: searchScope(in: library)) : nil
    }

    /// The items the list shows: the search results while searching, the sidebar item's items otherwise.
    func items(in library: any ItemLibrary) -> [Item] {
        Cost.measure(.items) { searchResults(in: library)?.items ?? placeItems(in: library) }
    }

    /// The types whose list also shows their subtypes' items, kept in the defaults and mirrored here so the views
    /// that list items follow a change (`IncludedSubtypes`).
    var stackedTypes: Set<String> = []

    /// The type whose list could also show its subtypes: the open place when it is a type that has subtypes holding
    /// items.
    func stackableType(in library: any ItemLibrary) -> String? {
        guard case .itemType(let type) = item else { return nil }
        let key = StackableKey(library: ObjectIdentifier(library), membership: library.membershipRevision, type: type)
        if let held = stackableMemo, held.key == key { return held.type }
        let stackable = library.subtypesHoldingItems(of: type).isEmpty ? nil : type
        stackableMemo = (key, stackable)
        return stackable
    }

    private struct StackableKey: Equatable {
        let library: ObjectIdentifier
        let membership: Int
        let type: String
    }

    /// Whether the open place lists its subtypes' items with its own.
    func stacksSubtypes(in library: any ItemLibrary) -> Bool {
        stackableType(in: library).map(stackedTypes.contains) ?? false
    }

    /// What the open place lists. A type lists its own items, and its subtypes' too while it is stacked.
    func placeItems(in library: any ItemLibrary) -> [Item] {
        if let preview = viewPreview { return library.previewItems(ofView: preview.view, query: preview.query) }
        guard stacksSubtypes(in: library), case .itemType(let type) = item else { return library.items(in: item) }
        return library.items(inTypeAndSubtypes: type)
    }

    /// The items in the order the window last drew them: the table's rows in the table, else the list's or gallery's
    /// sections, with whatever the place lists after them (a board, a timeline) in its own order.
    func onScreenOrder(in library: any ItemLibrary) -> [ItemID] {
        let drawn = viewMode == .table ? tableMemo?.content.rows.map(\.item.id) : sectionsMemo?.sections.flatMap { $0.items.map(\.id) }
        return (drawn ?? []) + placeItems(in: library).map(\.id)
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
    /// item is one, nor in search results. A place that keeps its own order, and a search ordered by relevance, are
    /// one section, in the order given. The filters apply, and a sort or group the person set, or a saved view
    /// has, orders and groups the items in place of the list's own order. The window's views ask for them as often
    /// as they are drawn, so the last answer stands until the items, the order, the filters, Hide Empty Groups, the day
    /// or the place change.
    func sections(in library: any ItemLibrary, order: ItemOrder, now: Date) -> [ItemSection] {
        let derived = derivedKey(in: library)
        let shape = listShape
        let key = SectionsKey(
            derived: derived.key, order: order, day: Calendar.current.startOfDay(for: now), shape: shape,
            hidesEmpty: shape != nil && hidesEmptyGroups)
        if let held = sectionsMemo, held.key == key { return held.sections }
        let sections = Cost.measure(.sections) {
            if let shape { return shapedSections(shape, in: library, order: order, now: now) }
            return sectionsUnmeasured(of: derived.items ?? items(in: library), order: order, now: now)
        }
        sectionsMemo = (key, sections)
        return sections
    }

    private func sectionsUnmeasured(of items: [Item], order: ItemOrder, now: Date) -> [ItemSection] {
        if keepsPlaceOrder || ordersByRelevance {
            return items.isEmpty ? [] : [ItemSection(group: nil, items: items)]
        }
        return ItemGroup.sections(
            of: items,
            sort: order.sort,
            favoritesFirst: !isSearching && !showsOnlyFavorites,
            groupsByDate: order.groupsByDate,
            now: now
        )
    }

    /// What the list's sections depend on besides the items: the filters, and the sort and grouping where they are
    /// set. Nil where the place is neither filtered nor arranged, so the table's other choices (a folded group, a
    /// page) never make the sections again.
    struct ListShape: Equatable {
        var options: ItemTableOptions
        /// Whether the table's sort and grouping order the list.
        var arranged: Bool
    }

    var listShape: ListShape? {
        guard let options = tableOptions[item] else { return nil }
        var grouped = false
        if options.grouping.columnID != nil { grouped = true }
        let arranged = options.sort != nil || grouped
        guard arranged || options.isFiltering else { return nil }
        var shape = options.settled
        if !arranged {
            shape.collapsed = nil
            shape.sort = nil
            shape.grouping = .automatic
        }
        return ListShape(options: shape, arranged: arranged)
    }

    /// The sections of a place that is filtered or arranged, worked out from the table's content, which the table
    /// shares and a click on another item never makes again.
    private func shapedSections(_ shape: ListShape, in library: any ItemLibrary, order: ItemOrder, now: Date) -> [ItemSection] {
        let content = tableContent(in: library)
        guard shape.arranged, !ordersByRelevance else {
            return sectionsUnmeasured(of: content.kept.map(\.item), order: order, now: now)
        }
        // The table groups a place by status on its own; the list does only what a view or the person asked for.
        guard shape.options.grouping.columnID != nil, let column = content.grouping else {
            return content.rows.isEmpty ? [] : [ItemSection(group: nil, items: content.rows.map(\.item))]
        }
        let collapsed = content.collapsed
        // An item's own date by day reads in a list as the list's sections always have: Today, Yesterday, Previous 7
        // Days, Previous 30 Days, then months and years.
        if content.groupMode == .bucket(.day), [ItemTableColumn.created.id, ItemTableColumn.edited.id, ItemTableColumn.occurred.id].contains(column.id) {
            var sections: [ItemSection] = []
            for row in content.groups.flatMap(\.rows) {
                let group = column.date(of: row, calendar: .current).map { ItemGroup.group(for: $0, now: now) }
                if let last = sections.last, last.group == group {
                    sections[sections.count - 1].items.append(row.item)
                } else {
                    sections.append(ItemSection(group: group, items: [row.item]))
                }
            }
            return sections.map { section in
                var section = section
                section.isCollapsed = section.group.map { collapsed.contains($0.key) } ?? false
                return section
            }
        }
        return content.groups.map {
            ItemSection(group: .custom(id: $0.id, title: $0.title), items: $0.rows.map(\.item), isCollapsed: collapsed.contains($0.id))
        }
    }

    /// The items the open place shows in the layouts that arrange them themselves (the board, the timeline): the
    /// place's items, less those the filters hide. `items(in:)` stays whole, for whatever needs every item.
    func filteredItems(in library: any ItemLibrary) -> [Item] {
        guard tableOptions[item]?.isFiltering == true else { return items(in: library) }
        return tableContent(in: library).kept.map(\.item)
    }

    /// Whether the open place has filters that hide everything it lists.
    func filtersHideEverything(in library: any ItemLibrary) -> Bool {
        guard tableOptions[item]?.isFiltering == true else { return false }
        let content = tableContent(in: library)
        return content.kept.isEmpty && !content.allRows.isEmpty
    }

    /// Whether the table has been worked out for the window, which a list or a gallery that is neither filtered nor
    /// arranged never does.
    var holdsTableContent: Bool { tableMemo != nil }

    /// What the place's table shows, worked out once and shared by everything that draws the table, its controls or
    /// a command about it, until the items, the place's options or the search change. Reading it does not depend on
    /// the selection, so a selection never makes it again.
    func tableContent(in library: any ItemLibrary) -> ItemTableContent {
        let keyed = (tableOptions[item] ?? ItemTableOptions()).settled
        let derived = derivedKey(in: library)
        let key = TableKey(
            derived: derived.key, options: keyed, choices: lookChoices, shownRelations: shownRelations, counts: library.counts.revision,
            hidesEmpty: hidesEmptyGroups,
            relativeDay: keyed.filter.relative.isEmpty ? nil : Calendar.current.startOfDay(for: library.now()))
        if let held = tableMemo, held.key == key { return held.content }
        let content = ItemTableContent(browser: self, library: library, items: derived.items ?? items(in: library))
        tableMemo = (key, content)
        return content
    }

    /// What everything worked out from a place's items depends on: which library and how often it changed, the
    /// place and how the window orders them. The items themselves are listed only where they can change without the
    /// library's revisions doing so, which is a search answering and a saved view's list arriving, and are handed
    /// back so the caller does not list them twice. Reading it observes the library's revisions, so a view that asks
    /// is told of the next change.
    private func derivedKey(in library: any ItemLibrary) -> (key: DerivedKey, items: [Item]?) {
        let listed = isSearching || isViewPlace ? items(in: library) : nil
        let key = DerivedKey(
            library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
            place: item, stacked: stacksType, ids: listed?.map(\.id), byRelevance: ordersByRelevance,
            keepsPlaceOrder: keepsPlaceOrder, favoritesFirst: !isSearching && !showsOnlyFavorites)
        return (key, listed)
    }

    /// Whether the open place is a saved view, whose sort and group the list and the gallery take.
    var isViewPlace: Bool {
        if case .view = item { true } else { false }
    }

    /// Whether the open place is a type the person has stacked, which lists its subtypes' items too.
    private var stacksType: Bool {
        if case .itemType(let type) = item { stackedTypes.contains(type) } else { false }
    }

    private struct DerivedKey: Equatable {
        let library: ObjectIdentifier
        let content: Int
        let membership: Int
        let place: SidebarItem
        let stacked: Bool
        let ids: [ItemID]?
        let byRelevance: Bool
        let keepsPlaceOrder: Bool
        let favoritesFirst: Bool
    }

    private struct SectionsKey: Equatable {
        let derived: DerivedKey
        let order: ItemOrder
        let day: Date
        let shape: ListShape?
        /// Hide Empty Groups, which only an arranged list's groups read and which is kept apart from the place's options.
        let hidesEmpty: Bool
    }

    private struct TableKey: Equatable {
        let derived: DerivedKey
        let options: ItemTableOptions
        let choices: [TypeID: TypeLookChoice]
        let shownRelations: Set<Relation>
        /// A changed or evicted answer invalidates the cached table rows.
        let counts: Int
        let hidesEmpty: Bool
        /// The day a filter relative to the day is worked out for, so the table is made again when it changes.
        let relativeDay: Date?
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

    private var showsOnlyFavorites: Bool {
        if case .favoriteItem = item { return true }
        return item == .favorites
    }

    /// Shows a sidebar item as a person picks it in the sidebar, the menus or the palette: any search is cleared and the
    /// list's first item is selected, where the place is not an index, which chooses nothing until the person does.
    func show(_ item: SidebarItem, in library: any ItemLibrary, order: ItemOrder) {
        let interval = Telemetry.begin(.navigation, "place.choose")
        defer { interval.end() }
        isCollectionItemPresented = false
        modalItem = nil
        searchText = ""
        isSearchExpanded = false
        sidebarItem = item
        fallBackToListIfUnavailable(in: library)
        selectFirstItem(in: library, order: order)
    }

    func selectFirstItem(in library: any ItemLibrary, order: ItemOrder) {
        // An index chooses nothing until the person does, and ordering every item for a first one would hold the window.
        guard !showsSidebarIndex else { return selectAutomatically([]) }
        let first = sections(in: library, order: order, now: library.now()).first?.items.first
        selectAutomatically(first.map { [$0.id] } ?? [])
    }

    /// Moves the selection as the app does, not as the person chose, so Back does not stop there.
    func selectAutomatically(_ ids: Set<ItemID>) {
        isSelectingAutomatically = true
        defer { isSelectingAutomatically = false }
        selection = ids
    }

    /// Whether the selection follows the items the window's layout holds as they change: a layout that spans the window
    /// has no list to do it, and nor has a full page opened from the list, which takes the list's place.
    var followsCollection: Bool { usesCollection || isCollectionItemPresented }

    /// Keeps the selection true as the items the window holds change (`collectionItemIDs`), while it follows them.
    func collectionItemsChanged(from old: [ItemID], to new: [ItemID]) {
        guard followsCollection else { return }
        keepSelection(from: old, to: new)
    }

    /// The items the layout that spans the window holds, which its selection follows as they change (`keepSelection`):
    /// the table's in the order it shows them, then those its filters hide, and the gallery's, the board's and the
    /// timeline's in the list's order, which is also the order of a full page opened from the list. The table's come from
    /// its own content, so a move between its places sorts no list. Items' are its table's (`itemIndexIDs`).
    func collectionItemIDs(in library: any ItemLibrary, order: ItemOrder) -> [ItemID] {
        guard followsCollection else { return [] }
        // Items has no layout: a full page opened from it follows the rows of its table.
        if item == .allItems { return itemIndexIDs(in: library) }
        guard !showsSidebarIndex else { return [] }
        guard viewMode == .table else {
            let shown = sections(in: library, order: order, now: library.now()).flatMap { $0.items.map(\.id) }
            // The items the filters and the hidden groups leave out stay in the selection's reach, as the table's do.
            let rest: [ItemID]
            if listShape?.arranged == true, !ordersByRelevance {
                rest = tableContent(in: library).allRows.map(\.id)
            } else if tableOptions[item]?.isFiltering == true {
                rest = items(in: library).map(\.id)
            } else {
                return shown
            }
            let isShown = Set(shown)
            return shown + rest.filter { !isShown.contains($0) }
        }
        let content = tableContent(in: library)
        // A grouped table shows its rows group by group, not in the sort's order across groups.
        let shown = (content.grouping == nil ? content.rows : content.groups.flatMap(\.rows)).map(\.id)
        let isShown = Set(shown)
        return shown + content.allRows.map(\.id).filter { !isShown.contains($0) }
    }

    /// Keeps the selection in the list after items leave it or the search changes it (see `selection(_:keptFrom:in:)`).
    ///
    /// A search not yet answered shows nothing, which says nothing about the selection: it is held, and the answer is
    /// compared with the list as it stood before the search.
    func keepSelection(from old: [ItemID], to new: [ItemID], isPending: Bool = false) {
        if isPending {
            listBeforePendingSearch = listBeforePendingSearch ?? old
            return
        }
        let before = listBeforePendingSearch ?? old
        listBeforePendingSearch = nil
        let kept = Self.selection(selection, keptFrom: before, in: new)
        if kept != selection { selectAutomatically(kept) }
    }

    /// Compares the answer of a search with the list before it, when the answer arrives without changing the list,
    /// as one that finds nothing does after a list that showed nothing while it waited.
    func keepHeldSelection(in list: [ItemID]) {
        guard listBeforePendingSearch != nil else { return }
        keepSelection(from: list, to: list)
    }

    /// The list a search that has not yet answered replaced, for the answer to be compared with.
    @ObservationIgnored private var listBeforePendingSearch: [ItemID]?

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
        stackableMemo = nil
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
        sidebarItem = .allItems
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

    /// Moves the live items among `ids` to Recently Deleted, which undoes; more than one is handed to `confirm`
    /// where there is one, which asks the person first and then moves them. A selection with a live item in it never
    /// erases anything: the items already in Recently Deleted stay there, since erasing cannot be undone and a
    /// command that also moves other items must not do it. Only a selection made entirely of items already there
    /// asks to erase them for good, and only where the library can; otherwise the person is told why not.
    static func delete(
        _ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?, toasts: ToastPresenter? = nil,
        naming title: String? = nil, asking confirm: ((Set<ItemID>) -> Void)? = nil
    ) {
        let binned = Set(ids.filter { library.item($0)?.state == .trashed })
        // Told here, before anything asks the person to confirm items that would be left alone.
        let plan = library.deletePlan(ids.subtracting(binned))
        let moving = plan.moving
        library.tellSkipped(plan.skips, didChange: !moving.isEmpty || !binned.isEmpty, failing: String(localized: "Can’t Delete"))
        if !moving.isEmpty {
            if moving.count > 1, let confirm {
                confirm(moving)
            } else {
                moveToRecentlyDeleted(moving, in: library, undoManager: undoManager, toasts: toasts, naming: title)
            }
        } else if !binned.isEmpty, ids.subtracting(binned).isEmpty {
            if library.reachesServer { library.itemsToPurge = binned } else { library.tellCannotPurge() }
        }
    }

    /// Moves `ids` to Recently Deleted, then says so in the window's toast with an Undo that takes back that move.
    /// The toast's Undo is bound to the step (`StepUndo`), not to its name: any step registered, undone or redone
    /// after it takes the toast away. It is offered only where no undo group was open before the move, since the move
    /// would then share that group and `undo()` would take back the other steps in it too. A manager that does not
    /// group by event has none open, so the move gets a group of its own, closed at once. A `title` names the one item
    /// moved, for an item the library may no longer return once moved.
    static func moveToRecentlyDeleted(
        _ ids: Set<ItemID>, in library: any ItemLibrary, undoManager: UndoManager?, toasts: ToastPresenter?, naming title: String? = nil
    ) {
        let moving = library.deletePlan(ids).moving
        let name = moving.count == 1 ? title ?? moving.first.flatMap { library.item($0)?.name } : nil
        let startsGroup = undoManager?.groupingLevel == 0
        let opensGroup = startsGroup && undoManager?.groupsByEvent == false
        if opensGroup { undoManager?.beginUndoGrouping() }
        library.delete(ids, undoManager: undoManager)
        if opensGroup { undoManager?.endUndoGrouping() }
        guard !moving.isEmpty, let toasts else { return }
        let message = DeletionWords.movedMessage(count: moving.count, title: name)
        guard startsGroup, let undoManager, undoManager.canUndo else {
            toasts.show(message, symbol: "trash")
            return
        }
        let step = StepUndo(undoManager: undoManager)
        let id = toasts.show(message, symbol: "trash", undo: { step.perform() })
        step.onLapse = { [weak toasts] in toasts?.dismiss(ifShowing: id) }
    }

    /// A place that is gone can no longer be shown, so the window moves to where `placeFallback(in:)` says.
    func placeRemoved(in library: any ItemLibrary, order: ItemOrder) {
        if let place = placeFallback(in: library) { show(place, in: library, order: order) }
    }

    /// Where the window should go instead, when the place it shows has gone; nil while the place stands. Reading it
    /// observes what a place's existence depends on (membership and the saved views), so a view that only asks this
    /// is told when the answer may have changed, and reads no list of the library's items to find out.
    func placeFallback(in library: any ItemLibrary) -> SidebarItem? {
        guard library.isLoaded else { return nil }
        switch sidebarItem {
        case .collection(let id):
            // A collection's state is part of membership, which `item(_:)` follows only once the item is missing.
            _ = library.membershipRevision
            return library.item(id)?.state != .active ? .allItems : nil
        // A type is in the sidebar while it holds an item, so one whose last item went has no row to stay on.
        case .itemType(let type):
            return library.count(in: .itemType(type)) == 0 ? .allItems : nil
        case .view(let id):
            return library.views.contains { $0.id == id } ? nil : .allItems
        case .favoriteItem(let id):
            _ = library.membershipRevision
            return library.item(id).map({ $0.state == .active && $0.isFavorite }) == true ? nil : .favorites
        default:
            return nil
        }
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
    @ObservationIgnored var observedChoices: [SidebarItem: ViewChoices] = [:]

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
    var filterRowChoice: [SidebarItem: Bool] = [:]

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
    var placeCards: [SidebarItem: ViewCards] = [:]
    /// The scale of each place's calendar that is not a saved view, as its default view keeps it (`calendarScale`).
    var placeCalendarScales: [SidebarItem: CalendarScale] = [:]
    /// The places whose default view leaves out the groups with no items.
    var placeHidesEmptyGroups: [SidebarItem: Bool] = [:]
    /// The Properties list of each place that is not a saved view, as its default view keeps it (`properties`).
    var placeProperties: [SidebarItem: ViewProperties] = [:]
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

    private static var initialDefaults: UserDefaults {
        #if DEBUG
        if TestHost.isRequested, let suite = UserDefaults(suiteName: "MarfaMac.Browser.\(UUID().uuidString)") { return suite }
        #endif
        return .standard
    }
    /// What `isDefaultViewChanged` last worked out, and the stored data it worked it out from (`Browser+PlaceDefaults`).
    @ObservationIgnored var changedMemo: (place: SidebarItem, inputs: [Data?], changed: Bool)?
    @ObservationIgnored var isApplyingLayout = false

    /// The order and grouping each view opened with (`Browser+SavedViews`).
    var viewSeeds: [ItemID: ViewSeed] = [:]

    // MARK: Keeping the selection in the list

    /// When selected items leave the list (deleted, moved elsewhere, filtered out by a search), the selection
    /// keeps whichever are still there. If none are, it moves to the item that followed them, or failing that
    /// the one before, as Notes and Mail do.
    static func selection(_ selection: Set<ItemID>, keptFrom old: [ItemID], in new: [ItemID]) -> Set<ItemID> {
        let visible = Set(new)
        let kept = selection.intersection(visible)
        guard kept.isEmpty, let first = old.firstIndex(where: selection.contains) else { return kept }
        let candidates = old[first...].dropFirst() + old[..<first].reversed()
        return candidates.first { visible.contains($0) && !selection.contains($0) }.map { [$0] } ?? []
    }
}
