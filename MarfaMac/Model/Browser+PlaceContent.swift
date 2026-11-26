import Foundation

extension Browser {
    /// Where the text search looks: what the place lists with the window's choices, which a place that lists items
    /// answers whatever the list's filters hold (the search runs within them), narrowed by the tokens that Marfa can say.
    /// A place that lists no items, such as an index, has the whole library.
    func searchScope(in library: any ItemLibrary) -> SearchScope {
        guard SearchScope.narrows(shown) else { return .everywhere }
        if let id = shown.savedView, !hasSearchTokens { return .view(id) }
        // The search follows what the place lists: its From, its archived items and a type's kinds.
        guard var query = ViewDraft.query(for: shown, listing: listing, catalogue: library.catalogue, views: library.views) else {
            return .everywhere
        }
        if hasSearchTokens {
            // Each token Marfa can say narrows the search itself, so the most it lists is counted after them; the rest are
            // applied to what it lists (`ItemTableContent.kept`), which is the only place every token is applied. A Type
            // token only narrows within the place's types, never lists others.
            query = ViewDraft.adding(
                FilterState(clauses: narrowingSearchTokens), to: query, targets: tokenTargets(in: library), catalogue: library.catalogue,
                replacingTypes: false).query
        }
        return .query(query)
    }

    /// What the search finds, or nil while the window is not searching.
    func searchResults(in library: any ItemLibrary) -> SearchResults? {
        isSearching ? library.search(searchText, in: searchScope(in: library)) : nil
    }

    /// The items the list shows: the search results while searching, the place's items otherwise.
    func items(in library: any ItemLibrary) -> [Item] {
        if previewsNothing { return [] }
        return Cost.measure(.items) { searchResults(in: library)?.items ?? placeItems(in: library) }
    }

    /// Whether the window previews a new view that lists nothing: an inbox whose every source the person unticked.
    var previewsNothing: Bool { viewPanel?.choosesNoSource == true }

