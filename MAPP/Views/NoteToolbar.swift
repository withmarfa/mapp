import SwiftUI

/// The page's toolbar: View As, Share and More, and, at the far right, Details,
/// which opens the panel at the window's right edge. Format is out of the
/// default toolbar but stays in the Format menu, its shortcuts and the palette, and the toolbar can have it back.
/// While the inspector is open, Share, More and Details sit above it instead (`InspectorToolbar`).
struct NoteToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let browser: Browser?
    let items: [Item]
    /// Nil for a file in a window of its own, which has no editor.
    let editor: EditorController?
    let details: DetailsPresentation
    var fileURL: URL?
    var showsCreation = false

    var body: some CustomizableToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
        ToolbarItem(id: "detailNewItem") {
            NewItemButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(!showsCreation)
        ToolbarItem(id: "scrolledTitle") {
            ScrolledItemTitle(title: tools.notes.first?.title ?? "")
        }
        .sharedBackgroundVisibility(.hidden)
        .customizationBehavior(.disabled)
        .hidden(!showsScrolledTitle || editor?.isHeaderScrolledAway != true || tools.notes.count != 1 || browser?.showsCollection == true)
        ToolbarSpacer(.flexible)
        ToolbarItem(id: "format") {
            if let editor { FormatMenu(editor: editor, note: tools.editableNote) }
        }
            .defaultCustomization(.hidden)
            .hidden(browser?.showsCollection == true)
        ToolbarItem(id: "viewMode") {
            if let browser { ViewModeMenu(browser: browser) }
        }
        .hidden(browser == nil)
        ToolbarSpacer(.fixed)
            .hidden(browser == nil || tools.showsInspector)
        ToolbarItem(id: "share") { tools.shareLink }
            .hidden(tools.showsInspector)
        ToolbarItem(id: "more") {
            tools.moreMenu.disabled(items.isEmpty)
        }
        .hidden(tools.showsInspector)
        ToolbarSpacer(.fixed)
            .hidden(tools.showsInspector)
        ToolbarItem(id: "details") { tools.detailsButton }
            .hidden(tools.showsInspector)
    }
}

/// The title of the note on the page, in the toolbar once the page's header has scrolled away.
struct ScrolledItemTitle: View {
    let title: String

    /// The most room a title takes, so a long one never crowds the buttons beside it.
    static let widest: CGFloat = 300

    var body: some View {
        Text(title)
            .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: Self.widest, alignment: .leading)
            // The toolbar sizes an item from what it reports, and the title would otherwise report whatever width it
            // was last offered: a stale or still-growing one while the item is placed shows as "14…". Fixed, it always
            // reports the width its own text needs, up to `widest`, which a long title then ends in an ellipsis at.
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityIdentifier("ScrolledItemTitle")
    }
}

/// Share, More and Details above the inspector column, where the system sets a toolbar declared inside the inspector's
/// content. Details is on while the inspector is open and is never dimmed, so the inspector can always be closed.
/// It contributes nothing while the inspector is closed, because the system keeps a closed inspector's toolbar
/// and would show the actions a second time beside the page's own.
struct InspectorToolbar: ToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser?
    let items: [Item]
    let editor: EditorController?
    let details: DetailsPresentation
    var fileURL: URL?

    var body: some ToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
        if tools.showsInspector {
            ToolbarItemGroup {
                tools.shareLink
                tools.moreMenu
                    .disabled(items.isEmpty)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                DetailsToggle(details: details)
            }
        }
    }
}

/// The Details button of a toolbar above the inspector: on, because the inspector is open.
struct DetailsToggle: View {
    let details: DetailsPresentation

    var body: some View {
        Toggle("Details", systemImage: "sidebar.right", isOn: Binding { details.isPresented } set: { details.isPresented = $0 })
            .help("Hide Details")
            .accessibilityIdentifier("DetailsToggle")
    }
}

