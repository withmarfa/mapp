import SwiftUI
import UniformTypeIdentifiers

/// ⌘K: one field that reaches the window's commands, the places in the sidebar and the notes by title. ⇧⌘P: the
/// same field searching the text of every note, each found note shown with the words around what was found.
/// Arrow keys choose, Return runs, and Escape or a click outside puts it away. The commands are only what could
/// be done now, so what it lists is what the menus have enabled.
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
    let browser: Browser
    let editor: EditorController
    let mode: Browser.Palette
    @State private var query = ""
    @State private var highlighted = 0
    /// Where the keyboard was before the palette took it, and goes back to once the palette is put away.
    @State private var returnFocus: Browser.Pane = .list
    /// Every note's title folded once while the palette is open, so a keystroke folds only what was typed.
    @State private var titles = PaletteMatch.Titles()
    /// What the palette lists for the query as it stands, kept across the arrow keys and anything else that runs the
    /// body again. Nothing here is observed.
    @State private var listing = Listing()
    @FocusState private var isFieldFocused: Bool

    private struct Entry: Identifiable {
        let id: String
        let title: String
        var detail: String?
        /// The words around what a search found, or an item's preview where nothing was searched for.
        var snippet: String?
        var excerpt: SearchExcerpt?
        let icon: RowIcon
        var shortcut: String?
        /// Another interface takes the keyboard itself, so the note should not regain focus first.
        var takesFocus = false
        let action: () -> Void
    }

    /// Everything that can change what the palette lists, other than the query.
    private struct Basis: Equatable {
        let library: ObjectIdentifier
        let content: Int
        let membership: Int
        let mode: Browser.Palette
        let returnFocus: Browser.Pane
        let selection: Set<ItemID>
    }

    /// The list shown, held until the query or its basis changes, so an arrow key reads it and builds nothing.
    private final class Listing {
        var key: (basis: Basis, query: String)?
        var entries: [Entry] = []
        /// The commands and places, held for a basis; the query then ranks them with the items' titles.
        var fixed: (basis: Basis, entries: [Entry], titles: [String])?
        var itemTitles: (basis: Basis, titles: [String])?
    }

    private var basis: Basis {
        Basis(library: ObjectIdentifier(library), content: library.contentRevision, membership: library.membershipRevision,
              mode: mode, returnFocus: returnFocus, selection: browser.selection)
    }

    private func shown() -> [Entry] {
        let basis = basis
        if let key = listing.key, key.basis == basis, key.query == query { return listing.entries }
        let entries = mode == .search ? found : matching(basis)
        listing.key = (basis, query)
        listing.entries = entries
        return entries
    }

    var body: some View {
        let entries = shown()
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField(mode == .search ? "Search Notes" : "Search Commands and Notes", text: $query)
                    .textFieldStyle(.plain)
                    .interfaceFont(.title3)
                    .focused($isFieldFocused)
                    .onSubmit { run(entries) }
                    .onExitCommand { close() }
                    .accessibilityIdentifier("CommandPaletteField")
            }
            .padding(12)
            Divider()
            if entries.isEmpty {
                Text("No Results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(entries.indices, id: \.self) { index in
                                row(entries[index], isHighlighted: index == highlighted)
                                    .id(index)
                                    .onTapGesture { run(entries, at: index) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 460)
                    .onChange(of: highlighted) { proxy.scrollTo(highlighted) }
                }
            }
        }
        .floatingPanelSurface(width: 520)
        .onKeyPress(.downArrow) {
            highlighted = min(highlighted + 1, max(entries.count - 1, 0))
            return .handled
        }
        .onKeyPress(.upArrow) {
            highlighted = max(highlighted - 1, 0)
            return .handled
        }
        .onKeyPress(.escape) {
            close()
            return .handled
        }
        .onChange(of: query) { highlighted = 0 }
        .onAppear { returnFocus = editor.isFocused ? .page : .list }
        // The field takes the keyboard once the palette is in the window; asked any sooner, the list keeps it.
        .defaultFocus($isFieldFocused, true)
        .task {
            try? await Task.sleep(for: .milliseconds(50))
            isFieldFocused = true
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Command Palette")
    }

    private func row(_ entry: Entry, isHighlighted: Bool) -> some View {
        HStack(spacing: 10) {
            RowIconImage(icon: entry.icon)
                .frame(width: 20)
                .foregroundStyle(isHighlighted ? .white : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 10) {
                    Text(entry.title)
                        .lineLimit(1)
                    if let detail = entry.detail {
                        Text(detail)
                            .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                            .lineLimit(1)
                    }
                }
                if let text = entry.excerpt?.attributed(matchColor: isHighlighted ? .white : .primary) ?? entry.snippet.map({ AttributedString($0) }) {
                    Text(text)
                        .interfaceFont(.callout)
                        .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            if let shortcut = entry.shortcut {
                Text(shortcut)
                    .foregroundStyle(isHighlighted ? .white.opacity(0.8) : .secondary)
            }
        }
        .foregroundStyle(isHighlighted ? .white : .primary)
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(isHighlighted ? Color.accentColor : .clear, in: .rect(cornerRadius: 6))
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isHighlighted ? .isSelected : [])
    }

    // MARK: Running

    private func run(_ entries: [Entry], at index: Int? = nil) {
        let index = index ?? highlighted
        guard entries.indices.contains(index) else { return }
        close(returningFocus: !entries[index].takesFocus)
        entries[index].action()
    }

    private func close(returningFocus: Bool = true) {
        browser.palette = nil
        if returningFocus, browser.focusRequest == nil { browser.focusRequest = returnFocus }
    }

    // MARK: What it offers

    /// The commands and places that answer the query, then the notes, in the order in which equally good matches are
    /// listed. The titles are ranked first and an entry is built only for each of the best `PaletteMatch.listLimit`
    /// notes, never for every item in the library.
    private func matching(_ basis: Basis) -> [Entry] {
        let fixed: [Entry]
        let fixedTitles: [String]
        if let held = listing.fixed, held.basis == basis {
            (fixed, fixedTitles) = (held.entries, held.titles)
        } else {
            fixed = commands + places
            fixedTitles = fixed.map(\.title)
            listing.fixed = (basis, fixed, fixedTitles)
        }
        let recent = browser.paletteIndex(in: library).recent
        let itemTitles: [String]
        if let held = listing.itemTitles, held.basis == basis {
            itemTitles = held.titles
        } else {
            itemTitles = recent.map(\.title)
            listing.itemTitles = (basis, itemTitles)
        }
        let typed = !query.trimmingCharacters(in: .whitespaces).isEmpty
        return titles.picks(fixed: fixedTitles, items: typed ? itemTitles : [], query).map { pick in
            switch pick {
            case .fixed(let index): fixed[index]
            case .item(let index): note(recent[index])
            }
        }
    }

    /// The most a search lists.
    static let searchLimit = 50

    /// What a search lists: the best matches, in the order the library ranked them. Sorting them by date would
    /// push a strong old match out past the limit.
    static func listed(_ results: SearchResults) -> [Item] {
        Array(results.items.prefix(searchLimit))
    }

    /// Items whose text or title has what was typed, best match first, or the most recently edited before anything is.
    private var found: [Entry] {
        let isEmpty = query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let results = isEmpty ? nil : library.search(query, in: .everywhere)
        let items = results.map(Self.listed) ?? Array(browser.paletteIndex(in: library).recent.prefix(12))
        return items.map { item in
            // An excerpt that is the title says nothing the title does not, so the preview stands.
            let excerpt = results?.excerpts[item.id].flatMap { $0.plainText == item.title ? nil : $0 }
            return Entry(
                id: "note:\(item.id)", title: item.title, detail: library.placeLabel(of: item),
                snippet: item.preview.isEmpty ? nil : item.preview, excerpt: excerpt,
                icon: .type(library.catalogue.icon(for: item.type)), takesFocus: true
            ) {
                reveal(item)
            }
        }
    }

    private var commands: [Entry] {
        // Writing and Version History act on notes; a file selected takes neither.
        let everything = browser.selectedItems(in: library)
        let selected = everything.filter { !$0.isFile }
        let one = browser.selection.count == 1 && selected.count == 1 ? selected.first : nil
        let hasVisibleEditor = browser.showsPage && one?.id == editor.noteID && editor.hasNote
        var entries: [Entry] = []
        func add(_ title: String, _ systemImage: String, _ shortcut: String? = nil, action: @escaping () -> Void) {
            entries.append(Entry(id: "command:" + title, title: title, icon: .symbol(systemImage), shortcut: shortcut, action: action))
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
                for format in [Format.title, .heading, .subheading, .body, .bold, .italic, .strikethrough, .code,
                               .codeBlock, .quote, .bulletList, .orderedList, .checklist, .table]
                where format != .table || !editor.caret.inTable {
                    let shortcut = format.shortcut.map { Self.symbols($0.modifiers) + String($0.key).uppercased() }
                    add(String(localized: format.title), "textformat", shortcut) { editor.apply(format) }
                }
            }
        }
        // The same commands, titles and rules as the menu bar and the More menu (`ItemCommand`).
        let itemContext = ItemCommandContext(library: library, ids: browser.selection, browser: browser, editor: editor)
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

        if let details, selected.count == 1, let only = selected.first {
            add(String(localized: "Version History…"), "clock.arrow.circlepath") {
                details.history = VersionHistoryRequest(item: only.id, undoManager: undoManager)
            }
        }
        if let details, let only = one, PageCustomization.isAvailable(for: only) {
            add(String(localized: "Customize Page…"), "slider.horizontal.3") {
                details.pageCustomization = PageCustomizationRequest(item: only.id)
            }
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
                add(String(localized: "Remove from “\(collection.title)”"), "rectangle.stack.badge.minus") {
                    library.removeFromCollection(browser.selection, collection.id, undoManager: undoManager)
                }
            }
        }

        if library.isLoaded {
            for command in ViewOptionCommand.commands(for: browser, in: library, storedColumns: $storedColumns) {
                add(command.title, command.systemImage, action: command.action)
            }
            for command in SavedViewCommand.commands(for: browser, in: library) {
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

    /// An item by title, with its type, or the Inbox for one waiting there.
    private func note(_ item: Item) -> Entry {
        Entry(id: "note:\(item.id)", title: item.title, detail: library.placeLabel(of: item), icon: .type(library.catalogue.icon(for: item.type)), takesFocus: true) {
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
