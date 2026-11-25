import SwiftUI
import UniformTypeIdentifiers

/// The buttons of a window's toolbar, and nothing else: the top row draws the title and the views in the content
/// (`TopRow`), under the window's hidden title. A list has Search, View and Panel; an item's page has Favorite, Share
/// and More as one group, then Panel. A person cannot rearrange them. Every action is a menu command too.
/// Library › Types, Collections and Sources have Search alone, as they have no view to set up. Format and the Reader and
/// Original switch are in the page's corner (`ItemCorner`), not here.
struct WindowToolbar: ToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let browser: Browser?
    let items: [Item]
    /// Nil for a file in a window of its own, which has no editor.
    let editor: EditorController?
    let details: DetailsPresentation
    var fileURL: URL?
    /// Whether the list column holds Search and View, which otherwise come here.
    var hasListColumn = false
    /// Whether Back and Forward are in the window, which a page opened from a layout then needs no Back of its own beside.
    var hasHistory = false
    /// Whether Back and Forward lead this column, because the sidebar that holds them is closed.
    var leadsWithHistory = false

    var body: some ToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
        let isIndex = browser?.showsPlaceIndex == true
        let opensFromCollection = browser?.isCollectionItemPresented == true && !hasListColumn
        let editsView = browser?.showsViewPanel == true
        // A list beside its page has the page's buttons here; a list that spans the window has Search and View.
        let listsHere = browser != nil && !isIndex && !hasListColumn && !opensFromCollection
        let showsActions = !isIndex && !listsHere && !editsView
        let showsDetails = !tools.showsInspector
        if let browser, leadsWithHistory {
            ToolbarItem(placement: .navigation) { SidebarHistory(browser: browser) }
                .sharedBackgroundVisibility(.hidden)
        }
        if let browser, opensFromCollection, !hasHistory {
            ToolbarItem(placement: .navigation) {
                // A plain arrow with no label: it goes back to wherever the page was opened from.
                Button("Back", systemImage: "chevron.backward") { browser.returnToCollection() }
                    .labelStyle(.iconOnly)
                    .help("Back")
                    .accessibilityIdentifier("BackToGallery")
            }
        }
        // A window of its own has no top row, so the page's title is an item of its toolbar once its head has scrolled.
        if browser == nil, showsScrolledTitle || tools.isFocused, let head = tools.scrolledPageTitle {
            ToolbarItem {
                ScrolledItemTitle(title: head.title, icon: head.icon, showsIcon: true, subtitle: head.subtitle)
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarSpacer(.flexible)
        if let browser, isIndex {
            ViewToolbarItems(browser: browser, layout: .item, offersView: false)
        } else if let browser, listsHere {
            ViewToolbarItems(browser: browser, layout: .item)
        }
        if showsActions {
            ToolbarItemGroup {
                tools.withUndo { FavoriteButton(ids: tools.ids, undoManager: $0) }
                tools.shareLink
                tools.moreMenu.disabled(items.isEmpty)
            }
        }
        // With the panel open its own toolbar holds its button over the panel, so a gap stands before it either way.
        if showsActions || (showsDetails && (listsHere || isIndex)) { ToolbarSpacer(.fixed) }
        if showsDetails {
            ToolbarItem { tools.detailsButton }
        }
    }
}

/// Back or Forward through the places a window has shown, in one capsule.
struct SidebarHistory: View {
    @CurrentLibrary private var library
    let browser: Browser

    /// The height of the toolbar's own glass.
    private static let height: CGFloat = 36

    var body: some View {
        HStack(spacing: 0) {
            Button("Back", systemImage: "chevron.backward") { browser.stepBack(in: library) }
                .disabled(!browser.canStepBack(in: library))
                .help("Back")
                .accessibilityIdentifier("SidebarBack")
            Button("Forward", systemImage: "chevron.forward") { browser.stepForward(in: library) }
                .disabled(!browser.canStepForward(in: library))
                .help("Forward")
                .accessibilityIdentifier("SidebarForward")
        }
        .labelStyle(.iconOnly)
        .frame(height: Self.height)
        .glassEffect(.regular.interactive(), in: .capsule)
        .accessibilityElement(children: .contain)
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
struct InspectorToolbar: ToolbarContent {
    @CurrentLibrary private var library
    let details: DetailsPresentation
    let editor: EditorController?
    var browser: Browser?

    var body: some ToolbarContent {
        if details.isPresented, browser?.isModalPresented != true {
            if let browser, details.isEditingView, let panel = browser.viewPanel {
                ViewPanelToolbar(browser: browser, panel: panel, editor: editor)
            } else {
                ToolbarItem {
                    DetailsToggle(details: details)
                }
            }
        }
    }
}

/// The Details button, over the panel while it is open and beside the page while it is closed: one toggle either way,
/// so VoiceOver reads it as on or off.
struct DetailsToggle: View {
    let details: DetailsPresentation

    var body: some View {
        Toggle("Details", systemImage: "sidebar.right", isOn: Binding { details.isPresented } set: { details.isPresented = $0 })
            // Gray while on, as every on button is, rather than the accent color.
            .tint(.secondary)
            .help(details.isPresented ? "Hide Details" : "Show Details")
            .accessibilityIdentifier("DetailsToggle")
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

    /// What the top row shows of the page once its head has scrolled away, and nil while the head shows. The one place the
    /// row reads it, so the page's own report (`DetailsPresentation`) replaces these four reads in one step.
    var scrolledPageTitle: (title: String, icon: String?, subtitle: String?)? {
        guard hasHeaderAway else { return nil }
        return (scrolledTitle, scrolledIcon, scrolledSubtitle)
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
    var editableItem: Item? { visibleItem.flatMap { $0.allows(.text) ? $0 : nil } }

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

    var detailsButton: some View {
        DetailsToggle(details: details).disabled((browser?.selection.count ?? items.count) != 1)
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
            PageCornerKind(for: item, in: library, details: details, hasEditor: editor != nil),
            shows: PageCornerChoice(formats: showsFormats, textSize: showsTextSize, focus: showsFocus))
    }

    var body: some View {
        let item = pageItems.count == 1 ? pageItems.first : nil
        Menu("More", systemImage: "ellipsis") {
            Group {
                command(.open)
                command(.openBesideList)
                command(.openAsModal)
                command(.openAsFullPage)
                command(.openInNewWindow)
                command(.quickLook)
                command(.openOutside)
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
                    case .open, .look, .pages, .zoom: EmptyView()
                    }
                }
                Divider()
                command(.print)
                command(.exportPDF)
                Divider()
                ItemMoveActions(ids: ids, undoManager: undoManager, keepsPlace: true)
                ItemRemoveActions(ids: ids, undoManager: undoManager, keepsPlace: true)
            }
            // On macOS a menu item draws its symbol only when the menu asks for it. The menu's own label stays a symbol.
            .labelStyle(.titleAndIcon)
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityIdentifier("MoreToolbar")
    }
}
