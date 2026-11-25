import SwiftUI
import UniformTypeIdentifiers

/// A window's toolbar, which a person can change with Customize Toolbar. Each split view the main window mounts keeps a
/// layout of its own (`WindowToolbarLayout`), since the system reshuffles a saved layout when one identifier moves between
/// split views. Nothing else in a window may declare a plain `toolbar`, which turns customization off for the whole window.
///
/// The defaults run Search and View Options, View As, Share and More, and Details at the far right. Save as View… is in
/// View Options and the View menu, never here. In the list Search and View Options are the list column's
/// (`ListToolbar`). `ExtraToolbarItems` start in the tray. Format and the Reader and Original switch are in the page's
/// corner (`ItemCorner`), not here.
struct WindowToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let browser: Browser?
    let items: [Item]
    /// Nil for a file in a window of its own, which has no editor.
    let editor: EditorController?
    let details: DetailsPresentation
    var fileURL: URL?
    /// Whether the list column holds Search and View Options, which otherwise come here.
    var hasListColumn = false
    /// Whether Back stands over the sidebar, which a page opened from a layout then needs no Back of its own beside.
    var hasSidebarBack = false

    var body: some CustomizableToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
        let showsItem = browser?.showsSidebarIndex != true
        let opensFromCollection = browser?.isCollectionItemPresented == true && !hasListColumn
        // A navigation item that is merely hidden still moves the title in a collection, so these two come and go.
        if let browser, opensFromCollection, !hasSidebarBack {
            ToolbarItem(id: "backToCollection", placement: .navigation) {
                // A plain arrow with no label: it goes back to wherever the page was opened from.
                Button("Back", systemImage: "chevron.backward") { browser.returnToCollection() }
                    .labelStyle(.iconOnly)
                    .help("Back")
                    .accessibilityIdentifier("BackToGallery")
            }
            .customizationBehavior(.disabled)
        }
        // In the list the item stays in the toolbar while the page's title is in view and only its text goes, rather
        // than the item being hidden and shown as the page scrolls. A hidden item keeps no place at the detail
        // column's leading edge, so the first time it was shown it could be laid out from the list column's side,
        // under that column's buttons. Both kinds of page that scroll their header away (an item's, and a web page's)
        // report through the window's `DetailsPresentation`, by item, so the title of the item shown before cannot
        // appear for the next. Any other page keeps no header to scroll, so its item is hidden.
        if hasListColumn || browser == nil {
            ToolbarItem(id: "scrolledTitle") {
                ScrolledItemTitle(title: tools.scrolledTitle, icon: tools.scrolledIcon, showsIcon: tools.hasHeaderAway, subtitle: tools.scrolledSubtitle)
            }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
            .hidden((!showsScrolledTitle && !tools.isFocused) || !tools.hasScrollingHeader || browser?.showsCollection == true)
        } else if opensFromCollection, showsScrolledTitle || tools.isFocused, tools.hasHeaderAway {
            ToolbarItem(id: "scrolledTitle", placement: .navigation) {
                ScrolledItemTitle(title: tools.scrolledTitle, icon: tools.scrolledIcon, showsIcon: tools.hasHeaderAway, subtitle: tools.scrolledSubtitle)
            }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
        }
        // The index pages' tabs come into the toolbar once their own have scrolled away.
        if let browser, browser.showsSidebarIndex, !hasListColumn { IndexTabsToolbarItem(browser: browser) }
        ToolbarSpacer(.flexible)
        // A hidden spacer still leaves its gap, so the fixed spacers are not hidden: each stands after a group that
        // shows and before another that does, which keeps one standard gap between groups in every state. They are
        // locked, so they come and go like the items that are.
        // While a view is edited the toolbar keeps to what edits it: its layout is chosen in the panel, and Share and
        // More act on items, not on the view.
        let editsView = browser?.showsViewPanel == true
        let showsViewTools = browser != nil && !hasListColumn && !opensFromCollection
        // A full page opened from a layout has no view options, so no layout to choose.
        let showsViewMode = browser != nil && showsItem && !editsView && !opensFromCollection
        let showsActions = showsItem && !editsView
        let showsDetails = !tools.showsInspector
        let showsAfterViewMode = showsActions || showsDetails
        let showsAfterViewTools = showsViewMode || showsAfterViewMode
        if let browser, browser.showsSidebarIndex, !hasListColumn {
            IndexToolbarItems(browser: browser)
        }
        if let browser, !browser.showsSidebarIndex, !hasListColumn {
            ViewToolbarItems(browser: browser, layout: .item, isHidden: opensFromCollection)
        }
        if browser != nil, !hasListColumn {
            if showsViewTools && showsAfterViewTools { ToolbarSpacer(.fixed).customizationBehavior(.disabled) }
        }
        if let browser {
            ToolbarItem(id: "viewMode") { ViewModeMenu(browser: browser) }
                .hidden(!showsViewMode)
            if showsViewMode && showsAfterViewMode { ToolbarSpacer(.fixed).customizationBehavior(.disabled) }
        }
        ToolbarItem(id: "share") { tools.shareLink }
            .hidden(!showsActions)
        ToolbarItem(id: "more") {
            tools.moreMenu.disabled(items.isEmpty)
        }
        .hidden(!showsActions)
        // With the right sidebar open its own toolbar holds the Details button, which would otherwise join Share and
        // More into one capsule, so the gap stands whether Details is here or over the sidebar.
        if showsActions { ToolbarSpacer(.fixed).customizationBehavior(.disabled) }
        ToolbarItem(id: "details") { tools.detailsButton }
            .hidden(!showsDetails)
        ExtraToolbarItems(tools: tools)
    }
}

