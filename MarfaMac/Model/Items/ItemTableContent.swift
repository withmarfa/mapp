import Foundation

/// What a place's table shows, worked out once for the window (`Browser.tableContent(in:)`) and shared by the table,
/// its toolbar's controls, the menu bar and the command palette. The columns, the sort and the grouping come from
/// the items alone; the rows the filters keep, their groups and what is folded away are worked out when first
/// read, so the controls and the command palette, which need only the columns, never sort.
@MainActor
final class ItemTableContent {
    /// Every row before the filters.
    let allRows: [ItemTableRow]
    /// Tells this table from every other made in the run, for what is worked out from it (`Browser.sections`).
    let serial = ItemTableContent.nextSerial()
    private static var serials = 0
    private static func nextSerial() -> Int {
        serials += 1
        return serials
    }
    /// What the rows were made of, which an update of the table starts from (`updating`).
    let made: Made
    /// The links and counts the rows were made with, nil where the table was made for nothing.
    let wants: Wants?
    let columns: [ItemTableColumn]
    let sort: [ItemTableComparator]
    let grouping: ItemTableColumn?
    /// How `grouping` groups: by each value, or by a date's span.
    let groupMode: GroupMode
    private let options: ItemTableOptions
    /// The calendar dates are grouped on: a saved view's weeks start on Monday, a place's where Settings says.
    let calendar: Calendar
    private let catalogue: Catalogue
    /// The types the place lists, which its filters' fields come from with the types of its items (`Browser.listedTypes`).
    private let listedTypes: Set<TypeID>
    /// The types of its items.
    private let heldTypes: Set<TypeID>
    /// When the table was worked out, which a filter relative to the day reads as today.
    private let now: Date

    /// The search's tokens and the fields they ask about, which narrow the rows beside the filters.
    private let tokens: FilterState
    private let tokenTargets: [String: FilterTarget]

    /// The rows the filters and the search's tokens keep, in the order the items came in: what a layout that sorts and
    /// groups the items itself (the list, the board, the timeline) works from.
    lazy var kept: [ItemTableRow] = {
        let clock = FilterMatching.Clock(now: now, calendar: .current)
        let filtered = options.isFiltering
            ? FilterMatching.filter(allRows, by: options.filter, targets: filterOffer.targets, catalogue: catalogue, clock: clock)
            : allRows
        return tokens.isEmpty
            ? filtered : FilterMatching.filter(filtered, by: tokens, targets: tokenTargets, catalogue: catalogue, clock: clock)
    }()

    /// The items of `kept`, for the layouts that place items themselves.
    lazy var keptItems: [Item] = kept.map(\.item)

    /// What Filter By offers for the place: the fields of the types it lists, then what every item has.
    lazy var filterOffer = FilterOffer.make(
        columns: columns, types: listedTypes.union(heldTypes), catalogue: catalogue)

    /// The rows the filters keep, in order.
    lazy var rows: [ItemTableRow] = Cost.measure(.tableRows) {
        ItemTableLayout.sorted(kept, by: sort)
    }
    /// Every group in order, the hidden and the empty ones too: what the View panel's Group lists to order and hide. A grouping the
    /// person or the view chose lists its empty groups (`declared`), which a place's own grouping by status does not.
    lazy var allGroups: [ItemTableGroup] = Cost.measure(.tableGroups) {
        guard let grouping else { return [] }
        let made = ItemTableLayout.groups(
            of: rows, by: grouping, mode: groupMode, catalogue: catalogue, declared: options.grouping != .automatic,
            asMarfa: groupsAsMarfa, calendar: calendar)
        return ItemTableLayout.ordered(made, by: options.groupOrder)
    }
    /// The groups shown: all but the hidden ones (`device/view-group-hidden`), and the empty ones where Hide Empty Groups is on.
    lazy var groups: [ItemTableGroup] = {
        let hidden = options.hiddenGroups ?? []
        return allGroups.filter { !hidden.contains($0.id) && !(hidesEmptyGroups && $0.rows.isEmpty) }
    }()
    lazy var collapsed: Set<String> = grouping.map { ItemTableLayout.collapsed(options, groups: groups, by: $0, mode: groupMode) } ?? []
    /// Whether the rows are all in hidden groups, which says so rather than that the place is empty.
    var hidesEveryGroup: Bool { grouping != nil && !rows.isEmpty && groups.allSatisfy(\.rows.isEmpty) }
    /// Whether a group with no items is left out (Hide Empty Groups).
    let hidesEmptyGroups: Bool
    /// Whether the rows are grouped as Marfa groups a saved view's (`ItemTableLayout.groups`).
    let groupsAsMarfa: Bool