/// The toolbar of every view that spans the window (gallery, table, board and timeline), one for the view and the
/// page it opens, so the order across its single column keeps New Item at the leading side when the sidebar is
/// hidden. At the trailing side, always in this order: Search, the table's Filter and View Options
/// (`CurrentViewOptions`), then View As, Share and More, and Details. The list has the same order across its two
/// columns (`ListToolbar`, `NoteToolbar`). Opened on an item, Search, Filter and View Options give way.
struct GalleryToolbar: ToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    @Bindable var browser: Browser
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation
    var showsCreation = true

    // Every item but the navigation ones stays in the toolbar and is hidden when it does not apply, as the page's
    // toolbar does (`NoteToolbar`). The toolbar then keeps its shape as a place or a layout changes, instead of being
    // rebuilt.
    var body: some ToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details)
        ToolbarItem(id: "collectionNewItem") { NewItemButton(browser: browser) }
            .hidden(!showsCreation)
        // A navigation item that is merely hidden still moves the title in a collection, so these two come and go.
        if !browser.showsCollection {
            ToolbarItem(placement: .navigation) {
                Button(String(localized: browser.viewMode.backTitle), systemImage: "chevron.backward") { browser.returnToCollection() }
                    .accessibilityIdentifier("BackToGallery")
            }
            if showsScrolledTitle, editor.isHeaderScrolledAway, tools.notes.count == 1 {
                ToolbarItem(placement: .navigation) {
                    ScrolledItemTitle(title: tools.notes.first?.title ?? "")
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
        ToolbarSpacer(.flexible)
        ColumnSearch(
            isExpanded: $browser.isSearchExpanded,
            text: $browser.searchText,
            prompt: String(localized: "Search"),
            layout: .item,
            focusRequests: browser.searchFocusRequests,
            onDown: { browser.focusRequest = .list }
        ) {
            if browser.viewMode == .table { ItemTableFilterMenu(browser: browser) }
            ViewOptionsMenu(browser: browser)
        }
        .hidden(!browser.showsCollection)
        ToolbarSpacer(.fixed)
            .hidden(!browser.showsCollection)
        ToolbarItem(id: "collectionViewMode") { ViewModeMenu(browser: browser) }
        // Keep the controls in place when selection clears. They move above an open inspector.
        ToolbarSpacer(.fixed)
            .hidden(details.isPresented)
        ToolbarItemGroup {
            tools.shareLink
            tools.moreMenu
                .disabled(browser.selection.isEmpty)
        }
        .hidden(details.isPresented)
        ToolbarSpacer(.fixed)
            .hidden(details.isPresented)
        ToolbarItem {
            tools.detailsButton
        }
        .hidden(details.isPresented)
    }
}

private struct ItemToolbarActions {
    let library: any ItemLibrary
    let browser: Browser?
    let items: [Item]
    let editor: EditorController?
    let details: DetailsPresentation
    let fileURL: URL?
    /// The selected items that are not files, sorted out once, since a selection can hold every item in the library.
    let notes: [Item]

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
        notes = items.filter { !$0.isFile }
    }
    var showsInspector: Bool { details.isPresented }

    var visibleNote: Item? {
        guard browser?.showsPage != false,
              (browser?.selection.count ?? notes.count) == 1, notes.count == 1,
              let note = notes.first, let editor, editor.hasNote, editor.noteID == note.id else { return nil }
        return note
    }

    /// Formatting acts only on the writable note currently visible in the editor.
    var editableNote: Item? { visibleNote.flatMap { $0.isWritable ? $0 : nil } }

    private var selectedFileURL: URL? {
        guard (browser?.selection.count ?? items.count) == 1,
              let id = browser?.selection.first ?? items.first?.id else { return nil }
        return browser?.fileURL(of: id) ?? fileURL
    }

    var shareLink: some View {
        let hasSingleSelection = (browser?.selection.count ?? items.count) == 1
        let note = hasSingleSelection && notes.count == 1 ? notes.first : nil
        return NoteShareLink(share: NoteShare(note: note, fileURL: selectedFileURL, in: library))
            .help("Share…")
            .accessibilityIdentifier("ShareToolbar")
    }

    var detailsButton: some View {
        Button("Details", systemImage: "sidebar.right") { details.isPresented.toggle() }
            .help(details.isPresented ? "Hide Details" : "Show Details")
            .disabled((browser?.selection.count ?? items.count) != 1)
            .accessibilityIdentifier("DetailsToggle")
    }

    var moreMenu: some View {
        let isShowingSelection = (browser?.selection.count ?? notes.count) == notes.count
        return MoreMenu(
            ids: browser.map(\.selection) ?? Set(items.map(\.id)),
            notes: isShowingSelection ? notes : [],
            fileURL: selectedFileURL, browser: browser, editor: editor)
    }
}

/// Text styles and emphasis, as Notes offers them under Aa.
private struct FormatMenu: View {
    let editor: EditorController
    let note: Item?

    var body: some View {
        Menu("Format", systemImage: "textformat") {
            ForEach([Format.title, .heading, .subheading, .body], id: \.self, content: toggle)
            Divider()
            ForEach([Format.bold, .italic, .strikethrough, .code], id: \.self, content: toggle)
            Divider()
            ForEach([Format.bulletList, .orderedList, .checklist], id: \.self, content: toggle)
            Button("Table", systemImage: "tablecells") { editor.apply(.table) }
                // A table is inserted beside another table, never inside one.
                .disabled(!editor.canApply(.table))
        }
        .menuIndicator(.hidden)
        .help("Format")
        .accessibilityIdentifier("FormatToolbar")
        .disabled(note == nil)
    }

    private func toggle(_ format: Format) -> some View {
        Toggle(isOn: Binding { format.isActive(in: editor.caret) } set: { _ in editor.apply(format) }) {
            Text(format.title)
        }.disabled(!editor.canApply(format))
    }
}

/// What else can be done to the item shown, as Notes keeps it under its More button.
private struct MoreMenu: View {
    @CurrentLibrary private var library
    @Environment(\.undoManager) private var undoManager
    @Environment(DetailsPresentation.self) private var details: DetailsPresentation?
    /// Everything selected, files too; the windows it opens, the share it makes and the collection actions take them all.
    let ids: Set<ItemID>
    let notes: [Item]
    let fileURL: URL?
    let browser: Browser?
    let editor: EditorController?

    private func command(_ command: ItemCommand) -> some View {
        ItemCommandButton(
            command: command, context: ItemCommandContext(library: library, ids: ids, browser: browser, editor: editor, fileURL: fileURL),
            editor: editor)
    }

    var body: some View {
        let note = notes.count == 1 ? notes.first : nil
        Menu("More", systemImage: "ellipsis") {
            command(.openInNewWindow)
            command(.openOriginal)
            command(.openInBrowser)
            NoteShareLink(share: NoteShare(note: note, fileURL: fileURL, in: library), showsIcon: false)
            Divider()
            NoteOrganizeActions(ids: ids, undoManager: undoManager, keepsPlace: true)
            CollectionActions(selection: ids, details: details, undoManager: undoManager)
            Divider()
            command(.addAttachment)
            Divider()
            Menu("Page Width", systemImage: "arrow.left.and.right") {
                PageWidthOptions().pickerStyle(.inline).labelsHidden()
            }
            command(.toggleSource)
            Divider()
            command(.print)
            command(.exportPDF)
            Divider()
            NoteRemoveActions(ids: ids, undoManager: undoManager, keepsPlace: true)
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityIdentifier("MoreToolbar")
    }
}
