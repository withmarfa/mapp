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

    /// The order a starting point sets: as the window holds it, and as the view is written.
    var sort: (window: [ItemTableComparator], saved: [LibraryViewSort])? {
        switch self {
        case .recentlyAdded, .inbox:
            ([ItemTableComparator(column: .created, order: .reverse)], [LibraryViewSort(field: "created_at", ascending: false)])
        default: nil
        }
    }
}

/// Making a view from a starting point: which ones fit the place, what each does to the window, which the person already
/// has, the name the panel suggests, and Create View's checks. The window shows the view as it will list, and the
/// panel's snapshot puts the place back on Cancel.
extension Browser {
    /// The search's tokens This Search starts from: the window's search, or the one set aside while another starting
    /// point shows its own list.
    private var newViewSearchTokens: [FilterClause] { viewPanel?.setAsideSearch?.tokens ?? searchTokens }

    /// What This Search saves of the search's tokens: the filters Marfa can say, and the From a From token names, which
    /// becomes the view's tier as Marfa holds it. The panel names the other tokens (`ViewDraft.Unkept.searchToken`).
    func searchStart(in library: any ItemLibrary) -> (filters: [FilterClause], scope: ListScope?, inFrom: [FilterClause]) {
        let tokens = newViewSearchTokens
        let targets = tokenTargets(in: library, of: tokens)
        let place = (viewPanel?.snapshot?.place ?? shown).place
        var result: (filters: [FilterClause], scope: ListScope?, inFrom: [FilterClause]) = ([], nil, [])
        for token in tokens {
            if token.field == FilterTarget.tier.id {
                guard token.op == .is, token.values.count == 1, let tier = token.values.first.flatMap(Tier.init(word:)) else { continue }
                if place.takesScope, result.scope == nil {
                    result.scope = ListScope(tier: tier)
                    result.inFrom.append(token)
                } else if place == .library && tier == .library || place == .feed && tier == .feed {
                    // The place lists that tier already.
                    result.inFrom.append(token)
                }
            } else if targets[token.field].flatMap({ ViewDraft.piece(of: token, target: $0, calendar: .current) }) != nil {
                result.filters.append(token)
            }
        }
        return result
    }

    /// The search's tokens that Marfa can save as a view's filter.
    func searchTokenFilters(in library: any ItemLibrary) -> [FilterClause] {
        searchStart(in: library).filters
    }

    /// The starting points for the place the new view began on, three to a tile row: This Search first while searching,
    /// then what fits the place's fields, then In the Feed, the Feed's Inbox and Blank. A saved view's Save as New View…
    /// starts from that view, so it offers none.
    func newViewStarts(in library: any ItemLibrary) -> [NewViewStart] {
        guard let snapshot = viewPanel?.snapshot, snapshot.place.view == .own else { return [] }
        let place = snapshot.place.place
        var starts: [NewViewStart] = []
        let search = searchStart(in: library)
        if !search.filters.isEmpty || !search.inFrom.isEmpty { starts.append(.search) }
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
        panel.choosesNoSource = false
        panel.tokensInFrom = []
        // Any other starting point shows its own list, so the search is set aside until the panel closes.
        if start == .search { restoreSetAsideSearch(of: panel) } else { setSearchAside(in: panel) }
        switch start {
        case .search:
            let search = searchStart(in: library)
            // The place's From, Archived Items and Include Kinds stay, and a From token sets the From.
            options.scope = search.scope ?? snapshot.options?.scope
            options.archived = snapshot.options?.archived
            options.includesKinds = snapshot.options?.includesKinds
            options.filter.clauses = search.filters
            panel.tokensInFrom = search.inFrom
        case .recentlyAdded:
            options.sort = start.sort?.window
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
            options.sort = start.sort?.window
            layout = .list
            panel.quickActions = true
        case .blank:
            layout = .table
        }
        tableOptions[place] = options
        if layout != viewMode { set(layout: layout) }
        panel.start = start
        panel.suggest(suggestedViewName(in: library))
        panel.startingValues = newViewValues()
    }

    private func setSearchAside(in panel: ViewPanel) {
        guard panel.setAsideSearch == nil, narrowsBySearch else { return }
        panel.setAsideSearch = ViewPanel.SetAsideSearch(text: searchText, tokens: searchTokens, relevanceChoice: relevanceChoice)
        searchText = ""
        searchTokens = []
    }

    func restoreSetAsideSearch(of panel: ViewPanel) {
        guard let aside = panel.setAsideSearch else { return }
        panel.setAsideSearch = nil
        searchText = aside.text
        searchTokens = aside.tokens
        relevanceChoice = aside.relevanceChoice
    }

    // MARK: What the person has made of it

    /// The new view's values as the window shows them now.
    func newViewValues() -> ViewPanel.Values? {
        guard let panel = viewPanel, panel.isNew, let place = panel.snapshot?.place else { return nil }
        var options = (tableOptions[place] ?? ItemTableOptions()).settled
        options.collapsed = nil
        return ViewPanel.Values(
            options: options, layout: viewMode, timelineDate: timelineFields[place], quickActions: panel.quickActions,
            addsToSidebar: panel.addsToSidebar, choosesNoSource: panel.choosesNoSource)
    }

    /// Whether the new view holds the person's work: a name they typed, a value they changed since the starting point,
    /// or a Create View that Marfa has not taken yet, still on its way or refused.
    func isNewViewTouched(_ panel: ViewPanel) -> Bool {
        guard panel.isNew, viewPanel === panel else { return false }
        return panel.form?.isSaving == true || panel.problem != nil || panel.hasTypedName || newViewValues() != panel.startingValues
    }

