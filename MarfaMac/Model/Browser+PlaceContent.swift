import Foundation

extension Browser {
    func searchScope(in library: any ItemLibrary) -> SearchScope {
        guard searchesPlace, SearchScope.narrows(shown) else { return .everywhere }
        if let id = shown.savedView { return .view(id) }
        // The search follows what the place lists: its From, its archived items and a type's kinds.
        return ViewDraft.query(for: shown, listing: listing, catalogue: library.catalogue, views: library.views)
            .map(SearchScope.query) ?? .everywhere
    }

    /// What the search finds, or nil while the window is not searching.
    func searchResults(in library: any ItemLibrary) -> SearchResults? {
        isSearching ? library.search(searchText, in: searchScope(in: library)) : nil
    }

    /// The items the list shows: the search results while searching, the place's items otherwise.
    func items(in library: any ItemLibrary) -> [Item] {
        Cost.measure(.items) { searchResults(in: library)?.items ?? placeItems(in: library) }
    }

    /// Whether the open place lists anything, without copying its items.
    /// A search, a saved view's list or the Favorites view is the copy's answer, filters included. No index count
    /// matches it. Chip filters narrow a layout after the list is made. They are not part of what `items(in:)` answered.
    func listsAnything(in library: any ItemLibrary) -> Bool {
        if isSearching || shown.view != .own || listing.archived != .hidden || !listing.includesKinds {
            return !items(in: library).isEmpty
        }
        // The answer follows membership, which is what moves an item into or out of the place, and not a keystroke.
        _ = library.membershipRevision
        return library.count(in: shown.place, scope: listing.scope) > 0
    }

    /// The From, Archived Items and Include Kinds of the open place.
    var listing: PlaceListing { listing(in: shown) }

    /// Whether the window shows the Archive's own list, as against a view or a place's list of archived items.
    var listsArchive: Bool { shown.place == .archive && shown.view == .own }

    /// The title a layout gives the window: the Archive is a page of the Library and keeps its title through a search.
    func pageTitle(in library: any ItemLibrary) -> String {
        if listsArchive { return String(localized: "Library") }
        return isSearching ? String(localized: "Search") : library.name(of: shown)
    }

    /// What `shown` lists besides its filters, as the person or a saved view chose, else the place's own: the Library
    /// lists its tier and the Feed its own; the Favorites view starts on the Library whatever Settings says, and a type,
    /// a collection or a source on Settings' From (`ListScope.defaultScope`). Archived items are hidden and a type
    /// lists its kinds until the person chooses otherwise.
    func listing(in shown: PlaceView) -> PlaceListing {
        let options = tableOptions[shown]
        let scope: ListScope = switch (shown.view, shown.place) {
        case (.favorites, _): options?.scope ?? .library
        case (.saved, _): options?.scope ?? .all
        case (.own, .library): .library
        case (.own, .feed): .feed
        case (.own, .type), (.own, .collection), (.own, .source): options?.scope ?? ListScope.defaultScope(in: defaults)
        case (.own, _): .all
        }
        let archived = shown.place == .archive && shown.view == .own ? .only : options?.archived ?? .hidden
        return PlaceListing(scope: scope, archived: archived, includesKinds: options?.includesKinds ?? true)
    }

    /// Sets the open place's From, through the window's funnel, so it is kept and, in a saved view, written.
    func setScope(_ scope: ListScope) {
        tableOptions[shown, default: ItemTableOptions()].scope = scope
        choicesChanged()
    }

    /// Sets whether the open place lists its archived items.
    func setArchived(_ archived: ArchivedItems) {
        tableOptions[shown, default: ItemTableOptions()].archived = archived
        choicesChanged()
    }

    /// Sets whether the open type lists its kinds.
    func setIncludesKinds(_ includes: Bool) {
        tableOptions[shown, default: ItemTableOptions()].includesKinds = includes
        choicesChanged()
    }

    /// The type whose list can leave out its kinds: the open place when it is a type with kinds.
    func kindsType(in library: any ItemLibrary) -> TypeID? {
        guard shown.view == .own, case .type(let type) = shown.place, !library.catalogue.descendants(of: type).isEmpty else { return nil }
        return type
    }