/// What a person can add from the tray. Each is a command of the menu bar too. One that cannot act on what is showing
/// dims, as Mail's do, so a layout keeps its shape from view to view.
private struct ExtraToolbarItems: CustomizableToolbarContent {
    let tools: ItemToolbarActions

    var body: some CustomizableToolbarContent {
        if let browser = tools.browser {
            ToolbarItem(id: "historyBack") { HistoryButton(direction: .back, browser: browser) }
                .defaultCustomization(.hidden)
            ToolbarItem(id: "historyForward") { HistoryButton(direction: .forward, browser: browser) }
                .defaultCustomization(.hidden)
        }
        ToolbarItem(id: "favorite") { tools.withUndo { FavoriteButton(ids: tools.ids, undoManager: $0) } }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "addTag") { tools.withUndo { AddTagButton(ids: tools.ids, details: tools.details, undoManager: $0) } }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "quickLook") { tools.command(.quickLook) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "openInNewWindow") { tools.command(.openInNewWindow) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "versionHistory") { VersionHistoryButton(ids: tools.ids, details: tools.details) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "customizeLayout") { CustomizeLayoutButton(ids: tools.ids, details: tools.details) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "addAttachment") { tools.command(.addAttachment) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "toggleSource") { tools.command(.toggleSource) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "print") { tools.command(.print) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "exportPDF") { tools.command(.exportPDF) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "delete") { tools.withUndo { ItemRemoveActions(ids: tools.ids, undoManager: $0, keepsPlace: true) } }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "bold") { FormatToggle(format: .bold, symbol: "bold", tools: tools) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "italic") { FormatToggle(format: .italic, symbol: "italic", tools: tools) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "bulletList") { FormatToggle(format: .bulletList, symbol: "list.bullet", tools: tools) }
            .defaultCustomization(.hidden)
        ToolbarItem(id: "checklist") { FormatToggle(format: .checklist, symbol: "checklist", tools: tools) }
            .defaultCustomization(.hidden)
    }
}

/// Back or Forward through the items a window has shown.
private struct HistoryButton: View {
    @CurrentLibrary private var library
    let direction: SelectionHistory.Direction
    let browser: Browser

