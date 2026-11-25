import Foundation

/// What a place's table shows, worked out once for the window (`Browser.tableContent(in:)`) and shared by the table,
/// its toolbar's controls, the menu bar and the command palette. The columns, the sort and the grouping come from
/// the items alone; the rows the filters keep, their groups and what is folded away are worked out when first
/// read, so the controls and the command palette, which need only the columns, never sort.
@MainActor
final class ItemTableContent {
    /// Every row before the filters.
    let allRows: [ItemTableRow]
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

    /// The rows the filters keep, in the order the items came in: what a layout that sorts and groups the items
    /// itself (the list, the board, the timeline) works from.
    lazy var kept: [ItemTableRow] = options.isFiltering
        ? FilterMatching.filter(
            allRows, by: options.filter, targets: filterOffer.targets, catalogue: catalogue, clock: .init(now: now, calendar: .current))
        : allRows

    /// What Filter By offers for the place: the fields of the types it lists, then what every item has.
    lazy var filterOffer = FilterOffer.make(
        columns: columns, types: listedTypes.union(heldTypes), catalogue: catalogue)

    /// The rows the filters keep, in order.
    lazy var rows: [ItemTableRow] = Cost.measure(.tableRows) {
        ItemTableLayout.sorted(kept, by: sort)
    }
    /// Every group in order, the hidden and the empty ones too: what Edit View lists to order and hide. A grouping the
    /// person or the view chose lists its empty groups (`declared`), which a place's own grouping by status does not.
    lazy var allGroups: [ItemTableGroup] = Cost.measure(.tableGroups) {
        guard let grouping else { return [] }
        let made = ItemTableLayout.groups(
            of: rows, by: grouping, mode: groupMode, catalogue: catalogue, declared: options.grouping != .automatic, calendar: calendar)
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

    /// Works the table out for `items`, which are what `browser` shows in `library`. Nothing is kept: ask the
    /// browser, which keeps the last one while its inputs stand.
    convenience init(browser: Browser, library: any ItemLibrary, items: [Item]) {
        let start = ContinuousClock.now
        defer { Cost.record(.tableContent, since: start) }
        let wants = Wants(items: items, browser: browser, library: library)
        self.init(browser: browser, library: library, made: Made(Self.reading(browser: browser, library: library, items: items, wants: wants)))
    }

    /// Works the table out from its rows and columns, which may have been made off the main actor.
    init(browser: Browser, library: any ItemLibrary, made: Made) {
        let options = browser.tableOptions[browser.shown] ?? ItemTableOptions()
        allRows = made.allRows
        columns = made.columns
        heldTypes = made.types
        catalogue = library.catalogue
        listedTypes = browser.listedTypes(in: library)
        now = library.now()
        self.options = options
        // Relevance is the order the rows come in, which the sort leaves alone when it is empty.
        sort = browser.ordersByRelevance ? [] : ItemTableLayout.sort(
            options, columns: columns, keepsGivenOrder: browser.keepsPlaceOrder, listsByOrigin: browser.listsByOrigin)
        grouping = ItemTableLayout.grouping(options, columns: columns)
        // A place's own grouping is by the status's groups, as a board of mixed types is.
        groupMode = options.grouping == .automatic ? .statusGroups : options.grouping.mode
        hidesEmptyGroups = browser.hidesEmptyGroups
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
            self.relations = relations
            let counts = looks.compactMapValues { $0.counts.isEmpty ? nil : $0.counts }
            self.counts = counts
            let wantsMore = !relations.subtracting([.parent]).isEmpty
            let wantsParent = relations.contains(.parent)
            asked = wantsMore ? items : items.filter { counts[$0.type] != nil || (wantsParent && $0.parentID != nil) }
        }

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

        init(_ reading: Reading) {
            allRows = ItemTableRow.rows(
                of: reading.items, relations: reading.relations, catalogue: reading.catalogue, sources: reading.sources)
            columns = ItemTableLayout.columns(
                for: allRows, types: reading.listedTypes, catalogue: reading.catalogue, hidden: reading.hidden, looks: reading.looks,
                listsByOrigin: reading.listsByOrigin)
            types = Set(reading.items.map(\.type))
        }
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

        struct Ordered: Sendable {
            let offer: FilterOffer?
            let kept: [ItemTableRow]
            let rows: [ItemTableRow]
        }

        func ordered() -> Ordered {
            guard let filter else { return Ordered(offer: nil, kept: allRows, rows: ItemTableLayout.sorted(allRows, by: sort)) }
            let offer = FilterOffer.make(columns: columns, types: types, catalogue: catalogue)
            let kept = FilterMatching.filter(
                allRows, by: filter, targets: offer.targets, catalogue: catalogue, clock: .init(now: now, calendar: .current))
            return Ordered(offer: offer, kept: kept, rows: ItemTableLayout.sorted(kept, by: sort))
        }
    }

    var ordering: Ordering {
        Ordering(
            allRows: allRows, filter: options.isFiltering ? options.filter : nil, columns: columns,
            types: listedTypes.union(heldTypes), catalogue: catalogue, now: now, sort: sort)
    }

    /// Takes the rows `ordering` kept and sorted, with `rows` in the order to show.
    func land(_ ordered: Ordering.Ordered, rows: [ItemTableRow]) {
        if let offer = ordered.offer { filterOffer = offer }
        kept = ordered.kept
        self.rows = rows
    }

    /// The columns Add Sort offers: those of the types the view shows after its filters, in a sensible order.
    var sortChoices: [ItemTableColumn] {
        ItemTableLayout.sortChoices(from: columns, types: Set(kept.map(\.item.type)), catalogue: catalogue)
    }
}
