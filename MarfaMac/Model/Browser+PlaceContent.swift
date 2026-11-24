import Foundation

extension Browser {
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

    /// Whether the open place lists anything, without copying its items.
    /// A search, or a saved view's list, is the copy's answer, filters included. No index count matches it.
    /// Chip filters narrow a layout after the list is made. They are not part of what `items(in:)` answered.
    func listsAnything(in library: any ItemLibrary) -> Bool {
        if isSearching || isViewPlace {
            return !items(in: library).isEmpty
        }
        // Include Subtypes lists a subtype's items. This is true only when one of those subtypes holds an item,
        // so the place lists something even when the type itself does not.
        if stacksSubtypes(in: library) { return true }
        // Recents' count does not read `membershipRevision` itself. The rest do. Either way the answer follows
        // membership, which is what moves an item into or out of the place, and not a keystroke.
        _ = library.membershipRevision
        return library.count(in: item) > 0
    }

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

    struct StackableKey: Equatable {
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

    /// Whether the open place is a type the person has stacked, which lists its subtypes' items too.
    var stacksType: Bool {
        if case .itemType(let type) = item { stackedTypes.contains(type) } else { false }
    }

    struct DerivedKey: Equatable {
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
        /// The day a filter relative to the day is worked out for, so the table is made again when it changes.
        let relativeDay: Date?
    }

    private var showsOnlyFavorites: Bool {
        if case .favoriteItem = item { return true }
        return item == .favorites
    }
}
