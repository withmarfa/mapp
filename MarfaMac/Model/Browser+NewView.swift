import Foundation
import Marfa

/// A way to begin a new view, as a tile of the new view's panel. Each is one Marfa can save exactly: a date relative to
/// today ("this week", "overdue") waits for Marfa, so no starting point needs one.
nonisolated enum NewViewStart: String, CaseIterable, Hashable, Identifiable, Sendable {
    case search, recentlyAdded, favorites, calendar, byStatus, byType, bySource, inTheFeed, inbox, blank

    var id: String { rawValue }

    var title: String {
        switch self {
        case .search: String(localized: "This Search")
        case .recentlyAdded: String(localized: "Recently Added")
        case .favorites: String(localized: "Favorites")
        case .calendar: String(localized: "On the Calendar")
        case .byStatus: String(localized: "By Status")
        case .byType: String(localized: "By Type")
        case .bySource: String(localized: "By Source")
        case .inTheFeed: String(localized: "In the Feed")
        case .inbox: String(localized: "Inbox")
        case .blank: String(localized: "Blank")
        }
    }

    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .recentlyAdded: "clock"
        case .favorites: "star"
        case .calendar: "calendar"
        case .byStatus: "rectangle.split.3x1"
        case .byType: "square.grid.2x2"
        case .bySource: "tray.2"
        case .inTheFeed: "dot.radiowaves.up.forward"
        case .inbox: "tray"
        case .blank: "square.dashed"
        }
    }
}

/// Making a view from a starting point: which ones fit the place, what each does to the window, which the person already
/// has, the name the panel suggests, and Create View's checks. The window shows the view as it will list, and the
/// panel's snapshot puts the place back on Cancel.
extension Browser {
    /// The search's tokens that Marfa can save as a view's filter, which This Search starts from. The panel names the
    /// others (`ViewDraft.Unkept.searchToken`).
    func searchTokenFilters(in library: any ItemLibrary) -> [FilterClause] {
        let targets = tokenTargets(in: library)
        return searchTokens.filter { token in
            targets[token.field].flatMap { ViewDraft.piece(of: token, target: $0, calendar: .current) } != nil
        }
    }

    /// The starting points for the place the new view began on, three to a tile row: This Search first while searching,
    /// then what fits the place's fields, then In the Feed, the Feed's Inbox and Blank. A saved view's Save as New View…
    /// starts from that view, so it offers none.
    func newViewStarts(in library: any ItemLibrary) -> [NewViewStart] {
        guard let snapshot = viewPanel?.snapshot, snapshot.place.view == .own else { return [] }
        let place = snapshot.place.place
        var starts: [NewViewStart] = []
        if !searchTokenFilters(in: library).isEmpty { starts.append(.search) }
        starts += [.recentlyAdded, .favorites]
        if availableViewModes(in: library).contains(.calendar) { starts.append(.calendar) }
        if statusColumn(in: library) != nil { starts.append(.byStatus) }
        switch place {
        case .type: break
        case .feed: starts.append(.bySource)
        default: starts.append(.byType)
        }
        if place.takesScope { starts.append(.inTheFeed) }
        if place == .feed { starts.append(.inbox) }
        starts.append(.blank)
        return starts
    }

    /// The status field the place's types share, which By Status groups by.
    private func statusColumn(in library: any ItemLibrary) -> ItemTableColumn? {
        tableContent(in: library).columns.first { $0.groups(by: .statusGroups) }
    }

    /// The view the person already has for `start` in the place, which its tile opens instead of making another.
    func existingView(for start: NewViewStart, in library: any ItemLibrary) -> PlaceView? {
        guard let place = viewPanel?.snapshot?.place.place else { return nil }
        if start == .favorites, place == .library { return .favorites }
        let layouts = ViewLayouts.stored(in: defaults)
        let match = library.views(in: place).first { view in
            switch start {
            case .favorites:
                let terms = (try? ViewDraft.terms(of: view.query.filter))?.terms ?? []
                return terms.contains { $0.field == .tags && $0.operator == .contains && $0.value == .text(ItemTag.favorite) }
            case .recentlyAdded:
                return view.group == nil && view.sort.first == LibraryViewSort(field: "created_at", ascending: false)
            case .calendar: return layouts.settings(for: view.id)?.layout == .calendar
            case .byStatus: return view.group?.field == ViewDraft.statusGroupField
            case .byType: return view.group?.field == "type"
            case .bySource: return view.group?.field == "source"
            case .inTheFeed: return view.query.tier == .feed
            case .search, .inbox, .blank: return false
            }
        }
        return match.map { PlaceView(place, .saved($0.id)) }
    }