    var body: some View {
        switch direction {
        case .back:
            Button("Back", systemImage: "chevron.backward") { browser.go(.back, in: library) }
                .disabled(!browser.canGoBack(in: library))
        case .forward:
            Button("Forward", systemImage: "chevron.forward") { browser.go(.forward, in: library) }
                .disabled(!browser.canGoForward(in: library))
        }
    }
}

/// A style of the Format menu as a button of its own, on while the caret is in that style.
private struct FormatToggle: View {
    let format: Format
    let symbol: String
    let tools: ItemToolbarActions

    var body: some View {
        let editor = tools.editableItem == nil ? nil : tools.editor
        Toggle(isOn: Binding { editor.map { format.isActive(in: $0.caret) } ?? false } set: { _ in editor?.apply(format) }) {
            Label { Text(format.title) } icon: { Image(systemName: symbol) }
        }
        .disabled(editor?.canApply(format) != true)
    }
}

/// The saved toolbars of the main window, one for each split view it mounts. All of a split view's columns name the same
/// one. A layout saved under a name without the sidebar's items (`SidebarToolbar`) would show none of them, so a change to
/// those items changes these names.
enum WindowToolbarLayout {
    static let list = "window.list"
    static let index = "window.index"
    static let items = "window.items"

    static func collection(_ mode: ItemViewMode) -> String { "window.collection.\(mode)" }
}

/// Says when the Customize Toolbar tray of this window opens and closes. Menu commands still reach a window under its
/// tray, so a window holds its shape meanwhile. Only the active window's tray counts: it is where the tray opens from.
struct ToolbarTrayWatch: ViewModifier {
    @Environment(\.appearsActive) private var appearsActive
    @State private var trayWindow: NSWindow?
    let changed: (Bool) -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.willBeginSheetNotification)) { sheet in
                guard appearsActive, let window = sheet.object as? NSWindow, window.toolbar?.customizationPaletteIsRunning == true else { return }
                trayWindow = window
                changed(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEndSheetNotification)) { sheet in
                guard let window = sheet.object as? NSWindow, window === trayWindow else { return }
                trayWindow = nil
                changed(false)
            }
    }
}

/// The title of the item on the page, in the toolbar once the page's header has scrolled away.
struct ScrolledItemTitle: View {
    @Environment(\.colorScheme) private var scheme
    let title: String
    /// The item type's icon id, drawn before the title in the type's color. A type with none gets the generic mark.
    var icon: String?
    /// Whether the title is showing, and so its icon.
    var showsIcon = false
    /// A second, quieter line, as the page's Focus gives under the title.
    var subtitle: String?

    /// The most room a title takes, so a long one never crowds the buttons beside it.
    static let widest: CGFloat = 300

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                if showsIcon {
                    TypeGlyph(id: icon)
                        .font(.system(size: ChipLooks.defaults.chipMarkSize))
                        .foregroundStyle(TypeTone(icon: icon).color(for: scheme))
                        .accessibilityHidden(true)
                }
                Text(title)
                    .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("ScrolledItemTitle")
                    .accessibilityHidden(title.isEmpty)
            }
            if let subtitle {
                Text(subtitle)
                    .interfaceFont(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.tail)
                    .accessibilityIdentifier("ScrolledItemSubtitle")
            }
        }
        .frame(maxWidth: Self.widest, alignment: .leading)
        // The toolbar sizes an item from what it reports, and the title would otherwise report whatever width it
        // was last offered: a stale or still-growing one while the item is placed shows as "14…". Fixed, it always
        // reports the width its own text needs, up to `widest`, which a long title then ends in an ellipsis at.
        .fixedSize(horizontal: true, vertical: false)
    }
}