    /// Works the table out for `items`, which are what `browser` shows in `library`. Nothing is kept: ask the
    /// browser, which keeps the last one while its inputs stand.
    convenience init(browser: Browser, library: any ItemLibrary, items: [Item]) {
        let start = ContinuousClock.now
        defer { Cost.record(.tableContent, since: start) }
        let wants = Wants(items: items, browser: browser, library: library)
        self.init(
            browser: browser, library: library, made: Made(Self.reading(browser: browser, library: library, items: items, wants: wants)),
            wants: wants, options: browser.tableOptions[browser.shown] ?? ItemTableOptions(), hidesEmptyGroups: browser.hidesEmptyGroups)
    }

    /// Works the table out from its rows and columns, which may have been made off the main actor, by the `options` and
    /// Hide Empty Groups they were made under, which a table that lands later must not read again from the window.
    init(browser: Browser, library: any ItemLibrary, made: Made, wants: Wants?, options: ItemTableOptions, hidesEmptyGroups: Bool) {
        self.made = made
        self.wants = wants
        allRows = made.allRows
        columns = made.columns
        heldTypes = made.types
        catalogue = library.catalogue
        listedTypes = browser.listedTypes(in: library)
        now = library.now()
        self.options = options
        tokens = FilterState(clauses: browser.narrowingSearchTokens)
        tokenTargets = browser.tokenTargets(in: library)
        // Relevance is the order the rows come in, which the sort leaves alone when it is empty.
        sort = browser.ordersByRelevance ? [] : ItemTableLayout.sort(
            options, columns: columns, keepsGivenOrder: browser.keepsPlaceOrder, listsByOrigin: browser.listsByOrigin)
        grouping = ItemTableLayout.grouping(options, columns: columns)
        // A place's own grouping is by the status's groups, as a board of mixed types is.
        groupMode = options.grouping == .automatic ? .statusGroups : options.grouping.mode
        self.hidesEmptyGroups = hidesEmptyGroups
        groupsAsMarfa = browser.isViewPlace
        calendar = browser.isViewPlace ? DateGroups.viewCalendar() : WeekStart.calendar(.current, in: browser.defaults)
    }

    /// The links the table wants (`ItemTableLayout.relations`) and the counts the looks show, with the items the library
    /// must be asked about: every item where more than the parent is wanted, else those with a parent or a count. Worked
    /// out with no actor, so a large place's main actor asks only about those.
    nonisolated struct Wants: Sendable {
        let relations: Set<Relation>
        let counts: [TypeID: Set<CountFact>]
        let asked: [Item]

        init(items: [Item], relations: Set<Relation>, looks: [TypeID: TypeLook]) {
            self.init(items: items, relations: relations, counts: looks.compactMapValues { $0.counts.isEmpty ? nil : $0.counts })
        }

        private init(items: [Item], relations: Set<Relation>, counts: [TypeID: Set<CountFact>]) {
            self.relations = relations
            self.counts = counts
            let wantsMore = !relations.subtracting([.parent]).isEmpty
            let wantsParent = relations.contains(.parent)
            asked = wantsMore ? items : items.filter { counts[$0.type] != nil || (wantsParent && $0.parentID != nil) }
        }

        /// The same wants, asking only about `items`.
        func asking(_ items: [Item]) -> Wants { Wants(items: items, relations: relations, counts: counts) }

        /// Whether two wants read the same links and counts, whatever items they ask about.
        func readsAsMuch(as other: Wants) -> Bool { relations == other.relations && counts == other.counts }

        init(items: [Item], looks: [TypeID: TypeLook], options: ItemTableOptions, shown: Set<Relation>) {
            let relations = ItemTableLayout.relations(of: Set(items.map(\.type)), looks: looks, options: options, shown: shown)
            self.init(items: items, relations: relations, looks: looks)
        }

        @MainActor init(items: [Item], browser: Browser, library: any ItemLibrary) {
            self.init(
                items: items, looks: browser.looks(in: library), options: browser.tableOptions[browser.shown] ?? ItemTableOptions(),
                shown: browser.shownRelations)
        }
    }