    /// Shows the window as `start` would list, from the place as it was when the panel opened.
    func chooseStart(_ start: NewViewStart, in library: any ItemLibrary) {
        guard let panel = viewPanel, panel.isNew, let snapshot = panel.snapshot else { return }
        let place = snapshot.place
        var options = ItemTableOptions()
        var layout = snapshot.viewMode
        panel.quickActions = nil
        switch start {
        case .search:
            options.filter.clauses = searchTokenFilters(in: library)
        case .recentlyAdded:
            options.sort = [ItemTableComparator(column: .created, order: .reverse)]
            layout = .list
        case .favorites:
            options.filter.clauses = [FilterClause(field: ItemTableColumn.tags.id, op: .includes, values: [ItemTag.favorite])]
        case .calendar:
            layout = .calendar
        case .byStatus:
            layout = .board
            if let status = statusColumn(in: library) { options.group(by: .column(status.id, by: .statusGroups)) }
        case .byType:
            layout = .table
            options.group(by: .column(ItemTableColumn.type.id))
        case .bySource:
            layout = .table
            options.group(by: .column(ItemTableColumn.source.id))
        case .inTheFeed:
            options.scope = .feed
        case .inbox:
            options.sort = [ItemTableComparator(column: .created, order: .reverse)]
            layout = .list
            panel.quickActions = true
        case .blank:
            layout = .table
        }
        tableOptions[place] = options
        if layout != viewMode { set(layout: layout) }
        panel.start = start
        panel.suggest(suggestedViewName(in: library))
    }

    /// The Feed's sources an inbox can list, by name with their counts.
    func inboxSources(in library: any ItemLibrary) -> [(code: String, name: String, count: Int)] {
        library.sources.listing(loaded: [:])
    }

    /// The sources the window's source filter holds; empty is every source.
    var chosenSources: [String] {
        tableOptions[shown]?.filter.clauses.first { $0.field == FilterTarget.source.id && $0.op == .is }?.values ?? []
    }

    /// Ticks or unticks one source of an inbox. Every source ticked is no filter at all.
    func setSource(_ code: String, chosen: Bool, in library: any ItemLibrary) {
        let all = inboxSources(in: library).map(\.code)
        var chosenNow = Set(chosenSources.isEmpty ? all : chosenSources)
        if chosen { chosenNow.insert(code) } else { chosenNow.remove(code) }
        var options = tableOptions[shown] ?? ItemTableOptions()
        options.filter.clauses.removeAll { $0.field == FilterTarget.source.id && $0.op == .is }
        if !chosenNow.isEmpty, chosenNow != Set(all) {
            options.filter.clauses.append(FilterClause(field: FilterTarget.source.id, op: .is, values: all.filter(chosenNow.contains)))
        }
        tableOptions[shown] = options
    }

    // MARK: The name

    /// The name the panel suggests: the types an inbox or a view of several types lists, else the starting point's.
    func suggestedViewName(in library: any ItemLibrary) -> String {
        let catalogue = library.catalogue
        let clause = tableOptions[shown]?.filter.clauses.first { $0.field == ViewDraft.typeFieldID && $0.op == .is }
        let types = (clause?.values ?? []).filter { !$0.isEmpty }.map { catalogue.itemTypes[TypeID($0)]?.plural ?? $0 }
        if types.count > 1 { return types.formatted(.list(type: .and, width: .standard)) }
        switch viewPanel?.start {
        case nil, .blank?: return String(localized: "New View")
        case .calendar?: return String(localized: "Calendar")
        case let start?: return start.title
        }
    }

    /// The name check for Create View. Marfa allows duplicate titles.
    func viewNamed(_ name: String, in library: any ItemLibrary) -> LibraryView? {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return library.views.first { $0.title.trimmingCharacters(in: .whitespacesAndNewlines).compare(name, options: .caseInsensitive) == .orderedSame }
    }
}
