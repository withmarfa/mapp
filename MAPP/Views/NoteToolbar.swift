import SwiftUI

/// A window's toolbar, which a person can change with Customize Toolbar. Each split view the main window mounts keeps a
/// layout of its own (`WindowToolbarLayout`), since the system reshuffles a saved layout when one identifier moves between
/// split views. Nothing else in a window may declare a plain `toolbar`, which turns customization off for the whole window.
///
/// The defaults run New Item at the leading side when the sidebar is hidden, then Search, the table's Filter and View
/// Options, View As, Share and More, and Details at the far right. In the list Search and View Options are the list
/// column's (`ListToolbar`). Format and `ExtraToolbarItems` start in the tray.
struct WindowToolbar: CustomizableToolbarContent {
    @CurrentLibrary private var library
    @AppStorage(InterfaceKey.showsScrolledTitle) private var showsScrolledTitle = true
    let browser: Browser?
    let items: [Item]
    /// Nil for a file in a window of its own, which has no editor.
    let editor: EditorController?
    let details: DetailsPresentation
    var fileURL: URL?
    var showsCreation = false
    /// Whether the list column holds Search and View Options, which otherwise come here.
    var hasListColumn = false

    var body: some CustomizableToolbarContent {
        let tools = ItemToolbarActions(library: library, browser: browser, items: items, editor: editor, details: details, fileURL: fileURL)
        let showsItem = browser?.showsSidebarIndex != true
        let opensFromCollection = browser.map { $0.usesCollection && !$0.showsCollection } == true && !hasListColumn
        ToolbarItem(id: "newItem") {
            NewItemButton(browser: browser)
        }
        .hidden(!showsCreation)
        // A navigation item that is merely hidden still moves the title in a collection, so these two come and go.
        if let browser, opensFromCollection {
            ToolbarItem(id: "backToCollection", placement: .navigation) {
                Button(String(localized: browser.viewMode.backTitle), systemImage: "chevron.backward") { browser.returnToCollection() }
                    .accessibilityIdentifier("BackToGallery")
            }
            .customizationBehavior(.disabled)
        }
        // In the list the item stays in the toolbar while the page's title is in view and only its text goes, rather
        // than the item being hidden and shown as the page scrolls. A hidden item keeps no place at the detail
        // column's leading edge, so the first time it was shown it could be laid out from the list column's side,
        // under that column's buttons. Only the editor's page scrolls its header away; any other page keeps its title
        // in view, so a stale flag from the note shown before it must not show the title.
        if hasListColumn || browser == nil {
            ToolbarItem(id: "scrolledTitle") {
                ScrolledItemTitle(title: editor?.isHeaderScrolledAway == true && tools.visibleNote != nil ? tools.notes.first?.title ?? "" : "")
            }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
            .hidden(!showsScrolledTitle || tools.notes.count != 1 || browser?.showsCollection == true)
        } else if opensFromCollection, showsScrolledTitle, editor?.isHeaderScrolledAway == true, tools.visibleNote != nil {
            ToolbarItem(id: "scrolledTitle", placement: .navigation) {
                ScrolledItemTitle(title: tools.notes.first?.title ?? "")
            }
            .sharedBackgroundVisibility(.hidden)
            .customizationBehavior(.disabled)
        }
        ToolbarSpacer(.flexible)
        if let browser, !hasListColumn {
            ViewToolbarItems(browser: browser, layout: .item, isHidden: opensFromCollection)
            ToolbarSpacer(.fixed)
                .hidden(opensFromCollection || !showsItem)
        }
        ToolbarItem(id: "format") {
            if let editor { FormatMenu(editor: editor, note: tools.editableNote) }
        }
            .defaultCustomization(.hidden)
            .hidden(browser?.showsCollection == true || !showsItem)
        if let browser {
            ToolbarItem(id: "viewMode") { ViewModeMenu(browser: browser) }
                .hidden(!showsItem)
            ToolbarSpacer(.fixed)
                .hidden(!showsItem)
        }
        ToolbarItem(id: "share") { tools.shareLink }
            .hidden(!showsItem)
        ToolbarItem(id: "more") {
            tools.moreMenu.disabled(items.isEmpty)
        }
        .hidden(!showsItem)
        ToolbarSpacer(.fixed)
            .hidden(tools.showsInspector || !showsItem)
        ToolbarItem(id: "details") { tools.detailsButton }
            .hidden(tools.showsInspector || !showsItem)
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
        ToolbarItem(id: "versionHistory") { tools.withUndo { VersionHistoryButton(ids: tools.ids, details: tools.details, undoManager: $0) } }
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
        ToolbarItem(id: "delete") { tools.withUndo { NoteRemoveActions(ids: tools.ids, undoManager: $0, keepsPlace: true) } }
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
        let editor = tools.editableNote == nil ? nil : tools.editor
        Toggle(isOn: Binding { editor.map { format.isActive(in: $0.caret) } ?? false } set: { _ in editor?.apply(format) }) {
            Label { Text(format.title) } icon: { Image(systemName: symbol) }
        }
        .disabled(editor?.canApply(format) != true)
    }
}

/// The saved toolbars of the main window, one for each split view it mounts. All of a split view's columns name the same
/// one.
enum WindowToolbarLayout {
    static let list = "main"
    static let index = "index"

    static func collection(_ mode: ItemViewMode) -> String { "collection.\(mode)" }
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
            .accessibilityHidden(title.isEmpty)
    }
}

/// Details above the inspector column, where the system sets a toolbar declared inside the inspector's content, so the
/// inspector can always be closed whatever a person's layout holds. It contributes nothing while the inspector is
/// closed, because the system keeps a closed inspector's toolbar and would show a second Details beside the page's.
struct InspectorToolbar: CustomizableToolbarContent {
    let details: DetailsPresentation
    let editor: EditorController?

    var body: some CustomizableToolbarContent {
        if details.isPresented {
            ToolbarItem(id: "inspectorDetails") {
                DetailsToggle(details: details, editor: editor)
            }
            .customizationBehavior(.disabled)
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

    @ViewBuilder var detailsButton: some View {
        if details.isCustomizingLayout {
            LayoutDoneButton(details: details, editor: editor)
        } else {
            Button("Details", systemImage: "sidebar.right") { details.isPresented.toggle() }
                .help(details.isPresented ? "Hide Details" : "Show Details")
                .disabled((browser?.selection.count ?? items.count) != 1)
                .accessibilityIdentifier("DetailsToggle")
        }
    }

    var ids: Set<ItemID> { browser.map(\.selection) ?? Set(items.map(\.id)) }

    func command(_ command: ItemCommand) -> some View {
        ItemCommandButton(
            command: command, context: ItemCommandContext(library: library, ids: ids, browser: browser, editor: editor, fileURL: selectedFileURL),
            editor: editor)
    }

    func withUndo<Content: View>(@ViewBuilder _ content: @escaping (UndoManager?) -> Content) -> some View {
        UndoManagerReader(content: content)
    }

    var moreMenu: some View {
        let isShowingSelection = (browser?.selection.count ?? notes.count) == notes.count
        return MoreMenu(
            ids: ids,
            notes: isShowingSelection ? notes : [],
            fileURL: selectedFileURL, browser: browser, editor: editor)
    }
}

/// Hands a toolbar item the window's undo manager, which toolbar content cannot read for itself.
private struct UndoManagerReader<Content: View>: View {
    @Environment(\.undoManager) private var undoManager
    @ViewBuilder let content: (UndoManager?) -> Content

    var body: some View { content(undoManager) }
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
            command(.quickLook)
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