    /// What the open place lists: a saved view's list, or its preview while the window has changed its filters; the
    /// Library's Favorites; or the place by its From, archived items and kinds.
    func placeItems(in library: any ItemLibrary) -> [Item] {
        if let preview = viewPreview { return library.previewItems(ofView: preview.view, query: preview.query) }
        let listing = listing
        switch shown.view {
        case .saved(let id): return library.items(inView: id)
        case .favorites: return library.favoriteItems(in: listing.scope, archived: listing.archived)
        case .own:
            return library.items(in: shown.place, scope: listing.scope, archived: listing.archived, includingKinds: listing.includesKinds)
        }
    }

    /// The items in the order the window last drew them: the table's rows in the table, else the list's or gallery's
    /// sections, with whatever the place lists after them (a board, a timeline) in its own order.
    func onScreenOrder(in library: any ItemLibrary) -> [ItemID] {
        let drawn = viewMode == .table ? tableMemo?.content.rows.map(\.item.id) : sectionsMemo?.sections.flatMap { $0.items.map(\.id) }
        return (drawn ?? []) + placeItems(in: library).map(\.id)
    }

    /// Whether the list shows its place's own order rather than the chosen sort: a collection lists its members in
    /// the order Marfa keeps for them, until a search lists results instead.
    var keepsPlaceOrder: Bool {
        guard !isSearching, shown.view == .own, case .collection = shown.place else { return false }
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
        guard let options = tableOptions[shown] else { return nil }
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
        guard tableOptions[shown]?.isFiltering == true else { return items(in: library) }
        return tableContent(in: library).kept.map(\.item)
    }

    /// Whether the open place has filters that hide everything it lists.
    func filtersHideEverything(in library: any ItemLibrary) -> Bool {
        guard tableOptions[shown]?.isFiltering == true else { return false }
        let content = tableContent(in: library)
        return content.kept.isEmpty && !content.allRows.isEmpty
    }

    /// Whether the table has been worked out for the window, which a list or a gallery that is neither filtered nor
    /// arranged never does.
    var holdsTableContent: Bool { tableMemo != nil }

    /// What the place's table shows, worked out once and shared by everything that draws the table, its controls or
    /// a command about it, until the items, the place's options or the search change. Reading it does not depend on
    /// the selection, so a selection never makes it again.
    ///
    /// A place of more than `arrangesAlongsideAbove` items, such as a Library of tens of thousands, is not ordered on the
    /// main actor at each change. Its last table stays on screen, also while the window is elsewhere, and the next is
    /// sorted off the main actor (`arrange`). A run of edits is let settle first (`arrangeSettling`); a choice of the
    /// person's or an item gone is arranged at once. The chosen row keeps its place through a re-sort until the person
    /// chooses another, so a sort by Edited does not carry the row they are editing from under them.
    func tableContent(in library: any ItemLibrary) -> ItemTableContent {
        // Read, so whoever asks is told when an arrangement lands.
        _ = tableArrangements
        let keyed = (tableOptions[shown] ?? ItemTableOptions()).settled
        let derived = derivedKey(in: library)
        let key = TableKey(
            derived: derived.key, options: keyed, choices: lookChoices, shownRelations: shownRelations, counts: library.counts.revision,
            hidesEmpty: hidesEmptyGroups, sources: library.sources.infos,
            relativeDay: keyed.filter.relative.isEmpty ? nil : Calendar.current.startOfDay(for: library.now()))
        if let held = tableMemo, held.key == key { return held.content }
        let held = heldTables[shown].flatMap { $0.key.derived.library == key.derived.library ? $0 : nil }
        if let held, arranging?.key == key { return held.content }
        let listed = derived.items ?? items(in: library)
        if let held, listed.count > Self.arrangesAlongsideAbove {
            arrange(key, items: listed, after: held, in: library)
            return held.content
        }
        arranging?.task.cancel()
        arranging = nil
        let content = ItemTableContent(browser: self, library: library, items: listed)
        tableMemo = (key, content)
        if listed.count > Self.arrangesAlongsideAbove { heldTables[shown] = (key, content) }
        return content
    }

    /// Up to this many items a table is worked out in place, so a small place never shows an earlier table first.
    nonisolated static let arrangesAlongsideAbove = 2_000
    /// How long a run of changes to a large place's items is let settle.
    nonisolated static let arrangeSettling = Duration.milliseconds(300)