/// Details above the inspector column, where the system sets a toolbar declared inside the inspector's content, so the
/// inspector can always be closed whatever a person's layout holds, or the view panel's actions while it has the
/// column. It contributes nothing while the inspector is closed, because the system keeps a closed inspector's toolbar
/// and would show a second Details beside the page's.
struct InspectorToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    let details: DetailsPresentation
    let editor: EditorController?
    var browser: Browser?

    var body: some CustomizableToolbarContent {
        if details.isPresented, browser?.isModalPresented != true {
            if let browser, details.isEditingView, let panel = browser.viewPanel {
                ViewPanelToolbar(browser: browser, panel: panel, editor: editor)
            } else {
                // The Items index shows the chosen item in this sidebar, so what acts on it sits above it, as Open comes first.
                if let browser, browser.showsItemsIndex {
                    let items = browser.selectedHeaderItems(in: library)
                    let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: nil, details: details)
                    ToolbarItem(id: "inspectorOpen") {
                        Button("Open") { browser.openSelection() }
                            .disabled(browser.selection.count != 1)
                            .help("Open")
                            .accessibilityIdentifier("OpenItemToolbar")
                    }
                    .customizationBehavior(.disabled)
                    ToolbarItem(id: "inspectorShare") { tools.shareLink.disabled(items.isEmpty) }
                        .customizationBehavior(.disabled)
                    ToolbarItem(id: "inspectorMore") { tools.moreMenu.disabled(items.isEmpty) }
                        .customizationBehavior(.disabled)
                }
                ToolbarItem(id: "inspectorDetails") {
                    DetailsToggle(details: details, editor: editor)
                }
                .customizationBehavior(.disabled)
            }
        }
    }
}

/// The Details button of a toolbar above the inspector: on, because the inspector is open.
struct DetailsToggle: View {
    let details: DetailsPresentation
    let editor: EditorController?

    var body: some View {
        if details.isCustomizingLayout {
            LayoutDoneButton(details: details, editor: editor)
        } else {
            Toggle("Details", systemImage: "sidebar.right", isOn: Binding { details.isPresented } set: { details.isPresented = $0 })
                // Gray while on, as every on button is, rather than the accent color.
                .tint(.secondary)
                .help("Hide Details")
                .accessibilityIdentifier("DetailsToggle")
        }
    }
}

/// Stands in for the Details button while Customize Layout has the right sidebar: the system's prominent button, which
/// finishes the mode, as Escape does and Return does unless the page has the keyboard: the page can still be typed in.
struct LayoutDoneButton: View {
    let details: DetailsPresentation
    let editor: EditorController?

    var body: some View {
        Button("Done") { details.endLayout() }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(editor?.isFocused == true ? nil : .defaultAction)
            .background {
                Button("Finish Customizing") { details.endLayout() }
                    .keyboardShortcut(.cancelAction)
                    .hidden()
            }
            .help("Finish Customizing")
            .accessibilityIdentifier("LayoutDone")
    }
}

struct ItemToolbarActions {
    let library: any ItemLibrary
    let browser: Browser?
    let items: [Item]
    let editor: EditorController?
    let details: DetailsPresentation
    let fileURL: URL?
    /// The selected items that are not files, sorted out once, since a selection can hold every item in the library.
    let pageItems: [Item]

    init(
        library: any ItemLibrary, browser: Browser?, items: [Item], editor: EditorController?, details: DetailsPresentation,
        fileURL: URL? = nil
    ) {
        self.library = library
        self.browser = browser
        self.items = items
        self.editor = editor
        self.details = details
        self.fileURL = fileURL
        pageItems = items.filter { !$0.isFile }
    }
    var showsInspector: Bool { details.isPresented }

    var visibleItem: Item? {
        guard browser?.showsPage != false,
              (browser?.selection.count ?? pageItems.count) == 1, pageItems.count == 1,
              let item = pageItems.first, let editor, editor.hasItem, editor.pageItemID == item.id else { return nil }
        return item
    }

    /// The one item the window's page shows, of any kind.
    private var shownItem: Item? {
        guard browser?.showsPage != false, (browser?.selection.count ?? items.count) == 1, items.count == 1 else { return nil }
        return items.first
    }

    /// The item on the page while it is in Focus, which puts its title in the toolbar from the start, whatever kind
    /// of page it is.
    private var focusedItem: Item? { shownItem.flatMap { details.isFocused(on: $0.id) ? $0 : nil } }

