import SwiftUI
import UniformTypeIdentifiers

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the notes by title. ⇧⌘P: the
/// same field searching the text of every note, each found note shown with the words around what was found. Both
/// list in sections, and what a row can do is in Actions (⌘K again). Arrow keys choose, Return runs, and Escape or
/// a click outside puts it away. The commands are only what could be done now, so what it lists is what the menus
/// have enabled.
struct CommandPalette: View {
    @CurrentLibrary private var library
    @FocusedValue(\.detailsPresentation) private var details
    @Environment(\.undoManager) private var undoManager
    @Environment(\.openWindow) private var openWindow
    @Environment(MarfaHost.self) private var host: MarfaHost?
    @StoredOrder private var order
    @AppStorage(ItemTableColumnLayouts.key) private var storedColumns = Data()
    @AppStorage(PageKey.fullWidth) private var fullWidth = PageStyle().fullWidth
    @AppStorage(OrderKey.sort) private var sort = NoteOrder().sort
    @AppStorage(OrderKey.groupsByDate) private var groupsByDate = NoteOrder().groupsByDate
    @AppStorage(QuickAdd.lastTypeKey) private var lastType = ""
    @AppStorage(DateFormat.key) private var dateFormat = DateFormat.standard
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
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private var returnFocus: Browser.Pane = .list
    /// Every note's title folded once while the palette is open, so a keystroke folds only what was typed.
    @State private var titles = PaletteMatch.Titles()
    /// What the palette lists for the query as it stands, kept across the arrow keys and anything else that runs the
    /// body again. Nothing here is observed.
    @State private var listing = Listing()
    @FocusState private var focus: PaletteFocus?
    /// What the Actions field holds and which action is chosen, kept here since the arrow keys reach the palette.
    @State private var actionsQuery = ""
    @State private var actionsHighlighted = 0
    /// What Search Notes found for the query, asked once per query and again only when its answer changes (`watchSearch`),
    /// never by the body, which the arrow keys and the pointer run again and again.
    @State private var searched = SearchResults.none
    /// The height of the buttons that float over the results, with their margin: what the last row must clear.
    @State private var floatingHeight: CGFloat = 56

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
    }

    /// What is held across runs of the body: the items' titles for a basis, and how the titles ranked for a query.
    /// The commands are never held, since they read the editor, the browser and the host, which change while the
    /// palette is open and are not part of the basis.
    private final class Listing {
        var itemTitles: (basis: Basis, titles: [String])?
        var ranking: (key: Ranking, picks: [PaletteMatch.Pick], scores: [Int])?
    }

    private struct Ranking: Equatable {
        let basis: Basis
        let query: String
        let fixedTitles: [String]
    }

    private var basis: Basis {
        Basis(library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
              mode: mode, returnFocus: returnFocus, selection: browser.selection)
    }

    private var isTyped: Bool { !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(mode == .search ? "Search Notes" : "Search Commands and Notes", text: $query)
                    .textFieldStyle(.plain)
                    .interfaceFont(.title3)
                    .focused($focus, equals: .field)
                    // Actions holds the keyboard while it is open.
                    .disabled(actionsFor != nil)
                    // Read afresh: Return can come before the view is drawn again after the last key.
                    .onSubmit {
                        let current = shown().flatMap(\.rows)
                        if let id = actionsFor, let live = current.first(where: { $0.id == id }) {
                            performHighlighted(on: live)
                        } else {
                            run(current, at: current.indices.contains(highlighted) ? highlighted : max(current.count - 1, 0))
                        }
                    }
                    .onExitCommand { escape() }
                    .accessibilityIdentifier("CommandPaletteField")
                if isTyped {
                    let count = PaletteSections.resultCount(sections) { $0.id != Self.searchNotesID }
                    Text(count == 1 ? String(localized: "1 result") : String(localized: "\(count) results"))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .accessibilityIdentifier("CommandPaletteCount")
                }
            }
            .padding(12)
            if showsFilters {
                PaletteFilterRow()
            }
            Divider()
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
        .onChange(of: query) {
            highlighted = 0
            scrollTarget = nil
            // At once, so Return before the next draw reads the answer for what was typed.
            refreshSearch()
        }
        .task(id: query) { await watchSearch() }
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

    /// The rows, or "No Results", with the filter button, the footer and Actions floating over them.
    private func results(_ sections: [Section], rows: [Entry], chosen: Int, target: Entry?) -> some View {
        ZStack(alignment: .bottom) {
            if rows.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                list(sections, chosen: chosen)
            }
            if actionsFor != nil {
                // A click beside the panel puts it away and keeps the palette.
                Color.clear
                    .contentShape(.rect)
                    .onTapGesture { closeActions() }
            }
            HStack(alignment: .bottom) {
                PaletteFilterButton(count: filterCount, isOn: showsFilters) { showsFilters.toggle() }
                Spacer(minLength: 0)
                if let row = rows.indices.contains(chosen) ? rows[chosen] : nil {
                    PaletteFooter(
                        openTitle: openTitle(for: row), onOpen: { run(rows, at: chosen) },
                        onActions: { toggleActions(rows, chosen: chosen) })
                }
            }
            .padding(10)
            .onGeometryChange(for: CGFloat.self, of: { $0.size.height }) { floatingHeight = $0 }
            if let target {
                PaletteActionsPanel(
                    title: target.title, actions: actions(for: target),
                    perform: { perform($0, on: target) }, submit: { performHighlighted(on: target) }, close: { closeActions() },
                    query: actionsField, highlighted: $actionsHighlighted, focus: $focus
                )
                .padding(.trailing, 10)
                .padding(.bottom, floatingHeight)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
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
                                isSearch: mode == .search
                            ) {
                                if highlighted != index { highlighted = index }
                            } onRun: {
                                run(sections.flatMap(\.rows), at: index)
                            }
                            .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 2)
            }
            // Room under the last row for the buttons that float over the list; a scroll to a row keeps it clear of them.
            .contentMargins(.bottom, floatingHeight, for: .scrollContent)
            .frame(maxHeight: 460)
            .onChange(of: scrollTarget) { if let scrollTarget { proxy.scrollTo(scrollTarget) } }
        }
    }

    /// Filters are not offered yet; the filter row (`PaletteFilterRow`) shows only its add button.
    private var filterCount: Int { 0 }

    private func openTitle(for row: Entry) -> String {
        if row.item == nil { return String(localized: "Run") }
        return mode == .search ? String(localized: "Open at Match") : String(localized: "Open")
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

    private func close(returningFocus: Bool = true) {
        browser.palette = nil
        if returningFocus, browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }

    // MARK: Actions

    private func toggleActions(_ rows: [Entry], chosen: Int) {
        if actionsFor != nil {
            closeActions()
        } else if rows.indices.contains(chosen) {
            actionsFor = rows[chosen].id
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
        actionsFor = nil
        // Not at once: the Escape that closed Actions is still being handled, and would reach the field and close the palette.
        Task { focus = .field }
    }

    private func actions(for row: Entry) -> [PaletteAction] {
        guard let id = row.item, let item = library.item(id) else { return PaletteAction.forCommand }
        return PaletteAction.forItem(
            isFile: item.isFile, isFavorite: item.isFavorite, isActive: item.state == .active,
            openTitle: mode == .search ? String(localized: "Open at Match") : String(localized: "Open"))
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

    /// The commands, places and notes that answer the query, in sections. The commands are built each time, since
    /// what they offer changes under an open palette. The titles are ranked first and an entry is built only for each
    /// of the best `PaletteMatch.listLimit` notes, never for every item in the library.
    private func matching(_ basis: Basis) -> [Section] {
        let commands = commands
        let fixed = commands + places
        let fixedTitles = fixed.map(\.title)
        let recent = browser.paletteIndex(in: library).recent
        let itemTitles: [String]
        if let held = listing.itemTitles, held.basis == basis {
            itemTitles = held.titles
        } else {
            itemTitles = recent.map(\.title)
            listing.itemTitles = (basis, itemTitles)
        }
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
        let sections = PaletteSections.forCommands(picks: picks, scores: scores, typed: typed, commandCount: commands.count, recentCount: recent.count)
        return sections.map { section in
            Section(kind: section.kind, rows: section.rows.map { pick in
                switch pick {
                case .fixed(let index): fixed[index]
                case .item(let index): note(recent[index])
                case .searchNotes: searchNotesEntry
                }
            })
        }
    }

    private func refreshSearch() {
        searched = mode == .search && isTyped ? library.search(query, in: .everywhere) : .none
    }

    /// Keeps `searched` current for the query: the library's answer arrives later through its observed state, so each
    /// run reads it under observation and waits for the next change.
    private func watchSearch() async {
        guard mode == .search, isTyped else { return }
        let words = query
        while !Task.isCancelled {
            let (changes, signal) = AsyncStream.makeStream(of: Void.self)
            searched = withObservationTracking {
                library.search(words, in: .everywhere)
            } onChange: {
                signal.yield()
                signal.finish()
            }
            for await _ in changes { break }
        }
    }

    /// The most a search lists.
    static let searchLimit = 50

    /// What a search lists: the best matches, in the order the library ranked them. Sorting them by date would
    /// push a strong old match out past the limit.
    static func listed(_ results: SearchResults) -> [Item] {
        Array(results.items.prefix(searchLimit))
    }

    /// Items whose text or title has what was typed, best match first, with the notes named by the words typed
    /// apart from those that hold them in the text; or the most recently edited before anything is typed.
    private var found: [Section] {
        let results = isTyped ? searched : nil
        let items = results.map(Self.listed) ?? Array(browser.paletteIndex(in: library).recent.prefix(12))
        let now = library.now()
        let entries = items.map { item in
            // An excerpt that is the title says nothing the title does not, so the preview stands.
            let excerpt = results?.excerpts[item.id].flatMap { $0.plainText == item.name ? nil : $0 }
            return Entry(
                id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
                snippet: item.preview.isEmpty ? nil : item.preview, excerpt: excerpt,
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

    private var commands: [Entry] {
        // Writing and Version History act on notes; a file selected takes neither.
        let everything = browser.selectedItems(in: library)
        let selected = everything.filter { !$0.isFile }
        let one = browser.selection.count == 1 && selected.count == 1 ? selected.first : nil
        let hasVisibleEditor = browser.showsPage && one?.id == editor.noteID && editor.hasNote
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, id: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: id ?? "command:" + title, title: title, icon: .symbol(systemImage), shortcut: shortcut, action: action))
        }

        // The page keeps ⌘[ and ⌘] while it has the keyboard (see AppCommands), so the palette does not suggest them.
        func historyKey(_ key: String) -> String? { returnFocus == .page ? nil : key }

        if library.isLoaded {
            if browser.canSearchList {
                add(String(localized: "Search List"), "magnifyingglass", "⌥⌘F") { browser.focusRequest = .search }
            }
            let modes = browser.showsSidebarIndex ? [] : browser.availableViewModes(in: library)
            func addLayout(_ mode: ItemViewMode, _ title: String, _ systemImage: String, _ shortcut: String) {
                if modes.contains(mode) { add(title, systemImage, shortcut) { browser.viewMode = mode } }
            }
            addLayout(.list, String(localized: "View as List"), "list.bullet", "⌘1")
            addLayout(.gallery, String(localized: "View as Gallery"), "square.grid.2x2", "⌘2")
            addLayout(.table, String(localized: "View as Table"), "tablecells", "⌘3")
            addLayout(.board, String(localized: "View as Board"), "rectangle.split.3x1", "⌘4")
            addLayout(.timeline, String(localized: "View as Timeline"), "calendar", "⌘5")
            if browser.stackableType(in: library) != nil {
                let isOn = browser.stacksSubtypes(in: library)
                add(isOn ? String(localized: "Show This Type Only") : String(localized: "Include Subtypes"), IncludeSubtypes.symbol) {
                    browser.setStacksSubtypes(!isOn, in: library)
                }
            }
            let ordersList = browser.viewMode == .list || browser.viewMode == .gallery
            if ordersList && browser.isSearching && !browser.ordersByRelevance {
                add(String(localized: "Sort by Relevance"), "arrow.up.arrow.down") { browser.orderSearch(byRelevance: true) }
            }
            for choice in NoteSort.allCases where (choice != sort || browser.ordersByRelevance) && ordersList {
                add(String(localized: "Sort by \(String(localized: choice.title))"), "arrow.up.arrow.down") {
                    sort = choice
                    browser.orderSearch(byRelevance: false)
                }
            }
            if sort != .title && !browser.ordersByRelevance && ordersList {
                add(groupsByDate ? String(localized: "Ungroup by Date") : String(localized: "Group by Date"), "calendar") {
                    groupsByDate.toggle()
                }
            }
            if browser.usesCollection {
                if !browser.showsCollection {
                    add(String(localized: browser.viewMode.backTitle), "chevron.backward", historyKey("⌘[")) { browser.returnToCollection() }
                }
            } else {
                if browser.canGoBack(in: library) {
                    add(String(localized: "Back"), "chevron.backward", historyKey("⌘[")) { browser.go(.back, in: library) }
                }
                if browser.canGoForward(in: library) {
                    add(String(localized: "Forward"), "chevron.forward", historyKey("⌘]")) { browser.go(.forward, in: library) }
                }
            }
            if let host, host.canRefresh {
                add(String(localized: "Refresh"), "arrow.clockwise", "⌘R") { host.refresh() }
            }
            // The palette holds the keyboard itself, so the page counts as focused where it was when the palette opened.
            let zoom = TextZoom.acting(pageFocused: returnFocus == .page)
            let size = UserDefaults.standard.object(forKey: zoom.key) as? Int ?? zoom.defaultSize
            if zoom.size(after: .bigger, from: size) != nil {
                add(String(localized: "Make Text Bigger"), "textformat.size.larger", "⌘+") { zoom.apply(.bigger) }
            }
            if zoom.size(after: .smaller, from: size) != nil {
                add(String(localized: "Make Text Smaller"), "textformat.size.smaller", "⌘-") { zoom.apply(.smaller) }
            }
            add(String(localized: "Actual Size"), "textformat.size", "⌘0") { zoom.apply(.actual) }
            entries.append(Entry(id: "command:newItem", title: String(localized: "New Item"), icon: .symbol("plus"), shortcut: "⌘N",
                                 takesFocus: true) {
                browser.openQuickAdd(remembered: lastType, in: library)
            })
            for type in QuickAdd.types(in: library) {
                entries.append(Entry(id: "command:new:" + type.id.rawValue, title: String(localized: "New \(type.label)"),
                                     icon: .type(library.catalogue.icon(for: type.id)), takesFocus: true) {
                    browser.openQuickAdd(typeID: type.id.rawValue, in: library)
                })
            }
            // After New Item and the typed ones, so the commands "new" finds lead with New Item.
            add(String(localized: "New Window"), "macwindow.badge.plus", "⌥⌘N") { openWindow(id: "main") }
            if browser.selection.count == 1, let details {
                add(details.isPresented ? String(localized: "Hide Details") : String(localized: "Show Details"), "sidebar.right", "⌥⌘I") { details.isPresented.toggle() }
            }
        }
        let search = String(localized: "Search Notes")
        entries.append(Entry(id: "command:" + search, title: search, icon: .symbol("magnifyingglass"), shortcut: "⇧⌘P", takesFocus: true) {
            browser.palette = .search
        })

        #if DEBUG
        // Dev-only and not a toolbar action, so it is not localized and has no toolbar button or shortcut.
        add("Show Tuning Panel", "slider.horizontal.3") { openWindow(id: TuningPanel.windowID) }
        #endif

        if let one, one.isWritable {
            if hasVisibleEditor {
                for format in [Format.title, .heading, .subheading, .heading4, .heading5, .heading6, .body, .bold, .italic,
                               .strikethrough, .highlight, .code, .link, .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
                where format != .table || !editor.caret.inTable {
                    let shortcut = format.shortcut.map { Self.symbols($0.modifiers) + String($0.key).uppercased() }
                    add(String(localized: format.title), "textformat", shortcut) { editor.apply(format) }
                }
            }
        }
        // The same commands, titles and rules as the menu bar and the More menu (`ItemCommand`).
        let itemContext = ItemCommandContext(library: library, ids: browser.selection, browser: browser, editor: editor, details: details)
        for command in ItemCommand.allCases where command.isEnabled(in: itemContext) {
            let shortcut = command.shortcut.map { Self.symbols($0.modifiers) + String($0.key.character).uppercased() }
            add(String(localized: command.title(in: itemContext)), command.systemImage, shortcut) {
                command.perform(in: itemContext, editor: editor) { openWindow(value: $0) }
            }
        }
        let single = browser.selection.count == 1 ? browser.selectedItems(in: library).first?.id : nil
        let share = NoteShare(note: one, fileURL: single.flatMap { browser.fileURL(of: $0) }, in: library)
        if share.isAvailable {
            add(String(localized: "Share…"), "square.and.arrow.up") {
                share.present(near: hasVisibleEditor ? editor.webView : nil)
            }
        }

        if let details, details.history != nil {
            add(String(localized: "Exit Version History"), "xmark") { details.leaveHistory() }
            if details.history?.canRestore(in: library) == true {
                add(String(localized: "Restore Version"), "arrow.uturn.backward") {
                    details.restoreFromHistory(in: library, undoManager: undoManager)
                }
            }
        } else if let details, selected.count == 1, let only = selected.first {
            add(String(localized: "Version History…"), "clock.arrow.circlepath") {
                details.showHistory(of: only.id, in: library)
            }
        }
        if let details, details.isCustomizingLayout {
            add(String(localized: "Finish Customizing"), "slider.horizontal.3") { details.endLayout() }
        } else if let details, let only = one, details.canBeginLayout(for: only) {
            add(String(localized: "Customize Layout…"), "slider.horizontal.3") { details.beginLayout() }
        }
        // These act on the whole selection, files too; what an item can't take is left alone and the person is told.
        let ids = Set(everything.map(\.id))
        let active = everything.filter { $0.state == .active }
        if !everything.isEmpty, everything.allSatisfy({ $0.state == .trashed }) {
            add(String(localized: "Recover"), "arrow.uturn.backward") { library.recover(ids, undoManager: undoManager) }
        } else if !everything.isEmpty {
            let allFavorites = !active.isEmpty && active.allSatisfy(\.isFavorite)
            if !active.isEmpty {
                add(allFavorites ? String(localized: "Remove from Favorites") : String(localized: "Add to Favorites"), allFavorites ? "star.slash" : "star") {
                    library.setFavorite(ids, !allFavorites, undoManager: undoManager)
                }
            }
            if let details, library.canTag(ids) {
                add(String(localized: "Add Tag…"), "tag") {
                    details.tagRequest = TagRequest(ids: ids, undoManager: undoManager)
                }
            }
            if let details, library.offersTypeChange(for: ids) {
                add(String(localized: "Change Type…"), "square.on.square") {
                    details.typeChange = TypeChangeRequest(ids: ids, undoManager: undoManager)
                }
            }
            add(String(localized: "Delete"), "trash") {
                library.deleteAfterSaving(ids, undoManager: undoManager, asking: details)
            }
        }
        let members = library.collectionMembers(browser.selection)
        if !members.isEmpty {
            if let details, !library.collections.isEmpty {
                add(String(localized: "Add to Collection…"), "rectangle.stack.badge.plus") {
                    details.collectionPick = CollectionPickRequest(ids: browser.selection, undoManager: undoManager)
                }
            }
            for collection in library.collections(holding: members) {
                add(String(localized: "Remove from “\(collection.displayTitle)”"), "rectangle.stack.badge.minus", id: "command:removeFrom:\(collection.id)") {
                    library.removeFromCollection(browser.selection, collection.id, undoManager: undoManager)
                }
            }
        }

        if library.isLoaded {
            for command in ViewOptionCommand.commands(for: browser, in: library, storedColumns: $storedColumns) {
                add(command.title, command.systemImage, action: command.action)
            }
            for command in SavedViewCommand.commands(for: browser, in: library, order: order) {
                add(command.title, command.systemImage, action: command.action)
            }
        }
        if fullWidth {
            add(String(localized: "Standard Width"), "arrow.left.and.right") { fullWidth = false }
        } else {
            add(String(localized: "Full Width"), "arrow.left.and.right") { fullWidth = true }
        }
        let settingsTitle = String(localized: "Settings…")
        entries.append(Entry(id: "command:" + settingsTitle, title: settingsTitle, icon: .symbol("gearshape"), shortcut: "⌘,", takesFocus: true) {
            browser.showSettings()
        })
        for page in SettingsPage.allCases {
            let title = String(localized: "Settings: \(page.title)")
            entries.append(Entry(id: "command:" + title, title: title, icon: .symbol(page.symbol), takesFocus: true) {
                browser.showSettings(page)
            })
        }
        // Whatever else shares a title, such as two table columns of one label, is told apart by its place.
        let distinctIDs = PaletteSections.distinct(entries.map(\.id))
        for index in entries.indices { entries[index].id = distinctIDs[index] }
        return entries
    }

    private var places: [Entry] {
        browser.paletteIndex(in: library).places.map { place in
            Entry(id: "place:\(place.item)", title: place.title ?? library.name(of: place.item), detail: String(localized: "Show"), icon: place.icon) {
                browser.choose(place.item, in: library, order: order)
                browser.focusRequest = .list
            }
        }
    }

    static let searchNotesID = "command:searchNotesFor"

    /// The last row under Items: the same words, searched in the text of every note.
    private var searchNotesEntry: Entry {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return Entry(id: Self.searchNotesID, title: String(localized: "Search Notes for “\(typed)”"), icon: .symbol("magnifyingglass"),
                     shortcut: "⇧⌘P", takesFocus: true) {
            browser.paletteSeed = typed
            browser.palette = .search
        }
    }

    /// An item by title, with its type.
    private func note(_ item: Item) -> Entry {
        Entry(id: "note:\(item.id)", title: item.displayTitle, detail: library.placeLabel(of: item),
              icon: .type(library.catalogue.icon(for: item.type)), item: item.id, takesFocus: true) {
            reveal(item)
        }
    }

    private func reveal(_ item: Item) {
        browser.reveal(item, in: library, order: order)
    }

    /// Modifier keys as the menus write them.
    private static func symbols(_ modifiers: EventModifiers) -> String {
        (modifiers.contains(.control) ? "⌃" : "") + (modifiers.contains(.option) ? "⌥" : "")
            + (modifiers.contains(.shift) ? "⇧" : "") + (modifiers.contains(.command) ? "⌘" : "")
    }
}
