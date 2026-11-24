import SwiftUI
import UniformTypeIdentifiers

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the items by title. ⇧⌘P: the
/// same field searching the text of every item, each found item shown with the words around what was found. Both
/// list in sections, and what a row can do is in Actions (⌘J). Arrow keys choose, Return runs, and Escape or
/// a click outside puts it away. The commands are only what could be done now, so what it lists is what the menus
/// have enabled.
struct CommandPalette: View {
    @CurrentLibrary private var library
    @FocusedValue(\.detailsPresentation) private var details
    @FocusedValue(\.indexActions) private var indexActions
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openURL) private var openURL
    @Environment(ShortcutBindings.self) private var shortcuts: ShortcutBindings?
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @Environment(Libraries.self) private var libraries: Libraries?
    @StoredOrder private var order
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
    @AppStorage(SearchOptions.includesArchivedKey) private var includesArchived = SearchOptions.includesArchivedStandard
    @AppStorage(SearchOptions.includesInboxKey) private var includesInbox = SearchOptions.includesInboxStandard
    @AppStorage(SearchOptions.orderKey) private var searchOrder = SearchOptions.Order.standard
    @AppStorage(SearchOptions.showsSnippetsKey) private var showsSnippets = SearchOptions.showsSnippetsStandard
    let browser: Browser
    let editor: EditorController
    let mode: Browser.Palette
    @State private var query = ""
    @State private var highlighted = 0
    /// Moves the list to a row the keyboard chose, never one the pointer is over, which would slide rows under it.
    @State private var scrollTarget: String?
    /// The row Actions is open for, by its identifier, or nil while it is shut.
    @State private var actionsFor: String?
    @State private var showsFilters = false
    /// The filter row's height, which the list gives up while the row shows, so showing filters never grows the palette.
    @State private var filterRowHeight: CGFloat = 0
    /// The filters and the panel open for one, which last until the palette is put away.
    @State private var filterState = PaletteFilterState()
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private var returnFocus: Browser.Pane = .list
    /// Every item's title folded once while the palette is open, so a keystroke folds only what was typed.
    @State private var titles = PaletteMatch.Titles()
    /// What the palette lists for the query as it stands, kept across the arrow keys and anything else that runs the
    /// body again. Nothing here is observed.
    @State private var listing = Listing()
    @FocusState private var focus: PaletteFocus?
    /// What the Actions field holds and which action is chosen, kept here since the arrow keys reach the palette.
    @State private var actionsQuery = ""
    @State private var actionsHighlighted = 0
    /// What Search Items found for the query, asked once per query and again only when its answer changes (`watchSearch`),
    /// never by the body, which the arrow keys and the pointer run again and again.
    @State private var searched = SearchResults.none
    /// What `searched` lists once the filters have narrowed it: filtered when the answer or the filters change, never by the body.
    @State private var searchedItems: [Item] = []
    /// What the same search finds among the items left out of search, after the filters, which the last line counts.
    @State private var leftOut = SearchResults.none
    @State private var leftOutItems: [Item] = []
    /// Whether Show asked for this search once with nothing left out. A new search leaves out again.
    @State private var showsLeftOut = false

    /// `filters` are the ones Search Items opens with, its filter row showing while any is set.
    init(browser: Browser, editor: EditorController, mode: Browser.Palette, filters: PaletteFilters = PaletteFilters()) {
        self.browser = browser
        self.editor = editor
        self.mode = mode
        let state = PaletteFilterState()
        state.filters = filters
        _filterState = State(initialValue: state)
        _showsFilters = State(initialValue: !filters.isEmpty)
    }

    private typealias Entry = PaletteEntry
    private typealias Section = PaletteSections.Section<PaletteEntry>

    /// Everything that can change what the palette lists, other than the query.
    private struct Basis: Equatable {
        let library: ObjectIdentifier
        let content: Int
        let membership: Int
        let mode: Browser.Palette
        let returnFocus: Browser.Pane
        let selection: Set<ItemID>
        let filters: PaletteFilters
        /// What a typed search keeps and leaves out, which the items it lists follow.
        let narrowing: SearchNarrowing
        let typed: Bool
    }

    /// What is held across runs of the body: the items' titles for a basis, and how the titles ranked for a query.
    /// The commands are never held, since they read the editor, the browser and the host, which change while the
    /// palette is open and are not part of the basis.
    private final class Listing {
        var items: (basis: Basis, items: [Item], titles: [String], leftOut: [Item], leftOutTitles: [String])?
        var leftOutMatches: (key: Ranking, items: [Item])?
        var ranking: (key: Ranking, picks: [PaletteMatch.Pick], scores: [Int])?
    }

    private struct Ranking: Equatable {
        let basis: Basis
        let query: String
        let fixedTitles: [String]
    }

    private var basis: Basis {
        Basis(library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
              mode: mode, returnFocus: returnFocus, selection: browser.selection, filters: filterState.filters,
              narrowing: askedNarrowing, typed: isTyped)
    }

    private var isTyped: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// What the search keeps and leaves out: the Type filter, a type following its Include Subtypes choice, and what
    /// this library leaves out of search.
    private var narrowing: SearchNarrowing {
        let filters = filterState.filters
        let stacked = Set(browser.stackedTypes.map { TypeID($0) })
        return SearchNarrowing(
            types: filters.types, typesWithSubtypes: stacked.intersection(filters.types),
            excludesTypes: filters.negated.contains(.type), leaveOut: libraries?.searchLeaveOut ?? SearchLeaveOut(),
            includesArchived: includesArchived, includesInbox: includesInbox)
    }

    /// The search a query and its narrowing stand for, so a change of either starts the answer again.
    private struct SearchAsk: Hashable {
        let query: String
        let narrowing: SearchNarrowing
        let showsLeftOut: Bool
    }

    private var searchAsk: SearchAsk { SearchAsk(query: query, narrowing: narrowing, showsLeftOut: showsLeftOut) }

    /// A search is not held by `listing`: its answer arrives later, and `searched` follows it (`watchSearch`).
    private func shown() -> [Section] {
        mode == .search ? found : matching(basis)
    }

    var body: some View {
        let sections = shown()
        let rows = sections.flatMap(\.rows)
        let chosen = rows.indices.contains(highlighted) ? highlighted : max(rows.count - 1, 0)
        let target = actionsFor.flatMap { id in rows.first { $0.id == id } }
        VStack(spacing: 0) {
            HStack(spacing: PaletteMetrics.markGap) {
                // In the rows' mark column, so the typed words start where the titles do.
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: PaletteMetrics.markWidth)
                TextField(mode == .search ? "Search Items" : "Search Commands and Items", text: $query)
                    .textFieldStyle(.plain)
                    .interfaceFont(.title3)
                    .focused($focus, equals: .field)
                    // Actions holds the keyboard while it is open.
                    .disabled(actionsFor != nil)
                    // Read afresh: Return can come before the view is drawn again after the last key.
                    .onSubmit {
                        let current = shown().flatMap(\.rows)
                        if current.isEmpty {
                            newItem()
                        } else if let id = actionsFor, let live = current.first(where: { $0.id == id }) {
                            performHighlighted(on: live)
                        } else {
                            run(current, at: current.indices.contains(highlighted) ? highlighted : max(current.count - 1, 0))
                        }
                    }
                    .onExitCommand { escape() }
                    .accessibilityIdentifier("CommandPaletteField")
                if isTyped {
                    let count = PaletteSections.resultCount(sections) { $0.id != Self.searchItemsID }
                    Text(count == 1 ? String(localized: "1 result") : String(localized: "\(count) results"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("CommandPaletteCount")
                }
            }
            .padding(.horizontal, PaletteMetrics.markInset)
            .padding(.top, 18)
            .padding(.bottom, 12)
            if mode == .search, showsFilters {
                PaletteFilterRow(state: filterState)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterRowHeight = $0 }
            }
            results(sections, rows: rows, chosen: chosen, target: target)
        }
        .floatingPanelSurface(width: 680)
        .onKeyPress(.downArrow) {
            if let target {
                actionsHighlighted = min(actionsHighlighted + 1, max(PaletteAction.filtered(actions(for: target), by: actionsQuery).count - 1, 0))
                return .handled
            }
            highlighted = min(chosen + 1, max(rows.count - 1, 0))
            scrollTarget = rows.indices.contains(highlighted) ? rows[highlighted].id : nil
            return .handled
        }
        .onKeyPress(.upArrow) {
            if target != nil {
                actionsHighlighted = max(actionsHighlighted - 1, 0)
                return .handled
            }
            highlighted = max(chosen - 1, 0)
            scrollTarget = rows.indices.contains(highlighted) ? rows[highlighted].id : nil
            return .handled
        }
        .onKeyPress(.escape) {
            escape()
            return .handled
        }
        // Shortcut buttons, since a field takes most Command keys before a key press handler sees them. Out of sight, but
        // in the window's key equivalents. While Actions is open the palette owns every Actions shortcut: one the row
        // does not offer, or the field has filtered out, does nothing, and never reaches the window's menu.
        .background {
            if let target {
                ForEach(PaletteActionsPanel.shortcutKinds, id: \.self) { kind in
                    if let shortcut = PaletteActionsPanel.shortcut(of: kind) {
                        Button(String(describing: kind)) {
                            if let action = PaletteAction.reachable(kind, among: actions(for: target), filteredBy: actionsQuery) {
                                perform(action, on: target)
                            }
                        }
                        .keyboardShortcut(shortcut)
                        .opacity(0)
                        .frame(width: 0, height: 0)
                        .accessibilityHidden(true)
                    }
                }
            }
        }
        // The Type filter is part of the search, so a change to it asks again; the others narrow what was found.
        .onChange(of: filterState.filters) { old, new in
            highlighted = 0
            scrollTarget = nil
            if old.types != new.types || old.negated.contains(.type) != new.negated.contains(.type) {
                refreshSearch()
            } else {
                applyFilters(to: searched, leftOut: leftOut)
            }
        }
        .onChange(of: query) {
            highlighted = 0
            scrollTarget = nil
            showsLeftOut = false
            // At once, so Return before the next draw reads the answer for what was typed.
            refreshSearch()
        }
        .task(id: searchAsk) { await watchSearch() }
        .onChange(of: searchOrder) { applyFilters(to: searched, leftOut: leftOut) }
        // The row Actions is open for may go while it is open, as another device deletes it.
        .onChange(of: actionsFor != nil && (target == nil || target?.item.map { library.item($0) == nil } == true)) { _, isGone in
            if isGone { closeActions() }
        }
        .onChange(of: browser.paletteActionsRequests) { toggleActions(rows, chosen: chosen) }
        .onAppear {
            returnFocus = editor.isFocused ? .page : .list
            if !browser.paletteSeed.isEmpty {
                query = browser.paletteSeed
                browser.paletteSeed = ""
            }
        }
        // The field takes the keyboard once the palette is in the window; asked any sooner, the list keeps it.
        .defaultFocus($focus, .field)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            focus = .field
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
    }

    /// The rows, or "No Results", with the bar at their foot. Rows scroll under the bar and fade and blur out there,
    /// as the system's soft scroll edge effect draws them. Actions takes the bar's place: it grows up out of the bar
    /// and shrinks back into it, so there is only ever one layer over the rows.
    private func results(_ sections: [Section], rows: [Entry], chosen: Int, target: Entry?) -> some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if rows.isEmpty {
                    VStack(spacing: 0) {
                        Group {
                            if Self.emptyAnswer(searching: mode == .search && isTyped, results: searched) == .stillLooking {
                                Text("Still Looking")
                            } else {
                                Text("No Results")
                            }
                        }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: PaletteMetrics.emptyResultsHeight - (leftOutLine == nil ? 0 : 60))
                        leftOutRow
                    }
                } else {
                    list(sections, chosen: chosen)
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                // Kept in place while Actions is out, so the rows above do not move.
                HStack(alignment: .bottom, spacing: PaletteBar.spacing) {
                    if mode == .search {
                        PaletteFilterButton(count: filterState.filters.count, isOn: showsFilters) { showsFilters.toggle() }
                    }
                    Spacer(minLength: 0)
                    if let row = rows.indices.contains(chosen) ? rows[chosen] : nil {
                        PaletteFooter(
                            openTitle: openTitle(for: row), onOpen: { run(rows, at: chosen) },
                            actionsKeys: keys(.paletteActions), onActions: { toggleActions(rows, chosen: chosen) })
                    } else {
                        PaletteFooter(openTitle: String(localized: "New Item"), onOpen: newItem, actionsKeys: nil, onActions: nil)
                    }
                }
                .opacity(target == nil ? 1 : 0)
                .allowsHitTesting(target == nil)
                .padding(PaletteBar.inset)
            }
            if actionsFor != nil {
                // A click beside the panel puts it away and keeps the palette.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { closeActions() }
            }
            if let target {
                PaletteActionsPanel(
                    title: target.title, actions: actions(for: target),
                    perform: { perform($0, on: target) }, submit: { performHighlighted(on: target) }, close: { closeActions() },
                    query: actionsField, highlighted: $actionsHighlighted, focus: $focus
                )
                .padding(PaletteBar.inset)
                // Grows up and to the left out of where Actions stood, and shrinks back into it.
                .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
            }
        }
        .frame(minHeight: actionsFor == nil ? 0 : 340)
    }

    private func list(_ sections: [Section], chosen: Int) -> some View {
        var offset = 0
        let numbered = sections.map { section in
            defer { offset += section.rows.count }
            return (section: section, start: offset)
        }
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(numbered, id: \.section.kind) { group in
                        PaletteSectionHeader(title: group.section.kind.title)
                        ForEach(Array(group.section.rows.enumerated()), id: \.element.id) { position, entry in
                            let index = group.start + position
                            PaletteRow(
                                entry: entry, query: query, isHighlighted: index == chosen,
                                isSearch: mode == .search, showsSnippets: showsSnippets
                            ) {
                                if highlighted != index { highlighted = index }
                            } onRun: {
                                run(sections.flatMap(\.rows), at: index)
                            }
                            .id(entry.id)
                        }
                    }
                    leftOutRow
                }
                .padding(.horizontal, PaletteMetrics.listInset)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .frame(maxHeight: PaletteMetrics.resultsHeight - (mode == .search && showsFilters ? filterRowHeight : 0))
            .onChange(of: scrollTarget) { if let scrollTarget { proxy.scrollTo(scrollTarget) } }
        }
    }

    @ViewBuilder private var leftOutRow: some View {
        if let line = leftOutLine {
            PaletteLeftOutLine(text: line) { showsLeftOut = true }
                .padding(.horizontal, PaletteMetrics.listInset)
        }
    }

    /// Says how many more items matched in what is left out of search, or nil where none did.
    private var leftOutLine: String? {
        guard isTyped, !showsLeftOut else { return nil }
        if mode != .search {
            // The titles the palette matches itself: what is left out and answers them, counted in full.
            return SearchLeftOutLine.text(
                for: listing.leftOutMatches?.items ?? [], isCapped: false, narrowing: narrowing, catalogue: library.catalogue,
                sources: library.sources)
        }
        guard !leftOut.isPending else { return nil }
        return SearchLeftOutLine.text(
            for: leftOutItems, isCapped: leftOut.isCapped, narrowing: narrowing, catalogue: library.catalogue, sources: library.sources)
    }

    /// The active items the filters let through, most recently edited first, and their titles. Once words are typed, an
    /// item left out of search is not listed: the ones that would answer them are in `leftOut`, which the line at the
    /// foot counts. Worked out once for a basis, which holds the filters and the narrowing, and not for each keystroke
    /// or hover.
    private func filteredItems(_ basis: Basis) -> (items: [Item], titles: [String], leftOut: [Item], leftOutTitles: [String]) {
        if let held = listing.items, held.basis == basis { return (held.items, held.titles, held.leftOut, held.leftOutTitles) }
        let typed = basis.narrowing
        let catalogue = library.catalogue
        let recent = browser.paletteIndex(in: library).recent
        var kept = recent
        var out: [Item] = []
        if basis.typed {
            (kept, out) = typed.split(recent, in: catalogue)
        } else {
            kept = recent.filter { typed.admitsType($0.type, in: catalogue) }
        }
        let items = basis.filters.afterSearch.apply(to: kept, now: library.now())
        let leftOutItems = basis.filters.afterSearch.apply(to: out, now: library.now())
        let titles = items.map(\.title)
        let leftOutTitles = leftOutItems.map(\.title)
        listing.items = (basis, items, titles, leftOutItems, leftOutTitles)
        return (items, titles, leftOutItems, leftOutTitles)
    }

    private func openTitle(for row: Entry) -> String {
        row.item == nil ? String(localized: "Run") : String(localized: "Open")
    }

    // MARK: Running

    private func run(_ entries: [Entry], at index: Int? = nil) {
        let index = index ?? highlighted
        guard entries.indices.contains(index) else { return }
        close(returningFocus: !entries[index].takesFocus)
        entries[index].action()
        if mode == .search, isTyped, let id = entries[index].item {
            let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let editor = editor
            Task { @MainActor in await editor.find(words, in: id) }
        }
    }

    /// What was typed found nothing: quick add opens with the words as its title.
    private func newItem() {
        close(returningFocus: false)
        browser.openQuickAdd(titled: query, remembered: lastType, in: library)
    }

    private func close(returningFocus: Bool = true) {
        browser.palette = nil
        if returningFocus, browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }

    // MARK: Actions

    private func toggleActions(_ rows: [Entry], chosen: Int) {
        if actionsFor != nil {
            closeActions()
        } else if rows.indices.contains(chosen) {
            withAnimation(PaletteBar.grow) { actionsFor = rows[chosen].id }
            actionsQuery = ""
            actionsHighlighted = 0
            focus = .actions
        }
    }

    /// Escape puts away Actions if it is out, and otherwise the palette.
    private func escape() {
        if actionsFor != nil { closeActions() } else { close() }
    }

    private func closeActions() {
        withAnimation(PaletteBar.grow) { actionsFor = nil }
        // Not at once: the Escape that closed Actions is still being handled, and would reach the field and close the palette.
        Task { focus = .field }
    }

    private func actions(for row: Entry) -> [PaletteAction] {
        guard let id = row.item, let item = library.item(id) else { return PaletteAction.forCommand }
        return PaletteAction.forItem(
            isFile: item.isFile, isFavorite: item.isFavorite, isActive: item.state == .active)
    }

    /// Does what the action says through the same path as the menus, once the palette is put away.
    private func actionsShown(for row: Entry) -> [PaletteAction] {
        PaletteAction.filtered(actions(for: row), by: actionsQuery)
    }

    /// The Actions field, which puts the highlight back on the first action whenever its words change.
    private var actionsField: Binding<String> {
        Binding { actionsQuery } set: {
            actionsQuery = $0
            actionsHighlighted = 0
        }
    }

    private func performHighlighted(on row: Entry) {
        let shown = actionsShown(for: row)
        guard !shown.isEmpty else { return }
        perform(shown[min(actionsHighlighted, shown.count - 1)], on: row)
    }

    private func perform(_ action: PaletteAction, on row: Entry) {
        guard let id = row.item, let item = library.item(id) else {
            if action.kind == .run { run([row], at: 0) }
            return
        }
        switch action.kind {
        case .open, .run:
            run([row], at: 0)
        case .openInNewWindow:
            close()
            ItemWindows.open(library.idsForWindows([id])) { openWindow(value: $0) }
        case .copyLink:
            close()
            Task {
                if let link = await library.bodyLink(to: id, in: nil) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                } else {
                    library.notices.tell(String(localized: "Can’t Copy Link"), String(localized: "This item isn’t ready to link yet. Try again once its copy has loaded."))
                }
            }
        case .addToFavorites, .removeFromFavorites:
            close()
            library.setFavorite([id], action.kind == .addToFavorites, undoManager: undoManager)
        case .versionHistory:
            close(returningFocus: false)
            reveal(item)
            details?.showHistory(of: id, in: library)
        case .delete:
            close()
            library.deleteAfterSaving([id], undoManager: undoManager, asking: details)
        }
    }

    // MARK: What it offers

    /// The commands, places and items that answer the query, in sections. The commands are built each time, since
    /// what they offer changes under an open palette. The titles are ranked first and an entry is built only for each
    /// of the best `PaletteMatch.listLimit` items, never for every item in the library.
    private func matching(_ basis: Basis) -> [Section] {
        let commands = commands
        let fixed = commands + places
        let fixedTitles = fixed.map(\.title)
        let (recent, itemTitles, leftOutItems, leftOutTitles) = filteredItems(basis)
        let typed = isTyped
        let key = Ranking(basis: basis, query: query, fixedTitles: fixedTitles)
        let picks: [PaletteMatch.Pick]
        let scores: [Int]
        if let held = listing.ranking, held.key == key {
            (picks, scores) = (held.picks, held.scores)
        } else {
            let scored = titles.scoredPicks(fixed: fixedTitles, items: typed ? itemTitles : [], query)
            picks = scored.map(\.pick)
            scores = scored.map(\.score)
            listing.ranking = (key, picks, scores)
        }
        if typed, !leftOutItems.isEmpty {
            if listing.leftOutMatches?.key != key {
                listing.leftOutMatches = (key, titles.ranked(leftOutTitles, query).map { leftOutItems[$0] })
            }
        } else {
            listing.leftOutMatches = nil
        }
        let sections = PaletteSections.forCommands(picks: picks, scores: scores, typed: typed, groups: commands.map(\.group), recentCount: recent.count)
        return sections.map { section in
            Section(kind: section.kind, rows: section.rows.map { pick in
                switch pick {
                case .fixed(let index): fixed[index]
                case .item(let index): itemEntry(recent[index])
                case .searchItems: searchItemsEntry
                }
            })
        }
    }

    private func refreshSearch() {
        guard mode == .search, isTyped else {
            setSearched(.none, leftOut: .none)
            return
        }
        setSearched(library.search(query, narrowedBy: askedNarrowing), leftOut: askedLeftOut)
    }

    /// The search as asked: with what is left out, unless Show asked once for everything.
    private var askedNarrowing: SearchNarrowing {
        var asked = narrowing
        if showsLeftOut { asked.leaveOut = SearchLeaveOut() }
        return asked
    }

    /// What is left out and also matches, read only while a line would say so.
    private var askedLeftOut: SearchResults {
        showsLeftOut ? .none : library.searchLeftOut(query, narrowedBy: narrowing)
    }

    private func setSearched(_ results: SearchResults, leftOut found: SearchResults) {
        searched = results
        leftOut = found
        applyFilters(to: results, leftOut: found)
    }

    private func applyFilters(to results: SearchResults, leftOut found: SearchResults) {
        let rest = filterState.filters.afterSearch
        searchedItems = searchOrder.ordered(rest.apply(to: results.items, now: library.now()))
        leftOutItems = rest.apply(to: found.items, now: library.now())
    }

    /// Keeps `searched` current for the query: the library's answer arrives later through its observed state, so each
    /// run reads it under observation and waits for the next change.
    private func watchSearch() async {
        guard mode == .search, isTyped else { return }
        let words = query
        let asked = askedNarrowing
        let counted = showsLeftOut
        let leaving = narrowing
        while !Task.isCancelled {
            let (changes, signal) = AsyncStream.makeStream(of: Void.self)
            let (results, found) = withObservationTracking {
                (library.search(words, narrowedBy: asked), counted ? SearchResults.none : library.searchLeftOut(words, narrowedBy: leaving))
            } onChange: {
                signal.yield()
                signal.finish()
            }
            setSearched(results, leftOut: found)
            for await _ in changes { break }
        }
    }

    /// What the palette says when it lists nothing. A search from a copy that is filling or behind never says nothing
    /// matches, since what matches may not have arrived (the rule `SearchEmptyState` follows in the window).
    enum EmptyAnswer: Equatable { case noResults, stillLooking }

    static func emptyAnswer(searching: Bool, results: SearchResults) -> EmptyAnswer {
        searching && results.isIncomplete ? .stillLooking : .noResults
    }

    /// The most a search lists.
    static let searchLimit = 50

    /// What a search lists: the best matches, in the order the library ranked them. Sorting them by date would
    /// push a strong old match out past the limit.
    static func listed(_ items: [Item]) -> [Item] {
        Array(items.prefix(searchLimit))
    }

    /// Items whose text or title has what was typed, best match first, with the items named by the words typed
    /// apart from those that hold them in the text; or the most recently edited before anything is typed.
    private var found: [Section] {
        let results = isTyped ? searched : nil
        let items = results == nil ? Array(filteredItems(basis).items.prefix(12)) : Self.listed(searchedItems)
        let now = library.now()
        let entries = items.map { item in
            // An excerpt that is the title says nothing the title does not, so the preview stands.
            let excerpt = results?.excerpts[item.id].flatMap { $0.plainText == item.name ? nil : $0 }
            return Entry(
                id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
                snippet: item.preview.isEmpty ? about(item) : item.preview, excerpt: excerpt,
                date: DateDisplay.text(of: item.modified, place: .list, format: dateFormat, now: now),
                icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true
            ) {
                reveal(item)
            }
        }
        return PaletteSections.forSearch(rows: entries, typed: isTyped) { entry in
            PaletteMatch.matchRange(in: entry.title, query) != nil
        }
    }

    /// A search row's second line for an item with no text of its own: its type, or Inbox, and the collections it is
    /// in, so every row in Search Items has two lines.
    private func about(_ item: Item) -> String {
        let place = library.placeLabel(of: item)
        let collections = item.collectionIDs.compactMap { library.item($0)?.displayTitle }
        guard !collections.isEmpty else { return place }
        return String(localized: "\(place) in \(collections.formatted(.list(type: .and)))", comment: "A search row's second line: an item's type, then the collections it is in.")
    }

    private var commands: [Entry] {
        // Writing and Version History act on notes; a file selected takes neither.
        let everything = browser.selectedHeaderItems(in: library)
        let selected = everything.filter { !$0.isFile }
        let one = browser.selection.count == 1 && selected.count == 1 ? selected.first : nil
        let hasVisibleEditor = browser.showsPage && one?.id == editor.pageItemID && editor.hasItem
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, in group: PaletteSections.CommandGroup, id: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: id ?? "command:" + title, title: title, icon: .symbol(systemImage), shortcut: shortcut, group: group, action: action))
        }

        // The page keeps ⌘[ and ⌘] while it has the keyboard (see AppCommands), so the palette does not suggest them.
        func historyKey(_ key: String) -> String? { returnFocus == .page ? nil : key }

        if library.isLoaded {
            add(String(localized: "Search List"), "magnifyingglass", keys(.searchList), in: .edit) { browser.focusRequest = .search }
            let modes = browser.showsSidebarIndex ? [] : browser.availableViewModes(in: library)
            func addLayout(_ mode: ItemViewMode, _ title: String, _ systemImage: String, _ command: ShortcutCommand) {
                if modes.contains(mode) { add(title, systemImage, keys(command), in: .view) { browser.viewMode = mode } }
            }
            addLayout(.list, String(localized: "View as List"), "list.bullet", .viewAsList)
            addLayout(.gallery, String(localized: "View as Gallery"), "square.grid.2x2", .viewAsGallery)
            addLayout(.table, String(localized: "View as Table"), "tablecells", .viewAsTable)
            addLayout(.board, String(localized: "View as Board"), "rectangle.split.3x1", .viewAsBoard)
            addLayout(.timeline, String(localized: "View as Timeline"), ItemViewMode.timeline.symbol, .viewAsTimeline)
            addLayout(.calendar, String(localized: "View as Calendar"), ItemViewMode.calendar.symbol, .viewAsCalendar)
            if browser.stackableType(in: library) != nil {
                let isOn = browser.stacksSubtypes(in: library)
                add(isOn ? String(localized: "Show This Type Only") : String(localized: "Include Subtypes"), IncludeSubtypes.symbol, in: .view) {
                    browser.setStacksSubtypes(!isOn, in: library)
                }
            }
            if browser.isCollectionItemPresented {
                add(String(localized: browser.viewMode.backTitle), "chevron.backward", historyKey("⌘["), in: .go) { browser.returnToCollection() }
            } else if !browser.usesCollection {
                if browser.canGoBack(in: library) {
                    add(String(localized: "Back"), "chevron.backward", historyKey("⌘["), in: .go) { browser.go(.back, in: library) }
                }
                if browser.canGoForward(in: library) {
                    add(String(localized: "Forward"), "chevron.forward", historyKey("⌘]"), in: .go) { browser.go(.forward, in: library) }
                }
            }
            if browser.isModalPresented {
                let neighbors = browser.modalNeighbors(in: library, order: order)
                if neighbors.previous != nil {
                    add(String(localized: "Previous Item"), "chevron.up", "⌥⌘↑", in: .go) { browser.moveModal(.previous, in: library, order: order) }
                }
                if neighbors.next != nil {
                    add(String(localized: "Next Item"), "chevron.down", "⌥⌘↓", in: .go) { browser.moveModal(.next, in: library, order: order) }
                }
                add(String(localized: "Close Modal"), "xmark", in: .go) { browser.closeModal() }
            }
            if let libraries {
                add(String(localized: "Export Layouts…"), "square.and.arrow.up", in: .looks) { LooksFiles.export(from: libraries) }
                add(String(localized: "Import Layouts…"), "square.and.arrow.down", in: .looks) { LooksFiles.importLooks(into: libraries) }
            }
            // An image's or a PDF's page holds ⌘+, ⌘− and ⌘0 for the file, so the text sizes are not offered then
            // (`FileViewCommand`).
            if let fileView = browser.showsPage ? details?.fileViewing(of: browser.selection.count == 1 ? browser.selection.first : nil) : nil {
                for command in FileViewCommand.offered(for: fileView.kind) where command.isEnabled(on: fileView) {
                    add(String(localized: command.title), command.systemImage, keys(command.shortcutCommand), in: .view) { command.perform(on: fileView) }
                }
            } else {
                // The palette holds the keyboard itself, so the page counts as focused where it was when the palette opened.
                let zoom = TextZoom.acting(pageFocused: returnFocus == .page)
                let size = UserDefaults.standard.object(forKey: zoom.key) as? Int ?? zoom.defaultSize
                if zoom.size(after: .bigger, from: size) != nil {
                    add(String(localized: "Make Text Bigger"), "textformat.size.larger", keys(.makeTextBigger), in: .textSize) { zoom.apply(.bigger) }
                }
                if zoom.size(after: .smaller, from: size) != nil {
                    add(String(localized: "Make Text Smaller"), "textformat.size.smaller", keys(.makeTextSmaller), in: .textSize) { zoom.apply(.smaller) }
                }
                add(String(localized: "Actual Size"), "textformat.size", keys(.actualSize), in: .textSize) { zoom.apply(.actual) }
            }
            entries.append(Entry(id: "command:newItem", title: String(localized: "New Item"), icon: .symbol("plus"), shortcut: keys(.newItem),
                                 takesFocus: true) {
                browser.openQuickAdd(remembered: lastType, in: library)
            })
            for type in QuickAdd.types(in: library) {
                entries.append(Entry(id: "command:new:" + type.id.rawValue, title: String(localized: "New \(type.label)"),
                                     icon: .type(library.catalogue.icon(for: type.id)), takesFocus: true, group: nil) {
                    browser.openQuickAdd(typeID: type.id.rawValue, in: library)
                })
            }
            // After New Item and the typed ones, so the commands "new" finds lead with New Item.
            add(String(localized: "New Window"), "macwindow.badge.plus", keys(.newWindow), in: .file) { openWindow(id: MarfaMacApp.mainWindowID) }
            if let host, host.canRefresh {
                add(String(localized: "Refresh"), "arrow.clockwise", keys(.refresh), in: .file) { host.refresh() }
            }
            if browser.selection.count == 1, let details {
                add(details.isPresented ? String(localized: "Hide Details") : String(localized: "Show Details"), "sidebar.right", keys(.toggleDetails), in: .view) { details.isPresented.toggle() }
            }
        }
        let search = String(localized: "Search Items")
        entries.append(Entry(id: "command:" + search, title: search, icon: .symbol("magnifyingglass"), shortcut: keys(.searchItems), takesFocus: true, group: .edit) {
            browser.palette = .search
        })

        #if DEBUG
        // Dev-only and not a toolbar action, so it is not localized and has no toolbar button or shortcut.
        add("Show Tuning Panel", "slider.horizontal.3", in: .debug) { openWindow(id: TuningPanel.windowID) }
        #endif

        if let one, one.isWritable {
            if hasVisibleEditor {
                for format in [Format.title, .heading, .subheading, .heading4, .heading5, .heading6, .body, .bold, .italic,
                               .strikethrough, .highlight, .code, .link, .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
                where format != .table || !editor.caret.inTable {
                    add(ShortcutCommand.format(format).title, "textformat", keys(.format(format)), in: .format) { editor.apply(format) }
                }
            }
        }
        // The same commands, titles and rules as the menu bar and the More menu (`ItemCommand`).
        let itemContext = ItemCommandContext(library: library, ids: browser.selection, browser: browser, editor: editor, details: details)
        for command in ItemCommand.allCases where command.isEnabled(in: itemContext) {
            let sourceMode = command == .toggleSource ? editor.caret.sourceMode : nil
            add(String(localized: command.title(in: itemContext, sourceMode: sourceMode)), command.systemImage, keys(command.shortcutCommand), in: command.paletteGroup) {
                command.perform(in: itemContext, editor: editor) { openWindow(value: $0) }
            }
        }
        let shareID = one?.id
        let shareFile = shareID.flatMap { browser.fileURL(of: $0) }
        // Presence only. The text is read when Share is chosen, so opening the palette does not follow a keystroke.
        let canShare = shareFile != nil || (shareID.map { library.bodyText($0) != nil } ?? false)
        if canShare {
            add(String(localized: "Share…"), "square.and.arrow.up", in: .file) {
                let item = shareID.flatMap { library.item($0) }
                ItemShare(item: item, fileURL: shareFile ?? shareID.flatMap { browser.fileURL(of: $0) }, in: library)
                    .present(near: hasVisibleEditor ? editor.webView : nil)
            }
        }

        if let details, details.history != nil {
            add(String(localized: "Exit Version History"), "xmark", in: .file) { details.leaveHistory() }
            if details.history?.canRestore(in: library) == true {
                add(String(localized: "Restore Version"), "arrow.uturn.backward", in: .file) {
                    details.restoreFromHistory(in: library, undoManager: undoManager)
                }
            }
        } else if let details, selected.count == 1, let only = selected.first {
            add(String(localized: "Version History…"), "clock.arrow.circlepath", in: .file) {
                details.showHistory(of: only.id, in: library)
            }
        }
        if let details, details.isCustomizingLayout {
            add(String(localized: "Finish Customizing"), "slider.horizontal.3", in: .view) { details.endLayout() }
        } else if let details, let only = one, details.canBeginLayout(for: only) {
            add(String(localized: "Customize Layout…"), "slider.horizontal.3", in: .view) { details.beginLayout() }
        }
        // These act on the whole selection, files too; what an item can't take is left alone and the person is told.
        let ids = Set(everything.map(\.id))
        let active = everything.filter { $0.state == .active }
        if !everything.isEmpty, everything.allSatisfy({ $0.state == .trashed }) {
            add(String(localized: "Recover"), "arrow.uturn.backward", in: .file) { library.recover(ids, undoManager: undoManager) }
        } else if !everything.isEmpty {
            let allFavorites = !active.isEmpty && active.allSatisfy(\.isFavorite)
            if !active.isEmpty {
                add(allFavorites ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"), allFavorites ? "star.slash" : "star", in: .file) {
                    library.setFavorite(ids, !allFavorites, undoManager: undoManager)
                }
            }
            if let details, library.canTag(ids) {
                add(String(localized: "Add Tag…"), "tag", in: .file) {
                    details.tagRequest = TagRequest(ids: ids, undoManager: undoManager)
                }
            }
            if let details, library.offersTypeChange(for: ids) {
                add(String(localized: "Change Type…"), "square.on.square", in: .file) {
                    details.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
                }
            }
            add(String(localized: "Delete"), "trash", in: .file) {
                library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
            }
        }
        let members = library.collectionMembers(browser.selection)
        if !members.isEmpty {
            if let details, !library.collections.isEmpty {
                add(String(localized: "Add to Collection…"), "rectangle.stack.badge.plus", in: .file) {
                    details.collectionPick = CollectionPickRequest(ids: browser.selection, undoManager: undoManager)
                }
            }
            for collection in library.collections(holding: members) {
                add(String(localized: "Remove from “\(collection.displayTitle)”"), "rectangle.stack.badge.minus", in: .file, id: "command:removeFrom:\(collection.id)") {
                    library.removeFromCollection(browser.selection, collection.id, undoManager: undoManager)
                }
            }
        }

        if library.isLoaded {
            for command in ViewOptionCommand.commands(for: browser, in: library) {
                add(command.title, command.systemImage, keys(command.key), in: command.group, action: command.action)
            }
            for type in browser.layoutTypes(in: library) {
                add(String(localized: "Edit Layout of \(type.plural)…"), "slider.horizontal.3", in: .view, id: "command:editLayout:\(type.id)") {
                    browser.showLayouts(of: type)
                }
            }
            for command in SavedViewCommand.commands(for: browser, in: library, order: order) {
                add(command.title, command.systemImage, in: .view, action: command.action)
            }
            if browser.showsViewPanel {
                add(String(localized: "Finish Editing View"), "checkmark", in: .view) {
                    Task { await browser.finishViewPanel(in: library, order: order) }
                }
            }
            if browser.customizesSidebar {
                add(String(localized: "Finish Customizing Sidebar"), "checkmark", in: .view) { browser.customizesSidebar = false }
            } else {
                add(String(localized: "Customize Sidebar…"), "sidebar.squares.leading", in: .view) { browser.customizesSidebar = true }
            }
            if let indexActions {
                if let rename = indexActions.rename {
                    add(String(localized: "Rename Source…"), "pencil", in: .file, action: rename)
                }
                if let chooseMark = indexActions.chooseMark {
                    add(String(localized: "Choose Source Mark…"), "face.smiling", in: .file, action: chooseMark)
                }
                if let delete = indexActions.delete {
                    add(String(localized: "Delete Collection…"), "trash", in: .file, action: delete)
                }
            }
        }
        if fullWidth {
            add(String(localized: "Standard Width"), "arrow.left.and.right", in: .view) { fullWidth = false }
        } else {
            add(String(localized: "Full Width"), "arrow.left.and.right", in: .view) { fullWidth = true }
        }
        let settingsTitle = String(localized: "Settings…")
        entries.append(Entry(id: "command:" + settingsTitle, title: settingsTitle, icon: .symbol("gearshape"), shortcut: keys(.settings), takesFocus: true, group: .settings) {
            browser.showSettings()
        })
        for page in SettingsPage.all {
            let title = String(localized: "Settings: \(page.title)")
            entries.append(Entry(id: "command:" + title, title: title, icon: .symbol(page.symbol), takesFocus: true, group: .settings) {
                browser.showSettings(page)
            })
        }
        for item in HelpItem.allCases {
            add(String(localized: item.title), item.systemImage, in: .help) {
                item.perform(openSettings: { browser.showSettings($0) }, openURL: openURL)
            }
        }
        // Whatever else shares a title, such as two table columns of one label, is told apart by its place.
        let distinctIDs = PaletteSections.distinct(entries.map(\.id))
        for index in entries.indices { entries[index].id = distinctIDs[index] }
        return entries
    }

    private var places: [Entry] {
        browser.paletteIndex(in: library).places.map { place in
            Entry(id: "place:\(place.item)", title: place.title ?? library.name(of: place.item), detail: String(localized: "Show"), icon: place.icon) {
                browser.show(place.item, in: library, order: order)
                browser.focusRequest = .list
            }
        }
    }

    static let searchItemsID = "command:searchItemsFor"

    /// The last row under Items: the same words, searched in the text of every item.
    private var searchItemsEntry: Entry {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Entry(id: Self.searchItemsID, title: String(localized: "Search Items for “\(typed)”"), icon: .symbol("magnifyingglass"),
                     shortcut: keys(.searchItems), takesFocus: true) {
            browser.paletteSeed = typed
            browser.palette = .search
        }
    }

    /// An item by title, with its type.
    private func itemEntry(_ item: Item) -> Entry {
        Entry(id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
              icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true) {
            reveal(item)
        }
    }

    private func reveal(_ item: Item) {
        browser.reveal(item, in: library, order: order)
    }

    /// The key the person has given a menu command, as the menus write it, for the row that runs the command.
    private func keys(_ command: ShortcutCommand?) -> String? {
        command.flatMap { shortcuts?.display(for: $0) }
    }
}