    var isFocused: Bool { focusedItem != nil }

    /// The one item the window's page shows, when it is one whose page scrolls a header away: an item's, or a web
    /// page's.
    private var itemWithScrollingHeader: Item? {
        guard browser?.showsPage != false, (browser?.selection.count ?? items.count) == 1, items.count == 1,
              let item = items.first, library.pageLayout(of: item) != .file else { return nil }
        return item
    }

    var hasScrollingHeader: Bool { itemWithScrollingHeader != nil || isFocused }

    /// Whether that item's page has scrolled its header away, whatever the title says: an item with no title still
    /// brings its toolbar item, with no text.
    var hasHeaderAway: Bool { isFocused || itemWithScrollingHeader.map { details.isHeaderAway(of: $0.id) } == true }

    /// The title the toolbar shows: the item's once its page has scrolled the header away, and nothing before. A
    /// item's is the text it would be written with, as its header shows it; any other page's is the name it shows.
    var scrolledTitle: String {
        if let item = focusedItem { return library.pageLayout(of: item) == .text ? item.title : item.displayTitle }
        guard let item = itemWithScrollingHeader, details.isHeaderAway(of: item.id) else { return "" }
        return library.pageLayout(of: item) == .text ? item.title : item.displayTitle
    }

    /// The icon id of the item's type, shown before the title wherever the title is shown. Nil for a type with no icon.
    var scrolledIcon: String? {
        let item = focusedItem ?? itemWithScrollingHeader.flatMap { details.isHeaderAway(of: $0.id) ? $0 : nil }
        return item.flatMap { library.catalogue.icon(for: $0.type) }
    }

    /// The line under the title in Focus: the item's type, or for a PDF whose pages have been counted, its type and its
    /// page count. Nothing outside Focus, where the scrolled title stands alone.
    var scrolledSubtitle: String? {
        guard let item = focusedItem else { return nil }
        if case .file(let type, _) = item.content, type.conforms(to: .pdf), let pages = details.pages(of: item.id) {
            // Only an attributed string carries out the plural markup.
            return String(AttributedString(localized: "PDF, ^[\(pages) page](inflect: true)").characters)
        }
        return library.catalogue.label(for: item.type)
    }

    /// Formatting acts only on the writable item currently visible in the editor.
    var editableItem: Item? { visibleItem.flatMap { $0.isWritable ? $0 : nil } }

    private var selectedFileURL: URL? {
        guard (browser?.selection.count ?? items.count) == 1,
              let id = browser?.selection.first ?? items.first?.id else { return nil }
        return browser?.fileURL(of: id) ?? fileURL
    }

    var shareLink: some View {
        let hasSingleSelection = (browser?.selection.count ?? items.count) == 1
        let item = hasSingleSelection && pageItems.count == 1 ? pageItems.first : nil
        return ItemShareLink(item: item, fileURL: selectedFileURL, library: library)
            .help("Share…")
            .accessibilityIdentifier("ShareToolbar")
    }

    @ViewBuilder var detailsButton: some View {
        if details.isCustomizingLayout {
            LayoutDoneButton(details: details, editor: editor)
        } else {
            Button("Details", systemImage: "sidebar.right") { details.isPresented.toggle() }
                .help(details.isPresented ? "Hide Details" : "Show Details")
                // An index page shows the container chosen in its table, so it has details whatever items are selected.
                .disabled(browser?.showsSidebarIndex != true && (browser?.selection.count ?? items.count) != 1)
                .accessibilityIdentifier("DetailsToggle")
        }
    }

    var ids: Set<ItemID> { browser.map(\.selection) ?? Set(items.map(\.id)) }

    func command(_ command: ItemCommand) -> some View {
        ItemCommandButton(
            command: command, context: ItemCommandContext(library: library, ids: ids, browser: browser, editor: editor, details: details, fileURL: selectedFileURL),
            editor: editor)
    }