    /// Makes the table for `key` with its rows sorted off the main actor, and shows it once it is still the one asked for.
    private func arrange(
        _ key: TableKey, items: [Item], after earlier: (key: TableKey, content: ItemTableContent), in library: any ItemLibrary
    ) {
        arranging?.task.cancel()
        let place = shown
        let sameChoices = key.options == earlier.key.options && key.choices == earlier.key.choices
            && key.shownRelations == earlier.key.shownRelations && key.hidesEmpty == earlier.key.hidesEmpty
            && key.relativeDay == earlier.key.relativeDay && key.derived.listing == earlier.key.derived.listing
            && key.derived.ids == earlier.key.derived.ids && key.derived.byRelevance == earlier.key.derived.byRelevance
        // Only the items' own changes settle: a membership change may have taken an item away, which must not stay chosen.
        let settles = sameChoices && key.derived.membership == earlier.key.derived.membership
        let pinned = sameChoices && selection.count == 1 ? selection.first : nil
        let task = Task { [weak self] in
            if settles {
                try? await Task.sleep(for: Browser.arrangeSettling)
                guard !Task.isCancelled else { return }
            }
            guard let self, self.shown == place, self.isShowing(library) else { return }
            let content = ItemTableContent(browser: self, library: library, items: items)
            let kept = content.kept
            let sort = content.sort
            let sorted = await Task.detached(priority: .userInitiated) { ItemTableLayout.sorted(kept, by: sort) }.value
            guard !Task.isCancelled, self.arranging?.key == key, self.shown == place else { return }
            content.rows = Browser.holding(pinned, in: sorted, as: pinned == nil ? nil : earlier.content.rows)
            self.arranging = nil
            self.tableMemo = (key, content)
            self.heldTables[place] = (key, content)
            self.tableArrangements += 1
        }
        arranging = (key, task)
    }

    /// `rows` with the row of `id` where it stood in `earlier`, where both hold it.
    nonisolated static func holding(_ id: ItemID?, in rows: [ItemTableRow], as earlier: [ItemTableRow]?) -> [ItemTableRow] {
        guard let id, let earlier, let was = earlier.firstIndex(where: { $0.id == id }),
              let now = rows.firstIndex(where: { $0.id == id }), was != now else { return rows }
        var moved = rows
        moved.insert(moved.remove(at: now), at: min(was, moved.count))
        return moved
    }

    /// What everything worked out from a place's items depends on: which library and how often it changed, the
    /// place and how the window orders them. The items themselves are listed only where they can change without the
    /// library's revisions doing so, which is a search answering and a saved view's list arriving, and are handed
    /// back so the caller does not list them twice. Reading it observes the library's revisions, so a view that asks
    /// is told of the next change.
    private func derivedKey(in library: any ItemLibrary) -> (key: DerivedKey, items: [Item]?) {
        let listed = isSearching || shown.savedView != nil ? items(in: library) : nil
        let key = DerivedKey(
            library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
            place: shown, listing: listing, ids: listed?.map(\.id), byRelevance: ordersByRelevance,
            keepsPlaceOrder: keepsPlaceOrder, favoritesFirst: !isSearching && !showsOnlyFavorites)
        return (key, listed)
    }

    struct DerivedKey: Equatable {
        let library: ObjectIdentifier
        let content: Int
        let membership: Int
        let place: PlaceView
        let listing: PlaceListing
        let ids: [ItemID]?
        let byRelevance: Bool
        let keepsPlaceOrder: Bool
        let favoritesFirst: Bool
    }

    struct SectionsKey: Equatable {
        let derived: DerivedKey
        let order: ItemOrder
        let day: Date
        let shape: ListShape?
        /// Hide Empty Groups, which only an arranged list's groups read and which is kept apart from the place's options.
        let hidesEmpty: Bool
    }

    struct TableKey: Equatable {
        let derived: DerivedKey
        let options: ItemTableOptions
        let choices: [TypeID: TypeLookChoice]
        let shownRelations: Set<Relation>
        /// A changed or evicted answer invalidates the cached table rows.
        let counts: Int
        let hidesEmpty: Bool
        /// The names the server gave sources, which a row holds from when it was made, so the Source column sorts by them.
        let sources: [String: SourceInfo]
        /// The day a filter relative to the day is worked out for, so the table is made again when it changes.
        let relativeDay: Date?
    }

    private var showsOnlyFavorites: Bool { shown.isFavorites }
}