    /// Whether the open place lists anything, without copying its items.
    /// A search, a saved view's list or the Favorites view is the copy's answer, filters included. No index count
    /// matches it. Chip filters narrow a layout after the list is made. They are not part of what `items(in:)` answered.
    func listsAnything(in library: any ItemLibrary) -> Bool {
        if previewsNothing { return false }
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

    /// Whether the window shows a list of items by what they are and where they came from: the Archive's own list, and the
    /// Library's, whose default view is the name, type, source and edit date, latest first.
    var listsByOrigin: Bool { (shown.place == .archive || shown.place == .library) && shown.view == .own }

    /// The title a layout gives the window: the Archive is a page of the Library and keeps its title through a search.
    func pageTitle(in library: any ItemLibrary) -> String {
        listsArchive ? String(localized: "Library") : library.name(of: shown)
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
        if viewMode == .digest { return digestOrder }
        let drawn = viewMode == .table ? tableMemo?.content.rows.map(\.item.id) : sectionsWork.held?.value.ids
        return (drawn ?? []) + placeItems(in: library).map(\.id)
    }

    /// Whether the list shows its place's own order rather than the chosen sort: a collection lists its members in
    /// the order Marfa keeps for them, until a search lists results instead.
    var keepsPlaceOrder: Bool {
        guard !isSearching, shown.view == .own, case .collection = shown.place else { return false }
        return true
    }

    /// The list's sections, which the list and the gallery draw: the one way to read what a place lists, in order and
    /// grouped. Favorites lead wherever they mean something: not in Favorites itself, where every item is one, nor in
    /// search results. A place that keeps its own order, and a search ordered by relevance, are one section, in the order
    /// given. The filters apply, and a sort or group the person set, or a saved view has, orders and groups the items in
    /// place of the list's own order, as the table does (`tableContent(in:)`). The last answer stands until the items, the
    /// order, the filters, Hide Empty Groups, the day or the place change.
    ///
    /// A place of more than `arrangesAlongsideAbove` items is worked out off the main actor (`PlaceWork`), its last
    /// sections showing meanwhile, and a change of items re-places only the items that changed.
    func sections(in library: any ItemLibrary, order: ItemOrder, now: Date) -> [ItemSection] {
        arrangement(in: library, order: order, now: now).sections
    }

    /// The list's sections with what a layout reads of them, worked out with them (`sections(in:order:now:)`).
    func arrangement(in library: any ItemLibrary, order: ItemOrder, now: Date) -> ListArrangement {
        listArrangement(in: library, order: order, now: now, work: sectionsWork)
    }

    func digestArrangement(in library: any ItemLibrary, now: Date) -> DigestLayout.Display? {
        listArrangement(in: library, order: DigestLayout.order, now: now, work: digestWork, stacking: digestChoices.stacks).digest
    }

    private func listArrangement(
        in library: any ItemLibrary, order: ItemOrder, now: Date, work: PlaceWork<SectionsKey, ListArrangement>, stacking: Bool? = nil
    ) -> ListArrangement {
        _ = placeWorkLanded
        let derived = derivedKey(in: library)
        let shape = listShape
        let choices = SectionsChoices(
            derived: derived.key, order: order, clock: ClockDay(now: now, calendar: library.calendar()), shape: shape,
            hidesEmpty: shape != nil && hidesEmptyGroups, digestStacking: stacking,
            expanded: viewMode == .list && stacking == nil ? expandedHere : nil)
        let shown = work.held.flatMap { $0.key.choices.derived.isSamePlace(as: derived.key) ? $0.value : nil }
        // A filtered or arranged place takes its rows, order and groups from the table.
        let content: ItemTableContent?
        if shape == nil {
            content = nil
        } else if let table = requestTable(in: library, deferringFirstArrangement: stacking != nil) {
            content = table
        } else {
            _ = work.value(for: SectionsKey(choices: choices, table: nil, content: nil))
            return shown ?? .empty
        }
        let key = SectionsKey(choices: choices, table: content?.serial, content: content == nil ? library.contentRevision : nil)
        if let held = work.value(for: key) { return held }
        // A list of the place's own items that no change touched stands as it is, sub-items it hides included.
        if content == nil, let held = work.held, held.key.choices == choices, let since = held.value.content,
           let changed = library.changedItems(since: since),
           (derived.items ?? items(in: library)).count == held.value.ids.count + held.value.nestedAway.count,
           !changed.contains(where: { held.value.positions[$0] != nil || held.value.nestedAway.contains($0) }) {
            let kept = held.value.at(library.contentRevision)
            work.hold(kept, for: key)
            return kept
        }
        let earlier = content == nil ? work.held.flatMap { $0.key.choices == choices && $0.value.content != nil ? $0.value : nil } : nil
        let making = sectionsMaking(content, items: derived.items, in: library, now: now, choices: choices, earlier: earlier)
        if case .list(_, let earlier, _, _) = making.source, !making.ordersItself {
            if earlier == nil { placeWorkCounts.listsSorted += 1 } else { placeWorkCounts.listsUpdated += 1 }
        }
        let count = content?.allRows.count ?? making.count
        let place = self.shown
        let expanded = choices.expanded
        let make: @Sendable () -> ListArrangement = {
            var arrangement = making.make()
            if let expanded { arrangement = arrangement.nested(expanded: expanded) }
            if let stacking {
                arrangement.digest = DigestLayout.Display(place: place, sections: DigestLayout.sections(arrangement.sections, stacking: stacking))
            }
            return arrangement
        }
        guard count > Self.arrangesAlongsideAbove, shown != nil || stacking != nil else {
            let made = Cost.measure(.sections, make)
            work.hold(made, for: key)
            return made
        }
        let settles = work.held?.key.choices == choices
        work.start(key, settling: settles ? Self.arrangeSettling : nil, {
            Cost.measure(.sectionsArranged, make)
        }, landed: { [weak self] in self?.placeWorkLanded += 1 })
        return shown ?? .empty
    }

    /// What the sections are made of, read on the main actor: the table's rows where it arranges the place, else what the
    /// list orders, with the sections last made for the same choices, which it re-places the changed items in.
    private func sectionsMaking(
        _ content: ItemTableContent?, items: [Item]?, in library: any ItemLibrary, now: Date, choices: SectionsChoices, earlier: ListArrangement?
    ) -> ListSections {
        let ordersItself = keepsPlaceOrder || ordersByRelevance
        let favoritesFirst = choices.digestStacking == nil && !isSearching && !showsOnlyFavorites
        if let content, choices.shape?.arranged == true, !ordersByRelevance {
            return ListSections(
                source: .table(TableSections(
                    rows: content.rows, groups: content.groups, kept: content.keptItems, grouping: content.grouping,
                    groupMode: content.groupMode, collapsed: content.collapsed, groupsByOwnGroup: choices.shape?.options.grouping.columnID != nil)),
                order: choices.order, now: now, ordersItself: ordersItself, favoritesFirst: favoritesFirst)
        }
        let listed = content?.keptItems ?? items ?? self.items(in: library)
        // Only a list of the place's own items follows the library's revisions; the table's rows follow the table.
        let changed = earlier?.content.flatMap { library.changedItems(since: $0) }
        return ListSections(
            source: .list(listed, earlier: changed == nil ? nil : earlier, changed: changed, content: content == nil ? library.contentRevision : nil),
            order: choices.order, now: now, ordersItself: ordersItself, favoritesFirst: favoritesFirst)
    }

    /// What the list's sections depend on besides the items: the filters, and the sort and grouping where they are
    /// set. Nil where the place is neither filtered nor arranged, so the table's other choices (a folded group, a
    /// page) never make the sections again.
    nonisolated struct ListShape: Equatable, Sendable {
        var options: ItemTableOptions
        /// Whether the table's sort and grouping order the list.
        var arranged: Bool
        /// The search's tokens, which narrow the list as the filters do.
        var tokens: [FilterClause] = []
    }

    var listShape: ListShape? {
        let options = tableOptions[shown] ?? ItemTableOptions()
        var grouped = false
        if options.grouping.columnID != nil { grouped = true }
        let arranged = options.sort != nil || grouped
        guard arranged || options.isFiltering || hasSearchTokens else { return nil }
        var shape = options.settled
        if !arranged {
            shape.collapsed = nil
            shape.sort = nil
            shape.grouping = .automatic
        }
        return ListShape(options: shape, arranged: arranged, tokens: narrowingSearchTokens)
    }

    /// The items the open place shows in the layouts that arrange them themselves (the board, the timeline): the
    /// place's items, less those the filters hide. `items(in:)` stays whole, for whatever needs every item.
    func filteredItems(in library: any ItemLibrary) -> [Item] {
        guard tableOptions[shown]?.isFiltering == true || hasSearchTokens else { return items(in: library) }
        return tableContent(in: library).keptItems
    }

    /// What a layout that places the items itself (the board, the calendar, the timeline) works out from them by `choice`:
    /// the place's items, less those the filters hide. A place of more than `arrangesAlongsideAbove` items is worked out
    /// off the main actor, its last answer showing meanwhile, and a run of changes is let settle first. `table`, where the
    /// answer reads it, is the table it was read from, whose next one makes the answer again.
    func placed<Choice: Equatable & Sendable, Value: Sendable>(
        _ work: PlaceWork<PlacingKey<Choice>, Value>, choice: Choice, table: ItemTableContent? = nil, in library: any ItemLibrary,
        make: @escaping @Sendable ([Item]) -> Value
    ) -> Value {
        _ = placeWorkLanded
        let derived = derivedKey(in: library)
        let narrows = tableOptions[shown]?.isFiltering == true || hasSearchTokens
        let content = narrows ? (table ?? tableContent(in: library)) : table
        let key = PlacingKey(
            derived: derived.key, shape: listShape, choice: choice, table: content?.serial,
            content: narrows ? nil : library.contentRevision)
        if let held = work.value(for: key) { return held }
        let items = narrows ? content?.keptItems ?? [] : derived.items ?? self.items(in: library)
        let shown = work.held.flatMap { $0.key.derived.isSamePlace(as: derived.key) ? $0.value : nil }
        guard items.count > Self.arrangesAlongsideAbove, let shown else {
            let value = make(items)
            work.hold(value, for: key)
            return value
        }
        let settles = work.held.map { $0.key.derived == key.derived && $0.key.shape == key.shape && $0.key.choice == key.choice } ?? false
        work.start(key, settling: settles ? Self.arrangeSettling : nil, { make(items) }, landed: { [weak self] in self?.placeWorkLanded += 1 })
        return shown
    }

    /// Whether the open place has filters that hide everything it lists. A search's tokens that do so are the search's
    /// own empty result (`SearchEmptyState`).
    func filtersHideEverything(in library: any ItemLibrary) -> Bool {
        guard tableOptions[shown]?.isFiltering == true, !hasSearchTokens else { return false }
        guard let content = requestTable(in: library, deferringFirstArrangement: viewMode == .digest) else { return false }
        return content.kept.isEmpty && !content.allRows.isEmpty
    }

    /// Whether the table has been worked out for the window, which a list or a gallery that is neither filtered nor
    /// arranged never does.
    var holdsTableContent: Bool { tableMemo != nil }

    /// What the place's table shows, worked out once and shared by everything that draws the table, its controls or
    /// a command about it, until the items, the place's options or the search change. Reading it does not depend on
    /// the selection, so a selection never makes it again.
    ///
    /// A change of items updates the table last made for the same choices: where none of its rows changed and no item
    /// joined, it stands as it is; otherwise only the rows of the items that changed are made again, filtered and merged
    /// into the order of the rest (`ItemTableContent.Update`). Where the library cannot say what changed, the table is made
    /// again. A place of more than `arrangesAlongsideAbove` items, such as a Library of tens of thousands, is never worked
    /// out on the main actor at a change. Its last table stays on screen, the Library's also while the window is elsewhere,
    /// and the next is made off the main actor (`arrange`). A run of edits is let settle first (`arrangeSettling`); a
    /// choice of the person's or an item gone is arranged at once. The chosen row keeps its place through a re-sort until
    /// the person chooses another, so a sort by Edited does not carry the row they are editing from under them.
    func tableContent(in library: any ItemLibrary) -> ItemTableContent {
        // Only requests that defer the first arrangement can return before there is a table.
        requestTable(in: library, deferringFirstArrangement: false)!
    }

    private func requestTable(in library: any ItemLibrary, deferringFirstArrangement: Bool) -> ItemTableContent? {
        // Read, so whoever asks is told when an arrangement lands.
        _ = tableArrangements
        // Not held: the options are those of every source, whose table comes back as it was once one is ticked.
        if previewsNothing {
            askedTable = nil
            return ItemTableContent(browser: self, library: library, items: [])
        }
        let keyed = (tableOptions[shown] ?? ItemTableOptions()).settled
        let derived = derivedKey(in: library)
        let key = TableKey(
            choices: TableChoices(
                derived: derived.key, options: keyed, choices: lookChoices, shownRelations: shownRelations, hidesEmpty: hidesEmptyGroups,
                sources: library.sources.infos,
                clock: ClockDay(now: library.now(), calendar: library.calendar()),
                tokens: narrowingSearchTokens),
            basis: TableBasis(content: library.contentRevision, membership: library.membershipRevision, counts: library.counts.revision))
        askedTable = key
        // Returning to a cached sort supersedes the sort the person just left.
        func isReady(_ content: ItemTableContent) -> Bool {
            !deferringFirstArrangement || content.allRows.count <= Self.arrangesAlongsideAbove || content.hasOrdered
        }
        if let held = tableMemo, held.key == key, isReady(held.content) {
            if arranging.map({ $0.key != key }) == true { endArranging() }
            return held.content
        }
        // A search's table is held apart, so its results never show the Library's table nor drop it.
        let searching = isSearching
        let held = (searching ? heldSearch : heldTables[shown]).flatMap {
            $0.key.choices.derived.isSamePlace(as: key.choices.derived) && isReady($0.content) ? $0 : nil
        }
        // The table the place held is the one asked for again, as when a search ends on the place it began on.
        if let held, held.key == key {
            if arranging.map({ $0.key != key }) == true { endArranging() }
            tableMemo = held
            return held.content
        }
        if arranging?.key == key, held != nil || deferringFirstArrangement { return held?.content }
        let listed = derived.items ?? items(in: library)
        let isLarge = listed.count > Self.arrangesAlongsideAbove
        // The table last made for these choices, which a change of items updates rather than makes again.
        let earlier = [tableMemo, held].compactMap { $0 }.first { $0.key.choices == key.choices && isReady($0.content) }
        let changed = earlier.flatMap { changes(since: $0.key.basis, in: library) }
        if let earlier, let changed, earlier.content.isUntouched(by: changed, listing: listed.count) {
            // Whatever is under way is for another choice or an older revision.
            endArranging()
            take((key, earlier.content), searching: searching, isLarge: isLarge)
            return earlier.content
        }
        if isLarge, held != nil || deferringFirstArrangement {
            let update = earlier.flatMap { earlier in changed.map { (earlier.content, $0) } }
            arrange(key, items: listed, after: held, updating: update, in: library)
            return held?.content
        }
        endArranging()
        let content: ItemTableContent
        if let earlier, let changed,
           let updated = ItemTableContent.updating(earlier.content, browser: self, library: library, items: listed, changed: changed) {
            placeWorkCounts.tablesUpdated += 1
            content = updated
        } else {
            placeWorkCounts.tablesMade += 1
            content = ItemTableContent(browser: self, library: library, items: listed)
        }
        take((key, content), searching: searching, isLarge: isLarge)
        return content
    }

    /// Up to this many items a place is worked out in place, so a small place never shows an earlier table or list first.
    nonisolated static let arrangesAlongsideAbove = 2_000
    /// How long a run of changes to a large place's items is let settle.
    nonisolated static let arrangeSettling = Duration.milliseconds(300)

    /// The items that changed since `basis`, by the library and its counts, or nil where either cannot say.
    private func changes(since basis: TableBasis, in library: any ItemLibrary) -> Set<ItemID>? {
        guard let items = library.changedItems(since: basis.content), let counted = library.counts.changedItems(since: basis.counts)
        else { return nil }
        return items.union(counted)
    }

    /// Makes `table` the window's table, and the held one of its place or search where it is large.
    private func take(_ table: (key: TableKey, content: ItemTableContent), searching: Bool, isLarge: Bool) {
        tableMemo = table
        if searching {
            heldSearch = isLarge ? table : nil
        } else {
            heldSearch = nil
            hold(isLarge ? table : nil, for: shown)
        }
    }

    /// Keeps `table` as the held table of `place`, and forgets every other but the Library's, so a window that has
    /// shown many large places holds two tables at most.
    private func hold(_ table: (key: TableKey, content: ItemTableContent)?, for place: PlaceView) {
        var kept: PlaceMemory<(key: TableKey, content: ItemTableContent)> = [:]
        if !place.isSame(.library) { kept[.library] = heldTables[.library] }
        kept[place] = table
        heldTables = kept
    }

    /// Makes the table for `key` off the main actor, from `update`'s table where one is given, which then makes only the rows
    /// of the items that changed again, and shows it once it is still the one asked for. The main actor only reads the links
    /// of the rows it makes, and takes the table as it lands. One arrangement works off the main actor at a time: a newer one
    /// waits for the one before it to end, ended or not, which it does at its next step, so a steady run of edits never piles
    /// sorts up. Like `PlaceWork`'s runs, it lands only while `key` is still the table asked for.
    private func arrange(
        _ key: TableKey, items: [Item], after earlier: (key: TableKey, content: ItemTableContent)?,
        updating update: (content: ItemTableContent, changed: Set<ItemID>)?, in library: any ItemLibrary
    ) {
        arranging?.task.cancel()
        let place = shown
        let sameChoices = key.choices == earlier?.key.choices
        // Only the items' own changes settle: a membership change may have taken an item away, which must not stay chosen.
        let settles = sameChoices && key.basis.membership == earlier?.key.basis.membership
        // The arrangement before ends once the work it has off the main actor ends.
        let previous = lastArrangement
        let options = tableOptions[shown] ?? ItemTableOptions()
        let searching = isSearching
        let token = UUID()
        let from = update.map { (made: $0.content.made, wants: $0.content.wants, earlier: $0.content.earlierOffMainActor, changed: $0.changed) }
        let task = Task { [weak self] in
            if settles { try? await Task.sleep(for: Browser.arrangeSettling) }
            await previous?.value
            guard let self, !Task.isCancelled, self.askedTable == key, self.shown == place, self.isShowing(library) else {
                self?.endArranging(token)
                return
            }
            let looks = self.looks(in: library)
            let shownRelations = self.shownRelations
            let (wants, plan) = await Task.detached(priority: .userInitiated) {
                let wants = ItemTableContent.Wants(items: items, looks: looks, options: options, shown: shownRelations)
                let plan = from.flatMap {
                    ItemTableContent.Update(items: items, earlier: $0.made, earlierWants: $0.wants, changed: $0.changed, wants: wants)
                }
                return (wants, plan)
            }.value
            guard self.isLive(token, key, place, searching) else { return self.endArranging(token) }
            var start = ContinuousClock.now
            let reading = plan.map { ItemTableContent.reading(browser: self, library: library, update: $0, items: items) }
                ?? ItemTableContent.reading(browser: self, library: library, items: items, wants: wants)
            Cost.record(.tableArrange, since: start)
            let made = await Task.detached(priority: .userInitiated) {
                if let from, plan != nil { ItemTableContent.Made(reading, updating: from.made, items: items) } else { ItemTableContent.Made(reading) }
            }.value
            guard self.isLive(token, key, place, searching) else { return self.endArranging(token) }
            start = ContinuousClock.now
            // The options the rows and the key were made from, not the window's now.
            let content = ItemTableContent(
                browser: self, library: library, made: made, wants: wants, options: options, hidesEmptyGroups: key.choices.hidesEmpty)
            let ordering = content.ordering
            let remade = plan?.remade
            Cost.record(.tableArrange, since: start)
            let ordered = await Task.detached(priority: .userInitiated) {
                guard let from, let remade else { return ordering.ordered() }
                let earlier = ItemTableContent.Ordering.Earlier(
                    columns: from.earlier.columns, sort: from.earlier.sort, ordered: from.earlier.landed ?? from.earlier.ordering.ordered())
                return ordering.updated(from: earlier, changed: remade)
            }.value
            guard self.isLive(token, key, place, searching) else { return self.endArranging(token) }
            start = ContinuousClock.now
            // The chosen row is read as the table lands, where the held table shows it now. The held table's rows are
            // read only for that row, since reading them sorts them on the main actor where they were never asked for.
            if sameChoices, self.viewMode != .digest, self.selection.count == 1, let pinned = self.selection.first {
                let shownRows = (searching ? self.heldSearch : self.heldTables[place])?.content.rows ?? earlier?.content.rows
                content.land(ordered, rows: Browser.holding(pinned, in: ordered.rows, as: shownRows))
            } else {
                content.land(ordered)
            }
            Cost.record(.tableArrange, since: start)
            self.arranging = nil
            if plan == nil { self.placeWorkCounts.tablesMade += 1 } else { self.placeWorkCounts.tablesUpdated += 1 }
            self.tableMemo = (key, content)
            if searching { self.heldSearch = (key, content) } else { self.hold((key, content), for: place) }
            self.tableArrangements += 1
        }
        lastArrangement = task
        arranging = (key, token, task)
    }

    /// Whether the arrangement of `token` is still the one under way, for the table last asked, the place and the search it
    /// began for.
    private func isLive(_ token: UUID, _ key: TableKey, _ place: PlaceView, _ searching: Bool) -> Bool {
        !Task.isCancelled && arranging?.token == token && askedTable == key && shown == place && isSearching == searching
    }

    /// Ends the arrangement of `token` that did not land, so the next ask for that table arranges it again. A task that
    /// was replaced finds another's record and leaves it. With no token, ends whichever is under way, which a table
    /// taken in its place makes older.
    private func endArranging(_ token: UUID? = nil) {
        guard let arranging, token == nil || arranging.token == token else { return }
        if token == nil { arranging.task.cancel() }
        self.arranging = nil
    }

    /// `rows` with the row of `id` where it stood in `earlier`, where both hold it.
    nonisolated static func holding(_ id: ItemID?, in rows: [ItemTableRow], as earlier: [ItemTableRow]?) -> [ItemTableRow] {
        guard let id, let earlier, let was = earlier.firstIndex(where: { $0.id == id }),
              let now = rows.firstIndex(where: { $0.id == id }), was != now else { return rows }
        var moved = rows
        moved.insert(moved.remove(at: now), at: min(was, moved.count))
        return moved
    }

    /// What everything worked out from a place's items depends on besides the items: which library, the place and how
    /// the window orders them. The items themselves are listed only where they can change without the library's revisions
    /// doing so, which is a search answering and a saved view's list arriving, and are handed back so the caller does not
    /// list them twice. Reading it observes the library's revisions, so a view that asks is told of the next change.
    private func derivedKey(in library: any ItemLibrary) -> (key: DerivedKey, items: [Item]?) {
        let listed = isSearching || shown.savedView != nil ? items(in: library) : nil
        _ = (library.contentRevision, library.membershipRevision)
        let key = DerivedKey(
            library: ObjectIdentifier(library), place: shown, listing: listing, ids: listed?.map(\.id), byRelevance: ordersByRelevance,
            keepsPlaceOrder: keepsPlaceOrder, favoritesFirst: !isSearching && !showsOnlyFavorites)
        return (key, listed)
    }

    nonisolated struct DerivedKey: Equatable, Sendable {
        let library: ObjectIdentifier
        let place: PlaceView
        let listing: PlaceListing
        let ids: [ItemID]?
        let byRelevance: Bool
        let keepsPlaceOrder: Bool
        let favoritesFirst: Bool

        func isSamePlace(as other: DerivedKey) -> Bool { library == other.library && place == other.place }
    }

    /// Date groups and relative filters can change at midnight or when the time zone changes.
    nonisolated struct ClockDay: Equatable, Sendable {
        let day: Date
        let zone: TimeZone

        /// The day of `now` in `calendar`, the library's (`ItemLibrary.calendar`).
        init(now: Date, calendar: Calendar) {
            day = calendar.startOfDay(for: now)
            zone = calendar.timeZone
        }
    }

    /// What a layout's placing of the items is worked out for (`placed`).
    nonisolated struct PlacingKey<Choice: Equatable & Sendable>: Equatable, Sendable {
        let derived: DerivedKey
        let shape: ListShape?
        let choice: Choice
        /// The table the items or the order were read from (`ItemTableContent.serial`).
        let table: Int?
        /// The library's revision, where the items are the place's own.
        let content: Int?
    }

    /// What the calendar places its items by, besides the items.
    nonisolated struct CalendarChoice: Equatable, Sendable {
        let looks: [TypeID: TypeLook]
        let calendar: Calendar
        let marksFeed: Bool
    }

    /// The calendar's entries, and how many items have no date to stand on.
    nonisolated struct CalendarPlacing: Sendable {
        let entries: [CalendarEntry]
        let leftOut: Int
    }

    /// What the timeline places its items by, besides the items.
    nonisolated struct TimelineChoice: Equatable, Sendable {
        let field: String?
        let looks: [TypeID: TypeLook]
        /// Today leads the timeline.
        let clock: ClockDay
    }

    /// Where each item stands on the calendar (`CalendarLayout.entries`).
    func calendarPlacing(in library: any ItemLibrary, calendar: Calendar) -> CalendarPlacing {
        let looks = looks(in: library)
        let catalogue = library.catalogue
        let marksFeed = listing.scope == .all
        let choice = CalendarChoice(looks: looks, calendar: calendar, marksFeed: marksFeed)
        return placed(calendarWork, choice: choice, in: library) { items in
            let placed = CalendarLayout.entries(for: items, looks: looks, catalogue: catalogue, calendar: calendar, marksFeed: marksFeed)
            return CalendarPlacing(entries: placed.entries, leftOut: placed.leftOut)
        }
    }

    /// The timeline's days (`ItemTimelineLayout.groups`), by `field` or each item's own date.
    func timelinePlacing(in library: any ItemLibrary, field: String?, now: Date) -> TimelinePlacing {
        let looks = looks(in: library)
        let catalogue = library.catalogue
        let clock = ClockDay(now: now, calendar: library.calendar())
        return placed(timelineWork, choice: TimelineChoice(field: field, looks: looks, clock: clock), in: library) { items in
            TimelinePlacing(groups: ItemTimelineLayout.groups(for: items, field: field, looks: looks, catalogue: catalogue, today: now))
        }
    }

    /// The timeline's days, with what the timeline reads of them without a pass over the place.
    nonisolated struct TimelinePlacing: Sendable {
        let groups: [ItemTimelineGroup]
        /// Where each item stands, counting rows from the first day.
        let positions: [ItemID: Int]
        let types: Set<TypeID>

        init(groups: [ItemTimelineGroup]) {
            self.groups = groups
            let rows = groups.flatMap(\.rows)
            positions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            types = Set(rows.map(\.item.type))
        }

        /// The parts of the days that `drawn` draws (`ListDrawn`), each a day or the part of one.
        func drawn(_ drawn: ListDrawn) -> [DrawnDay] {
            drawn.parts(of: groups.map(\.rows.count)).map { part in
                let group = groups[part.section]
                return DrawnDay(group: ItemTimelineGroup(id: group.id, rows: Array(group.rows[part.items])), part: part)
            }
        }
    }

    /// A day of the timeline as drawn, or the part of one.
    nonisolated struct DrawnDay: Identifiable, Sendable {
        let group: ItemTimelineGroup
        let part: ListDrawn.Part
        var id: String { "\(part.run):\(group.id)" }
    }

    nonisolated struct SectionsChoices: Equatable, Sendable {
        let derived: DerivedKey
        let order: ItemOrder
        /// The list's date headings say Today and Yesterday.
        let clock: ClockDay
        let shape: ListShape?
        /// Hide Empty Groups, which only an arranged list's groups read and which is kept apart from the place's options.
        let hidesEmpty: Bool
        let digestStacking: Bool?
        /// The parents whose sub-items the list shows, where the list nests them (`ListArrangement.nested`).
        let expanded: Set<ItemID>?
    }

    nonisolated struct SectionsKey: Equatable, Sendable {
        let choices: SectionsChoices
        /// The table the sections are made from, where the place is filtered or arranged (`ItemTableContent.serial`).
        let table: Int?
        /// The library's revision, where the sections are made from the place's items.
        let content: Int?
    }

    /// The revisions a table was made at, which a change of items moves and an update follows.
    nonisolated struct TableBasis: Equatable, Sendable {
        let content: Int
        let membership: Int
        /// A changed or evicted count answer changes the rows that show it.
        let counts: Int
    }

    /// What a table is made for besides the items: an update follows a table of the same choices.
    struct TableChoices: Equatable {
        let derived: DerivedKey
        let options: ItemTableOptions
        let choices: [TypeID: TypeLookChoice]
        let shownRelations: Set<Relation>
        let hidesEmpty: Bool
        /// The names the server gave sources, which a row holds from when it was made, so the Source column sorts by them.
        let sources: [String: SourceInfo]
        /// The clock used for relative filters and date groups, which a board's lanes read too wherever the board chose
        /// them by date itself (`boardLanes`), so it is held whatever the table groups by.
        let clock: ClockDay
        /// The search's tokens, which narrow the rows the table keeps.
        let tokens: [FilterClause]
    }

    struct TableKey: Equatable {
        let choices: TableChoices
        let basis: TableBasis
    }

    private var showsOnlyFavorites: Bool { shown.isFavorites }
}

/// How often a window worked a place's table or list out whole, and how often it updated one from the last.
nonisolated struct PlaceWorkCounts: Equatable, Sendable {
    var tablesMade = 0
    var tablesUpdated = 0
    var listsSorted = 0
    var listsUpdated = 0
}

/// What a list's sections are made of (`Browser.sections`), read on the main actor and made with no actor, so a large
/// place's are made off it.
nonisolated struct ListSections: Sendable {
    enum Source: Sendable {
        /// The rows of a table that sorts or groups the place.
        case table(TableSections)
        /// Items the list orders itself, with the sections made of them before and the items changed since, where known.
        case list([Item], earlier: ListArrangement?, changed: Set<ItemID>?, content: Int?)
    }

    let source: Source
    let order: ItemOrder
    let now: Date
    /// Whether the items keep the order given: a collection's own, or a search's by relevance.
    let ordersItself: Bool
    let favoritesFirst: Bool

    var count: Int {
        switch source {
        case .table(let table): table.kept.count
        case .list(let items, _, _, _): items.count
        }
    }

    func make() -> ListArrangement {
        switch source {
        case .table(let table):
            return ListArrangement(
                sections: table.sections(order: order, now: now, ordersItself: ordersItself, favoritesFirst: favoritesFirst), sorted: nil,
                content: nil)
        case .list(let items, let earlier, let changed, let content):
            if ordersItself {
                return ListArrangement(sections: items.isEmpty ? [] : [ItemSection(group: nil, items: items)], sorted: nil, content: content)
            }
            let sorted = Self.sorted(items, by: order.sort, earlier: earlier?.sorted, changed: changed)
            let sections = ItemGroup.sections(
                ofSorted: sorted, sort: order.sort, favoritesFirst: favoritesFirst, groupsByDate: order.groupsByDate, now: now)
            return ListArrangement(sections: sections, sorted: sorted, content: content)
        }
    }

    /// `items` in `sort`'s order. From the same list's items in that order before `changed` changed, only the changed items,
    /// and those that joined, are sorted and merged into the rest.
    static func sorted(_ items: [Item], by sort: ItemSort, earlier: [Item]?, changed: Set<ItemID>?) -> [Item] {
        guard let earlier, let changed else { return sort.sorted(items) }
        let positions = Dictionary(items.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
        let was = Set(earlier.map(\.id))
        let staying = earlier.filter { !changed.contains($0.id) && positions[$0.id] != nil }
        let fresh = items.filter { changed.contains($0.id) || !was.contains($0.id) }
        return sort.merged(staying, sort.sorted(fresh), positions: positions)
    }
}

/// A list's sections, what a layout reads of them without a pass over the place, and the items in the list's order they
/// were made of, which the next change re-places items in.
nonisolated struct ListArrangement: Sendable {
    static let empty = ListArrangement(sections: [], sorted: nil, content: nil)
    let sections: [ItemSection]
    var digest: DigestLayout.Display?
    /// Every item of the sections, in order, the folded ones too.
    let ids: [ItemID]
    /// The items the list shows, in order: those of the sections not folded away.
    let shownIDs: [ItemID]
    /// Where each of `ids` stands.
    let positions: [ItemID: Int]
    /// Where each of `shownIDs` stands.
    let shownPositions: [ItemID: Int]
    /// The types of the items.
    let types: Set<TypeID>
    /// The items in the list's own order, before favorites lead, where the list ordered them.
    let sorted: [Item]?
    /// The library's revision the items were listed at, where they are the place's own.
    private(set) var content: Int?
    /// Where each item drawn stands among its parents, where the list nests them; empty where none nests.
    private(set) var nesting: [ItemID: ItemNesting.Place] = [:]
    /// The sub-items a closed parent hides, which the list holds without drawing.
    private(set) var nestedAway: Set<ItemID> = []

    init(sections: [ItemSection], sorted: [Item]?, content: Int?, nesting: [ItemID: ItemNesting.Place] = [:]) {
        self.sections = sections
        self.sorted = sorted
        self.content = content
        self.nesting = nesting
        ids = sections.flatMap { $0.items.map(\.id) }
        shownIDs = sections.flatMap { $0.isCollapsed ? [] : $0.items.map(\.id) }
        positions = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        shownPositions = shownIDs.count == ids.count
            ? positions : Dictionary(shownIDs.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        types = Set(sections.lazy.flatMap(\.items).map(\.type))
    }

    /// The parts of the sections that `drawn` draws (`ListDrawn`), for a layout that draws a page at a time
    /// (`Browser.listDrawn`). A folded section's items count only where `countsFolded`, as in the gallery, which draws
    /// them; the list counts the items it shows (`shownPositions`). In a grid of `columns`, a part starts at a row.
    func drawn(_ drawn: ListDrawn, countsFolded: Bool, columns: Int = 1) -> [DrawnSection] {
        let counts = sections.map { countsFolded || !$0.isCollapsed ? $0.items.count : 0 }
        return drawn.parts(of: counts, columns: columns).map { part in
            var section = sections[part.section]
            if part.items.count < section.items.count { section.items = Array(section.items[part.items]) }
            return DrawnSection(section: section, part: part)
        }
    }

    /// The same sections with each sub-item under its parent where both are in one section (`ItemNesting`), and drawn only
    /// where every parent above it is in `expanded`.
    func nested(expanded: Set<ItemID>) -> ListArrangement {
        var places: [ItemID: ItemNesting.Place] = [:]
        var away: Set<ItemID> = []
        let sections = sections.map { section in
            let nesting = ItemNesting(items: section.items)
            guard !nesting.isFlat else { return section }
            var nested = section
            let drawn = nesting.drawn(expanded: expanded).places
            nested.items = drawn.map { section.items[$0.index] }
            for place in drawn { places[place.id] = place }
            if drawn.count < section.items.count {
                let shown = Set(drawn.map(\.id))
                away.formUnion(section.items.lazy.map(\.id).filter { !shown.contains($0) })
            }
            return nested
        }
        guard !places.isEmpty else { return self }
        var made = ListArrangement(sections: sections, sorted: sorted, content: content, nesting: places)
        made.digest = digest
        made.nestedAway = away
        return made
    }

    /// The same sections, as made at the library's revision `content`, which changed none of their items.
    func at(_ content: Int) -> ListArrangement {
        var moved = self
        moved.content = content
        return moved
    }
}

/// A section of the list or the gallery as drawn, or the part of one, with where it falls among the runs drawn.
nonisolated struct DrawnSection: Identifiable, Sendable {
    let section: ItemSection
    let part: ListDrawn.Part
    var id: String { "\(part.run):\(part.section)" }
}

/// What an arranged table gives the list's sections: its rows in order and its groups.
nonisolated struct TableSections: Sendable {
    let rows: [ItemTableRow]
    let groups: [ItemTableGroup]
    let kept: [Item]
    let grouping: ItemTableColumn?
    let groupMode: GroupMode
    let collapsed: Set<String>
    /// Whether the person or the view chose the grouping: the table groups a place by status on its own, the list does not.
    let groupsByOwnGroup: Bool

    func sections(order: ItemOrder, now: Date, ordersItself: Bool, favoritesFirst: Bool) -> [ItemSection] {
        guard groupsByOwnGroup, let column = grouping else {
            return rows.isEmpty ? [] : [ItemSection(group: nil, items: rows.map(\.item))]
        }
        // An item's own date by day reads in a list as the list's sections always have: Today, Yesterday, Previous 7
        // Days, Previous 30 Days, then months and years.
        if groupMode == .bucket(.day), [ItemTableColumn.created.id, ItemTableColumn.edited.id, ItemTableColumn.occurred.id].contains(column.id) {
            var sections: [ItemSection] = []
            var grouper = ItemGroup.Grouper(now: now)
            for row in groups.flatMap(\.rows) {
                let group = column.date(of: row, calendar: .current).map { grouper.group(for: $0) }
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
        return groups.map {
            ItemSection(group: .custom(id: $0.id, title: $0.title), items: $0.rows.map(\.item), isCollapsed: collapsed.contains($0.id))
        }
    }
}