    func withUndo<Content: View>(@ViewBuilder _ content: @escaping (UndoManager?) -> Content) -> some View {
        UndoManagerReader(content: content)
    }

    var moreMenu: some View {
        let isShowingSelection = (browser?.selection.count ?? pageItems.count) == pageItems.count
        return MoreMenu(
            ids: ids,
            pageItems: isShowingSelection ? pageItems : [],
            fileURL: selectedFileURL, browser: browser, editor: editor)
    }
}

/// Hands a toolbar item the window's undo manager, which toolbar content cannot read for itself.
private struct UndoManagerReader<Content: View>: View {
    @Environment(\.undoManager) private var undoManager
    @ViewBuilder let content: (UndoManager?) -> Content

    var body: some View { content(undoManager) }
}

/// What else can be done to the item shown, as Notes keeps it under its More button.
private struct MoreMenu: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    /// Everything selected, files too; the windows it opens, the share it makes and the collection actions take them all.
    let ids: Set<ItemID>
    let pageItems: [Item]
    let fileURL: URL?
    let browser: Browser?
    let editor: EditorController?
    @AppStorage(PageKey.cornerShowsFormats) private var showsFormats = true
    @AppStorage(PageKey.cornerShowsTextSize) private var showsTextSize = true
    @AppStorage(PageKey.cornerShowsFocus) private var showsFocus = true

    private var context: ItemCommandContext {
        ItemCommandContext(library: library, ids: ids, browser: browser, editor: editor, details: details, fileURL: fileURL)
    }

    private func command(_ command: ItemCommand) -> some View {
        ItemCommandButton(command: command, context: context, editor: editor)
    }

    private var pageLayout: ItemPageLayout {
        context.item.flatMap { library.pageLayout(of: $0) } ?? .text
    }

    /// The corner's controls the person turned off in Settings > Editor, for the page this window shows.
    private var cornerControlsInMore: [PageCornerButton] {
        let context = context
        guard let details, let item = context.item, context.showsPage, !context.hidesCorner, let library = context.library else { return [] }
        return PageCorner.inMore(
            layout: library.pageLayout(of: item), hasReader: details.pageLook?.item == item.id,
            canWrite: item.isWritable && editor != nil, file: details.fileViewing(of: item.id)?.kind,
            shows: PageCornerChoice(formats: showsFormats, textSize: showsTextSize, focus: showsFocus))
    }

    var body: some View {
        let item = pageItems.count == 1 ? pageItems.first : nil
        Menu("More", systemImage: "ellipsis") {
            command(.open)
            command(.openAsModal)
            command(.openAsFullPage)
            command(.openInNewWindow)
            command(.quickLook)
            command(.openOriginal)
            command(.openInBrowser)
            ItemShareLink(item: item, fileURL: fileURL, library: library, showsIcon: false)
            command(.copyLink)
            Divider()
            ItemOrganizeActions(ids: ids, undoManager: undoManager, keepsPlace: true)
            CollectionActions(selection: ids, details: details, undoManager: undoManager)
            Divider()
            command(.addAttachment)
            Divider()
            Menu("Page Width", systemImage: "arrow.left.and.right") {
                PageWidthOptions().pickerStyle(.inline).labelsHidden()
            }
            command(.toggleSource)
            command(.toggleReader)
            ForEach(cornerControlsInMore, id: \.self) { button in
                switch button {
                case .formats: command(.toggleFormats)
                case .textSize:
                    Menu("Text Size", systemImage: "textformat.size") { TextSizeOptions() }
                        .disabled(!PageCorner.sizesText(layout: pageLayout, look: details?.pageLook?.mode))
                case .focus: command(.toggleFocus)
                case .look, .pages, .zoom: EmptyView()
                }
            }
            Divider()
            command(.print)
            command(.exportPDF)
            Divider()
            ItemRemoveActions(ids: ids, undoManager: undoManager, keepsPlace: true)
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityIdentifier("MoreToolbar")
    }
}
