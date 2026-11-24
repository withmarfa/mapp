import SwiftUI
import UniformTypeIdentifiers

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the items by title. ⇧⌘P: the
/// same field searching the text of every item, each found item shown with the words around what was found. Both
/// list in sections, and what a row can do is in Actions (⌘J). Arrow keys choose, Return runs, and Escape or
/// a click outside puts it away. The commands are only what could be done now, so what it lists is what the menus
/// have enabled.
struct CommandPalette: View {
    @CurrentLibrary var library
    @FocusedValue(\.detailsPresentation) var details
    @FocusedValue(\.indexActions) var indexActions
    @Environment(\.undoManager) var undoManager
    @Environment(\.openWindow) var openWindow
    @Environment(\.openURL) var openURL
    @Environment(ShortcutBindings.self) private var shortcuts: ShortcutBindings?
    @Environment(MarfaHost.self) var host: MarfaHost?
    @Environment(Libraries.self) var libraries: Libraries?
    @StoredOrder var order
    @AppStorage(PageKey.fullWidth) var fullWidth = PageStyle().fullWidth
    @AppStorage(QuickAdd.lastTypeKey) var lastType = ""
    @AppStorage(DateFormat.key) var dateFormat = DateFormat.standard
    @AppStorage(SearchOptions.includesArchivedKey) var includesArchived = SearchOptions.includesArchivedStandard
    @AppStorage(SearchOptions.includesInboxKey) var includesInbox = SearchOptions.includesInboxStandard
    @AppStorage(SearchOptions.orderKey) var searchOrder = SearchOptions.Order.standard
    @AppStorage(SearchOptions.showsSnippetsKey) private var showsSnippets = SearchOptions.showsSnippetsStandard
    let browser: Browser
    let editor: EditorController
    let mode: Browser.Palette
    @State private(set) var query = ""
    @State private var highlighted = 0
    /// Moves the list to a row the keyboard chose, never one the pointer is over, which would slide rows under it.
    @State private var scrollTarget: String?
    /// The row Actions is open for, by its identifier, or nil while it is shut.
    @State private var actionsFor: String?
    @State private var showsFilters = false
    /// The filter row's height, which the list gives up while the row shows, so showing filters never grows the palette.
    @State private var filterRowHeight: CGFloat = 0
    /// The filters and the panel open for one, which last until the palette is put away.
    @State private(set) var filterState = PaletteFilterState()
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private(set) var returnFocus: Browser.Pane = .list
    /// Every item's title folded once while the palette is open, so a keystroke folds only what was typed.
    @State private(set) var titles = PaletteMatch.Titles()
    /// What the palette lists for the query as it stands, kept across the arrow keys and anything else that runs the
    /// body again. Nothing here is observed.
    @State private(set) var listing = Listing()
    @FocusState private var focus: PaletteFocus?
    /// What the Actions field holds and which action is chosen, kept here since the arrow keys reach the palette.
    @State private var actionsQuery = ""
    @State private var actionsHighlighted = 0
    /// What Search Items found for the query, asked once per query and again only when its answer changes (`watchSearch`),
    /// never by the body, which the arrow keys and the pointer run again and again.
    @State var searched = SearchResults.none
    /// What `searched` lists once the filters have narrowed it: filtered when the answer or the filters change, never by the body.
    @State var searchedItems: [Item] = []
    /// What the same search finds among the items left out of search, after the filters, which the last line counts.
    @State var leftOut = SearchResults.none
    @State var leftOutItems: [Item] = []
    /// Whether Show asked for this search once with nothing left out. A new search leaves out again.
    @State private(set) var showsLeftOut = false

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

    typealias Entry = PaletteEntry
    typealias Section = PaletteSections.Section<PaletteEntry>

    /// The key the person has given a menu command, as the menus write it, for the row that runs the command.
    func keys(_ command: ShortcutCommand?) -> String? {
        command.flatMap { shortcuts?.display(for: $0) }
    }

    var body: some View {
        let sections = shown()
        let rows = sections.flatMap(\.rows)
        let chosen = rows.indices.contains(highlighted) ? highlighted : max(rows.count - 1, 0)
        let target = actionsFor.flatMap { id in rows.first { $0.id == id } }
        VStack(spacing: 0) {
            searchField(sections)
            if mode == .search, showsFilters {
                PaletteFilterRow(state: filterState)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { filterRowHeight = $0 }
            }
            results(sections, rows: rows, chosen: chosen, target: target)
        }
        .floatingPanelSurface(width: 680)
        .onKeyPress(.downArrow) { moveDown(rows, chosen: chosen, target: target) }
        .onKeyPress(.upArrow) { moveUp(rows, chosen: chosen, target: target) }
        .onKeyPress(.escape) {
            escape()
            return .handled
        }
        .background { actionShortcuts(for: target) }
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

    private func searchField(_ sections: [Section]) -> some View {
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
    }

    private func moveDown(_ rows: [Entry], chosen: Int, target: Entry?) -> KeyPress.Result {
        if let target {
            actionsHighlighted = min(actionsHighlighted + 1, max(PaletteAction.filtered(actions(for: target), by: actionsQuery).count - 1, 0))
            return .handled
        }
        highlighted = min(chosen + 1, max(rows.count - 1, 0))
        scrollTarget = rows.indices.contains(highlighted) ? rows[highlighted].id : nil
        return .handled
    }

    private func moveUp(_ rows: [Entry], chosen: Int, target: Entry?) -> KeyPress.Result {
        if target != nil {
            actionsHighlighted = max(actionsHighlighted - 1, 0)
            return .handled
        }
        highlighted = max(chosen - 1, 0)
        scrollTarget = rows.indices.contains(highlighted) ? rows[highlighted].id : nil
        return .handled
    }

    // Shortcut buttons, since a field takes most Command keys before a key press handler sees them. Out of sight, but
    // in the window's key equivalents. While Actions is open the palette owns every Actions shortcut: one the row
    // does not offer, or the field has filtered out, does nothing, and never reaches the window's menu.
    @ViewBuilder private func actionShortcuts(for target: Entry?) -> some View {
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
            Task { await library.copyLink(of: id) }
        case .copyWikiLink:
            close()
            Task {
                if let link = await library.bodyLink(to: id, in: nil) {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link, forType: .string)
                } else {
                    library.notices.tell(String(localized: "Can’t Copy Wiki Link"), String(localized: "This item isn’t ready to link yet. Try again once its copy has loaded."))
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
}