    /// Whether a click outside the panel must not end it: while the new view holds the person's work, whatever
    /// Create View's state.
    var keepsNewViewOpen: Bool {
        guard let panel = viewPanel else { return false }
        return isNewViewTouched(panel)
    }

    /// What the new view gives back as it ends any way but Cancel: the whole of it in words while it holds the
    /// person's work, and nothing otherwise.
    func newViewHandOff(in library: any ItemLibrary) -> String? {
        guard let panel = viewPanel, isNewViewTouched(panel) else { return nil }
        return newViewDescription(in: library)
    }

    /// The summary given back when an unsaved draft closes.
    func newViewDescription(in library: any ItemLibrary) -> String {
        let panel = viewPanel
        let typed = panel?.trimmedName ?? ""
        let name = typed.isEmpty ? suggestedViewName(in: library) : typed
        let content = tableContent(in: library)
        let options = tableOptions[shown] ?? ItemTableOptions()
        let catalogue = library.catalogue
        let place = shown.place
        let isTypes = { (clause: FilterClause) in clause.field == ViewDraft.typeFieldID && clause.op == .is }
        let types = (options.filter.clauses.first(where: isTypes)?.values ?? []).filter { !$0.isEmpty }
            .map { catalogue.itemTypes[TypeID($0)]?.plural ?? $0 }
        var words: [String] = []
        if !types.isEmpty {
            words.append(types.formatted(.list(type: .and, width: .standard)))
        } else if case .type = place {
            words.append(library.name(of: place))
        } else {
            words.append(String(localized: "All items"))
        }
        switch place {
        case .library: words.append(String(localized: "from the Library"))
        case .feed: words.append(String(localized: "from the Feed"))
        case .collection, .source: words.append(String(localized: "in \(library.name(of: place))"))
        default: break
        }
        if place.takesScope { words += [String(localized: "from"), listing.scope.title] }
        let conditions = options.filter.clauses.filter { $0.isComplete && !isTypes($0) }
        if conditions.isEmpty {
            words += [String(localized: "with"), String(localized: "no filter")]
        } else {
            let said = conditions.map { clause -> String in
                guard let target = content.filterOffer.targets[clause.field] else { return clause.values.joined(separator: ", ") }
                let parts = FilterWording.parts(of: clause, target: target, calendar: .current, titles: { library.title(ofValue: $0) })
                return [parts.field, parts.relation, parts.values].filter { !$0.isEmpty }.joined(separator: " ")
            }
            let joined = options.filter.matchesAny
                ? said.formatted(.list(type: .or, width: .standard)) : said.formatted(.list(type: .and, width: .standard))
            words += [String(localized: "where"), joined]
        }
        words += [String(localized: "as a"), viewMode.title]
        if viewMode != .timeline, viewMode != .calendar, !keepsPlaceOrder {
            let sort = SavedViews.arrangement(self, content: content, order: storedOrder).sort
            if let first = sort.first {
                let direction = first.order == .forward ? first.column.ascendingTitle : first.column.descendingTitle
                words += [String(localized: "sorted by"), first.column.label + ",", direction.localizedLowercase]
            }
            let grouping = shownGrouping(in: library)
            if grouping != .none, let found = groupOffer(in: library).entry(for: grouping) {
                words += [String(localized: "grouped by"), found.entry.label]
            }
        }
        var lines = [name, words.joined(separator: " ")]
        if offersNewViewQuickActions {
            lines.append(showsQuickActions ? String(localized: "Quick Actions: On") : String(localized: "Quick Actions: Off"))
        }
        let addsToSidebar = panel?.addsToSidebar == true
        lines.append(addsToSidebar ? String(localized: "Add to Sidebar: On") : String(localized: "Add to Sidebar: Off"))
        return lines.joined(separator: "\n")
    }

    /// Whether the new view offers Quick Actions: only where it lists the Feed, whose rows they are for.
    var offersNewViewQuickActions: Bool { listing.scope == .feed }

    /// The Feed's sources an inbox can list, by name with their counts.
    func inboxSources(in library: any ItemLibrary) -> [(code: String, name: String, count: Int)] {
        library.sources.listing(loaded: [:])
    }

    /// The sources the window's source filter holds; empty is every source.
    var chosenSources: [String] {
        tableOptions[shown]?.filter.clauses.first { $0.field == FilterTarget.source.id && $0.op == .is }?.values ?? []
    }

    /// Whether an inbox's menu ticks `code`: every source while none is named, and none once the person unticked the last.
    func ticksSource(_ code: String) -> Bool {
        if viewPanel?.choosesNoSource == true { return false }
        let chosen = chosenSources
        return chosen.isEmpty || chosen.contains(code)
    }

    /// Ticks or unticks one source of an inbox. Every source ticked is no filter at all, and none ticked is a view
    /// Create View won't make until one is ticked again.
    func setSource(_ code: String, chosen: Bool, in library: any ItemLibrary) {
        let all = inboxSources(in: library).map(\.code)
        var chosenNow = Set(all.filter(ticksSource))
        if chosen { chosenNow.insert(code) } else { chosenNow.remove(code) }
        var options = tableOptions[shown] ?? ItemTableOptions()
        options.filter.clauses.removeAll { $0.field == FilterTarget.source.id && $0.op == .is }
        if !chosenNow.isEmpty, chosenNow != Set(all) {
            options.filter.clauses.append(FilterClause(field: FilterTarget.source.id, op: .is, values: all.filter(chosenNow.contains)))
        }
        viewPanel?.choosesNoSource = chosenNow.isEmpty
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
