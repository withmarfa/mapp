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
    @FocusedValue(\.sidebarVisibility) var sidebarVisibility
    @Environment(\.undoManager) var undoManager
    @Environment(\.openWindow) var openWindow
    @Environment(\.openURL) var openURL
    @Environment(ShortcutBindings.self) private var shortcuts: ShortcutBindings?
    @Environment(MarfaHost.self) var host: MarfaHost?
    @Environment(Libraries.self) var libraries: Libraries?
    @StoredOrder var order
    @AppStorage(PageKey.fullWidth) var fullWidth = PageStyle().fullWidth
    @AppStorage(DateFormat.key) var dateFormat = DateFormat.standard
    @AppStorage(SearchOptions.includesArchivedKey) var includesArchived = SearchOptions.includesArchivedStandard
    @AppStorage(SearchOptions.includesFeedKey) var includesFeed = SearchOptions.includesFeedStandard
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
    /// Search Items' tokens, which last until the palette is put away. Nothing here is saved.
    @State private(set) var tokens = PaletteTokens()
    /// The token a click chose, which Delete takes away.
    @State private var selectedToken: FilterClause?
    /// Whether an arrow key has moved the choice since the words last changed. A list of nothing but offers has no choice
    /// until it has, so Return makes the item and not a token.
    @State private var arrowed = false

    /// Whether a row is chosen: always where there are results, and among offers alone only once an arrow has moved to one.
    private func hasChoice(_ rows: [Entry]) -> Bool {
        arrowed || rows.contains { !$0.isOffer }
    }

    /// Makes `clause` a token and puts the words that offered it away.
    func addToken(_ clause: FilterClause) {
        tokens.clauses.append(clause)
        query = ""
    }
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

    init(browser: Browser, editor: EditorController, mode: Browser.Palette) {
        self.browser = browser
        self.editor = editor
        self.mode = mode
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
        // The type token is part of the search, so a change to it asks again; the others narrow what was found.
        .onChange(of: tokens) { old, new in
            highlighted = 0
            scrollTarget = nil
            if old.typeClause != new.typeClause {
                refreshSearch()
            } else {
                applyFilters(to: searched, leftOut: leftOut)
            }
        }
        .onChange(of: selectedToken) { if selectedToken != nil { focus = .field } }
        .onChange(of: query) {
            selectedToken = nil
            highlighted = 0
            arrowed = false
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
        let results = sections.flatMap(\.rows).filter { !$0.isOffer }
        return HStack(spacing: PaletteMetrics.markGap) {
            // In the rows' mark column, so the typed words start where the titles do, on a circle that overhangs it.
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: PaletteMetrics.markWidth)
                .background {
                    if mode == .search { Circle().fill(.quaternary.opacity(0.6)).frame(width: 30, height: 30) }
                }
            if !tokens.isEmpty {
                PaletteTokenRow(tokens: tokens, library: library, selected: $selectedToken) { clause in
                    tokens.clauses.removeAll { $0 == clause }
                    selectedToken = nil
                    focus = .field
                }
            }
            TextField(fieldPrompt, text: $query)
                .textFieldStyle(.plain)
                .interfaceFont(.title3)
                .focused($focus, equals: .field)
                // Actions holds the keyboard while it is open.
                .disabled(actionsFor != nil)
                // Delete takes the chosen token away, or in an empty field the last, as it does in the list's search.
                .onKeyPress(.delete) {
                    if let chosen = selectedToken {
                        tokens.clauses.removeAll { $0 == chosen }
                        selectedToken = nil
                        return .handled
                    }
                    guard query.isEmpty, !tokens.isEmpty else { return .ignored }
                    tokens.clauses.removeLast()
                    return .handled
                }
                // Read afresh: Return can come before the view is drawn again after the last key.
                .onSubmit {
                    let current = shown().flatMap(\.rows)
                    if !current.contains(where: { !$0.isOffer }) && !arrowed {
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
                if results.isEmpty {
                    // Offers alone fill the body, so the answer is at the field's line then, and in the body otherwise.
                    if !sections.flatMap(\.rows).isEmpty {
                        Text(emptyAnswer)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .accessibilityIdentifier("CommandPaletteCount")
                    }
                    PaletteNewItem(returnMakes: !arrowed, onNew: newItem)
                } else {
                    let count = PaletteSections.resultCount(sections) { $0.id != Self.searchItemsID && !$0.isOffer }
                    Text(count == 1 ? String(localized: "1 result") : String(localized: "\(count) results"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("CommandPaletteCount")
                }
            }
        }
        .padding(.horizontal, PaletteMetrics.markInset)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    /// Whether the copy is still filling, so that what matches may not have arrived.
    private var isLooking: Bool { Self.emptyAnswer(searching: mode == .search, results: searched) == .stillLooking }

    private var emptyAnswer: LocalizedStringKey { isLooking ? "Still Looking" : "No Results" }

    private var fieldPrompt: LocalizedStringKey {
        if mode == .search { tokens.isEmpty ? "Search Items" : "" } else { "Search Commands and Items" }
    }

    private func moveDown(_ rows: [Entry], chosen: Int, target: Entry?) -> KeyPress.Result {
        if let target {
            actionsHighlighted = min(actionsHighlighted + 1, max(PaletteAction.filtered(actions(for: target), by: actionsQuery).count - 1, 0))
            return .handled
        }
        guard !rows.isEmpty else { return .handled }
        // Among offers alone nothing is chosen yet, so the first arrow chooses the first.
        highlighted = hasChoice(rows) ? min(chosen + 1, max(rows.count - 1, 0)) : 0
        arrowed = true
        scrollTarget = rows.indices.contains(highlighted) ? rows[highlighted].id : nil
        return .handled
    }

    private func moveUp(_ rows: [Entry], chosen: Int, target: Entry?) -> KeyPress.Result {
        if target != nil {
            actionsHighlighted = max(actionsHighlighted - 1, 0)
            return .handled
        }
        guard hasChoice(rows) else { return .handled }
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
                    // Nothing found says so, centred, with New Item at the field's line; what was left out is under it.
                    VStack(spacing: 0) {
                        if isTyped { PaletteNoResults(isLooking: isLooking) }
                        leftOutRow
                    }
                } else {
                    list(sections, chosen: chosen, showsBar: hasChoice(rows))
                }
            }
            .safeAreaBar(edge: .bottom, spacing: 0) {
                // Kept in place while Actions is out, so the rows above do not move.
                if hasChoice(rows), let row = rows.indices.contains(chosen) ? rows[chosen] : nil {
                    HStack(alignment: .bottom, spacing: PaletteBar.spacing) {
                        Spacer(minLength: 0)
                        PaletteFooter(
                            openTitle: openTitle(for: row), onOpen: { run(rows, at: chosen) },
                            actionsKeys: row.isOffer ? nil : keys(.paletteActions),
                            onActions: row.isOffer ? nil : { toggleActions(rows, chosen: chosen) })
                    }
                    .opacity(target == nil ? 1 : 0)
                    .allowsHitTesting(target == nil)
                    .padding(PaletteBar.inset)
                }
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

    private func list(_ sections: [Section], chosen: Int, showsBar: Bool) -> some View {
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
                                entry: entry, query: query, isHighlighted: index == chosen && hasChoice(sections.flatMap(\.rows)),
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
            // The last row can scroll clear of the bar that stands over the foot.
            .contentMargins(.bottom, showsBar ? PaletteBar.height + PaletteBar.inset * 2 : 0, for: .scrollContent)
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .frame(maxHeight: PaletteMetrics.resultsHeight)
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
        if row.isOffer { return String(localized: "Add Filter") }
        return row.item == nil ? String(localized: "Run") : String(localized: "Open")
    }

    // MARK: Running

    private func run(_ entries: [Entry], at index: Int? = nil) {
        let index = index ?? highlighted
        guard entries.indices.contains(index) else { return }
        if entries[index].staysOpen {
            entries[index].action()
            return
        }
        close(returningFocus: !entries[index].takesFocus)
        entries[index].action()
        if mode == .search, isTyped, let id = entries[index].item {
            let words = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let editor = editor
            Task { @MainActor in await editor.find(words, in: id) }
        }
    }

    /// What was typed found nothing: a new item opens with the words as its title.
    private func newItem() {
        close(returningFocus: false)
        browser.openNewItem(title: query, in: library)
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
