import SwiftUI

/// The page's toolbar: View As, Share and More, and, at the far right, Details,
/// which opens the panel at the window's right edge. Format is out of the
/// default toolbar but stays in the Format menu, its shortcuts and the palette, and the toolbar can have it back.
/// While the inspector is open, Share, More and Details sit above it instead (`InspectorToolbar`).
struct NoteToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser?
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation
    var fileURL: URL?
    var showsCreation = false

    private var tools: ItemToolbarActions {
        ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
    }

    var body: some CustomizableToolbarContent {
        ToolbarItem(id: "detailNewItem") {
            NewItemButton(browser: browser)
        }
        .customizationBehavior(.disabled)
        .hidden(!showsCreation)
        ToolbarItem(id: "scrolledTitle") {
            Text(tools.notes.first?.title ?? "")
                .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityIdentifier("ScrolledItemTitle")
        }
        .sharedBackgroundVisibility(.hidden)
        .customizationBehavior(.disabled)
        .hidden(!editor.isHeaderScrolledAway || tools.notes.count != 1 || browser?.showsCollection == true)
        ToolbarSpacer(.flexible)
        ToolbarItem(id: "format") { FormatMenu(editor: editor, note: tools.editableNote) }
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

/// Share, More and Details above the inspector column, where the system sets a toolbar declared inside the inspector's
/// content. Details is on while the inspector is open and is never dimmed, so the inspector can always be closed.
/// It contributes nothing while the inspector is closed, because the system keeps a closed inspector's toolbar
/// and would show the actions a second time beside the page's own.
struct InspectorToolbar: ToolbarContent {
    @CurrentLibrary private var library
    let browser: Browser?
    let items: [Item]
    let editor: EditorController
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

/// The gallery's and the table's toolbar, one for the collection and the page it opens, so the order across its
/// single column keeps New Item at the leading side when the sidebar is hidden. At the trailing side, Search and
/// View Options precede View As, Share and More, and Details. The table brings its own View Options
/// (`ItemTableControls`). Opened on an item, View Options and Search give way.
struct GalleryToolbar<Options: View>: ToolbarContent {
    @CurrentLibrary private var library
    @Bindable var browser: Browser
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation
    /// The width the search field spans when it is out.
    let columnWidth: CGFloat
    var showsCreation = true
    @ViewBuilder let options: () -> Options

    var body: some ToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details)
        if showsCreation {
            ToolbarItem(id: "collectionNewItem") { NewItemButton(browser: browser) }
        }
        if !browser.showsCollection, editor.isHeaderScrolledAway, tools.notes.count == 1 {
            ToolbarItem(placement: .navigation) {
                Text(tools.notes.first?.title ?? "")
                    .interfaceFont(.headline).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: 220, alignment: .leading)
                    .accessibilityIdentifier("ScrolledItemTitle")
            }
            .sharedBackgroundVisibility(.hidden)
        }
        ToolbarSpacer(.flexible)
        if browser.showsCollection {
            ColumnSearch(
                isExpanded: $browser.isSearchExpanded,
                text: $browser.searchText,
                prompt: String(localized: "Search"),
                columnWidth: columnWidth,
                focusRequests: browser.searchFocusRequests,
                onDown: { browser.focusRequest = .list }
            ) {
                options()
            }
            ToolbarSpacer(.fixed)
        }
        ToolbarItem(id: "collectionViewMode") { ViewModeMenu(browser: browser) }
        // Keep the controls in place when selection clears. They move above an open inspector.
        if !details.isPresented {
            ToolbarSpacer(.fixed)
            ToolbarItemGroup {
                tools.shareLink
                tools.moreMenu
                    .disabled(browser.selection.isEmpty)
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                tools.detailsButton
            }
        }
    }
}

private struct ItemToolbarActions {
    let library: any ItemLibrary
    let browser: Browser?
    let items: [Item]
    let editor: EditorController
    let details: DetailsPresentation
    var fileURL: URL?

    var notes: [Item] { items.filter { !$0.isFile } }
    var showsInspector: Bool { details.isPresented }

    var visibleNote: Item? {
        guard browser?.showsCollection != true,
              (browser?.selection.count ?? notes.count) == 1, notes.count == 1,
              let note = notes.first, editor.hasNote, editor.noteID == note.id else { return nil }
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
            fileURL: selectedFileURL, browser: browser, editor: editor, visibleNote: visibleNote, editableNote: editableNote)
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
    @Environment(\.openWindow) private var openWindow
    /// Everything selected, files too; the windows it opens and the share it makes take them all.
    let ids: Set<ItemID>
    let notes: [Item]
    let fileURL: URL?
    let browser: Browser?
    let editor: EditorController
    /// The note on the page, which Print, Export and the source view act on.
    let visibleNote: Item?
    let editableNote: Item?

    var body: some View {
        let noteIDs = Set(notes.map(\.id))
        let note = notes.count == 1 ? notes.first : nil
        Menu("More", systemImage: "ellipsis") {
            if browser != nil {
                Button("Open in New Window", systemImage: "macwindow") {
                    for id in library.idsForWindows(ids) { openWindow(value: id) }
                }
                .keyboardShortcut("o")
                .disabled(ids.isEmpty)
            }
            NoteShareLink(share: NoteShare(note: note, fileURL: fileURL, in: library), showsIcon: false)
            Divider()
            NoteOrganizeActions(ids: noteIDs, undoManager: undoManager, keepsPlace: true)
            Divider()
            Button("Add Attachment…", systemImage: "paperclip") { editor.isChoosingImages = true }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(editableNote == nil)
            Divider()
            Menu("Page Width", systemImage: "arrow.left.and.right") {
                PageWidthOptions().pickerStyle(.inline).labelsHidden()
            }
            Button(editor.caret.sourceMode ? "Show Formatted Text" : "Show Markdown Source", systemImage: "doc.plaintext") {
                editor.setSourceMode(!editor.caret.sourceMode)
            }
            .disabled(visibleNote == nil)
            Divider()
            Button("Print…", systemImage: "printer") { editor.printNote() }
                .keyboardShortcut("p")
                .disabled(visibleNote == nil)
            Button("Export as PDF…", systemImage: "doc.richtext") { editor.exportPDF() }
                .disabled(visibleNote == nil)
            Divider()
            NoteRemoveActions(ids: noteIDs, undoManager: undoManager, keepsPlace: true)
        }
        .menuIndicator(.hidden)
        .help("More")
        .accessibilityIdentifier("MoreToolbar")
    }
}