    /// What `Made` needs of the browser and the library, read on the main actor.
    nonisolated struct Reading: Sendable {
        let items: [Item]
        let relations: [ItemID: ItemRelations]
        let catalogue: Catalogue
        let sources: SourceDirectory
        let looks: [TypeID: TypeLook]
        let listedTypes: Set<TypeID>
        let hidden: Set<String>
        let listsByOrigin: Bool
    }

    static func reading(browser: Browser, library: any ItemLibrary, items: [Item], wants: Wants) -> Reading {
        Reading(
            items: items, relations: ItemTableRow.relations(asking: wants, in: library), catalogue: library.catalogue,
            sources: library.sources, looks: browser.looks(in: library), listedTypes: browser.listedTypes(in: library),
            hidden: items.first.map { library.hiddenPropertyKeys(of: $0) } ?? [], listsByOrigin: browser.listsByOrigin)
    }

    /// What a table is made of before its options order it: every row, the columns and the types of its items. Made from
    /// what was read (`Reading`), it needs no actor, so a large place makes it off the main actor.
    nonisolated struct Made: Sendable {
        let allRows: [ItemTableRow]
        let columns: [ItemTableColumn]
        let types: Set<TypeID>
        /// Where each row stands in `allRows`.
        let positions: [ItemID: Int]

        init(_ reading: Reading) {
            let rows = Cost.measure(.tableMade) {
                ItemTableRow.rows(of: reading.items, relations: reading.relations, catalogue: reading.catalogue, sources: reading.sources)
            }
            self.init(rows: rows, reading: reading, types: Set(reading.items.map(\.type)))
        }

        /// `earlier` for `items`: the rows of those `reading` was made for made again, the others kept as they were. Each
        /// item `earlier` has no row for must be among those read (`Update.need`).
        init(_ reading: Reading, updating earlier: Made, items: [Item]) {
            let remade = Dictionary(
                ItemTableRow.rows(of: reading.items, relations: reading.relations, catalogue: reading.catalogue, sources: reading.sources)
                    .map { ($0.id, $0) },
                uniquingKeysWith: { _, last in last })
            let rows = Cost.measure(.tableUpdated) {
                items.compactMap { remade[$0.id] ?? earlier.positions[$0.id].map { earlier.allRows[$0] } }
            }
            self.init(rows: rows, reading: reading, types: Set(items.map(\.type)))
        }

        private init(rows: [ItemTableRow], reading: Reading, types: Set<TypeID>) {
            allRows = rows
            positions = Dictionary(rows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            columns = ItemTableLayout.columns(
                for: rows, types: reading.listedTypes, catalogue: reading.catalogue, hidden: reading.hidden, looks: reading.looks,
                listsByOrigin: reading.listsByOrigin)
            self.types = types
        }
    }

    /// What an update of a table remakes: the rows of the items that changed, and of those that joined the place, which
    /// are the only ones whose links the main actor reads again. Worked out with no actor. Nil where the update cannot
    /// follow the earlier table, because the rows now ask about other links or counts, and the table is made again.
    nonisolated struct Update: Sendable {
        let wants: Wants
        let need: [Item]

        init?(items: [Item], earlier: Made, earlierWants: Wants?, changed: Set<ItemID>, wants: Wants) {
            guard let earlierWants, wants.readsAsMuch(as: earlierWants) else { return nil }
            need = items.filter { changed.contains($0.id) || earlier.positions[$0.id] == nil }
            self.wants = wants.asking(need)
        }

        /// The ids whose rows were made again.
        var remade: Set<ItemID> { Set(need.map(\.id)) }
    }

    /// What an update needs of the browser and the library, read on the main actor: the links of the items it remakes.
    static func reading(browser: Browser, library: any ItemLibrary, update: Update, items: [Item]) -> Reading {
        Reading(
            items: update.need, relations: ItemTableRow.relations(asking: update.wants, in: library), catalogue: library.catalogue,
            sources: library.sources, looks: browser.looks(in: library), listedTypes: browser.listedTypes(in: library),
            hidden: items.first.map { library.hiddenPropertyKeys(of: $0) } ?? [], listsByOrigin: browser.listsByOrigin)
    }

    /// Whether no row of the table could differ for `changed`: none of them is a row of it, and as many items are listed
    /// as it has rows, so none joined.
    func isUntouched(by changed: Set<ItemID>, listing count: Int) -> Bool {
        count == allRows.count && !changed.contains { made.positions[$0] != nil }
    }

    /// The table for `items` worked out from `earlier` on the main actor, as a small place's is: the rows of `changed`
    /// made again and re-placed, the others kept. Nil where it cannot follow `earlier` (`Update`).
    static func updating(
        _ earlier: ItemTableContent, browser: Browser, library: any ItemLibrary, items: [Item], changed: Set<ItemID>
    ) -> ItemTableContent? {
        let wants = Wants(items: items, browser: browser, library: library)
        guard let update = Update(items: items, earlier: earlier.made, earlierWants: earlier.wants, changed: changed, wants: wants)
        else { return nil }
        let made = Made(reading(browser: browser, library: library, update: update, items: items), updating: earlier.made, items: items)
        let content = ItemTableContent(
            browser: browser, library: library, made: made, wants: wants, options: browser.tableOptions[browser.shown] ?? ItemTableOptions(),
            hidesEmptyGroups: browser.hidesEmptyGroups)
        let ordered = content.ordering.updated(from: earlier.earlier, changed: update.remade)
        content.land(ordered, rows: ordered.rows)
        return content
    }

    /// What keeping and sorting the rows needs, which needs no actor, so a large place's rows are filtered and sorted off
    /// the main actor (`Browser.arrange`) and handed back with `land`.
    nonisolated struct Ordering: Sendable {
        let allRows: [ItemTableRow]
        let filter: FilterState?
        let columns: [ItemTableColumn]
        let types: Set<TypeID>
        let catalogue: Catalogue
        let now: Date
        let sort: [ItemTableComparator]
        let grouping: ItemTableColumn?
        let groupMode: GroupMode
        let declaresGroups: Bool
        /// Whether the rows are grouped as Marfa groups a saved view's (`ItemTableContent.groupsAsMarfa`).
        let groupsAsMarfa: Bool
        let groupOrder: [String]?
        let calendar: Calendar

        /// Everything the table reads of its rows that costs a pass over them, so none is made on the main actor.
        struct Ordered: Sendable {
            let offer: FilterOffer
            let kept: [ItemTableRow]
            let keptItems: [Item]
            let rows: [ItemTableRow]
            let sortChoices: [ItemTableColumn]
            /// Every group of `rows` in order, for a table that is grouped.
            let groups: [ItemTableGroup]

            fileprivate init(ordering: Ordering, offer: FilterOffer, kept: [ItemTableRow], rows: [ItemTableRow]? = nil) {
                let rows = rows ?? ItemTableLayout.sorted(kept, by: ordering.sort)
                self.offer = offer
                self.kept = kept
                keptItems = kept.map(\.item)
                self.rows = rows
                sortChoices = ItemTableLayout.sortChoices(from: ordering.columns, types: Set(kept.map(\.item.type)), catalogue: ordering.catalogue)
                groups = ordering.grouping.map {
                    ItemTableLayout.ordered(
                        ItemTableLayout.groups(
                            of: rows, by: $0, mode: ordering.groupMode, catalogue: ordering.catalogue, declared: ordering.declaresGroups,
                            asMarfa: ordering.groupsAsMarfa, calendar: ordering.calendar),
                        by: ordering.groupOrder)
                } ?? []
            }

            init(offer: FilterOffer, kept: [ItemTableRow], rows: [ItemTableRow], sortChoices: [ItemTableColumn], groups: [ItemTableGroup]) {
                self.offer = offer
                self.kept = kept
                keptItems = kept.map(\.item)
                self.rows = rows
                self.sortChoices = sortChoices
                self.groups = groups
            }
        }

        func ordered() -> Ordered {
            let offer = FilterOffer.make(columns: columns, types: types, catalogue: catalogue)
            guard let filter else { return Ordered(ordering: self, offer: offer, kept: allRows) }
            let kept = FilterMatching.filter(
                allRows, by: filter, targets: offer.targets, catalogue: catalogue, clock: .init(now: now, calendar: .current))
            return Ordered(ordering: self, offer: offer, kept: kept)
        }

        /// What `ordered()` gives, worked out from `earlier`, the same table's before the rows of `changed` were made
        /// again: only those rows are filtered and sorted, and are merged into the rows that stay. Where the columns, and so
        /// the sort and the filter's fields, are not those of `earlier`, every row is ordered again.
        func updated(from earlier: Earlier, changed: Set<ItemID>) -> Ordered {
            guard earlier.columns == columns, earlier.sort == sort else { return ordered() }
            let offer = FilterOffer.make(columns: columns, types: types, catalogue: catalogue)
            let positions = Dictionary(allRows.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
            let fresh = allRows.filter { changed.contains($0.id) }
            let kept: [ItemTableRow]
            let freshKept: [ItemTableRow]
            if let filter {
                freshKept = FilterMatching.filter(
                    fresh, by: filter, targets: offer.targets, catalogue: catalogue, clock: .init(now: now, calendar: .current))
                let passes = Set(freshKept.map(\.id))
                let wasKept = Set(earlier.ordered.kept.map(\.id))
                kept = allRows.filter { changed.contains($0.id) ? passes.contains($0.id) : wasKept.contains($0.id) }
            } else {
                freshKept = fresh
                kept = allRows
            }
            guard !sort.isEmpty else { return Ordered(ordering: self, offer: offer, kept: kept, rows: kept) }
            // The rows that did not change keep their order; a row that left the place is no longer in `positions`.
            let staying = earlier.ordered.rows.filter { !changed.contains($0.id) && positions[$0.id] != nil }
            let rows = ItemTableLayout.merged(
                staying, ItemTableLayout.sorted(freshKept, by: sort), by: sort, positions: positions)
            return Ordered(ordering: self, offer: offer, kept: kept, rows: rows)
        }

        /// What an update of a table reads of the table before it.
        struct Earlier: Sendable {
            let columns: [ItemTableColumn]
            let sort: [ItemTableComparator]
            let ordered: Ordered
        }
    }

    var ordering: Ordering {
        Ordering(
            allRows: allRows, filter: options.isFiltering ? options.filter : nil, columns: columns,
            types: listedTypes.union(heldTypes), catalogue: catalogue, now: now, sort: sort,
            grouping: grouping, groupMode: groupMode, declaresGroups: options.grouping != .automatic,
            groupsAsMarfa: groupsAsMarfa, groupOrder: options.groupOrder, calendar: calendar)
    }

    /// Takes what `ordering` made, with `rows` in the order to show. The groups were made of the rows as sorted, so they
    /// stand only where the rows are shown as sorted; where the chosen row was kept in its place the groups are made
    /// when first read, as ever.
    func land(_ ordered: Ordering.Ordered, rows: [ItemTableRow]) {
        landed = ordered
        filterOffer = ordered.offer
        kept = ordered.kept
        keptItems = ordered.keptItems
        sortChoices = ordered.sortChoices
        if rows.elementsEqual(ordered.rows, by: { $0.id == $1.id }) { allGroups = ordered.groups }
        self.rows = rows
    }

    /// What the table landed with, its rows as sorted, before the chosen row was kept in its place.
    private var landed: Ordering.Ordered?

    /// What an update of this table starts from: what it landed with, or, for a table worked out in place, its rows as
    /// they are read, which a small place sorts and groups on the main actor anyway.
    var earlier: Ordering.Earlier {
        let ordered = landed ?? Ordering.Ordered(
            offer: filterOffer, kept: kept, rows: rows, sortChoices: sortChoices, groups: grouping == nil ? [] : allGroups)
        return Ordering.Earlier(columns: columns, sort: sort, ordered: ordered)
    }

    /// What an update off the main actor starts from: what the table landed with, or else how to order its rows there,
    /// so a large table first worked out in place is never sorted on the main actor for an update.
    var earlierOffMainActor: (columns: [ItemTableColumn], sort: [ItemTableComparator], landed: Ordering.Ordered?, ordering: Ordering) {
        (columns, sort, landed, ordering)
    }

    /// The columns Add Sort offers: those of the types the view shows after its filters, in a sensible order.
    lazy var sortChoices: [ItemTableColumn] = ItemTableLayout.sortChoices(
        from: columns, types: Set(kept.map(\.item.type)), catalogue: catalogue)
}
